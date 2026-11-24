// SPDX-License-Identifier: GPL-3.0-or-later
#include "host_ui.hpp"
#include "host_profiles.hpp"
#ifdef GHL_EMBEDDED_RUNTIME
#include "runtime_host.hpp"
#endif

#include <atomic>
#include <cstdio>
#include <cstring>
#include <exception>
#ifdef GHL_ROOT_PACKAGE
#include "bootstrap_runtime.hpp"
#include "cursor.hpp"
#include "embedded_lua.hpp"
#include "embedded_storage.hpp"
#include <dxgi.h>
#include "direct_host.hpp"
#endif

extern "C" {
#include <lua.h>
#include <reframework/API.h>
}

namespace {

ghl::Ui host_ui;
std::atomic_bool ui_ready{false};
const REFrameworkPluginFunctions* host_functions = nullptr;
const char* unavailable_reason = "Native UI has not initialized";

#ifdef GHL_ROOT_PACKAGE
const REFrameworkRendererData* cursor_renderer = nullptr;
HMODULE active_runtime_module = nullptr;

void* cursor_window(void*) noexcept {
    if (!cursor_renderer || !cursor_renderer->swapchain) return nullptr;
    DXGI_SWAP_CHAIN_DESC description{};
    auto* swapchain = static_cast<IDXGISwapChain*>(cursor_renderer->swapchain);
    return SUCCEEDED(swapchain->GetDesc(&description)) ? description.OutputWindow : nullptr;
}

bool cursor_post(void*, void* window, bool visible) noexcept {
    return PostMessageW(static_cast<HWND>(window), WM_APP + 1, visible ? 1 : 0, 1) != FALSE;
}

void cursor_log(void*, const char* message, bool warning) noexcept {
    if (!host_functions) return;
    if (warning) {
        if (host_functions->log_warn) host_functions->log_warn("[GHL QOL Cursor] %s", message);
    } else if (host_functions->log_info) host_functions->log_info("[GHL QOL Cursor] %s", message);
}

ghl::Cursor cursor{{nullptr, cursor_window, cursor_post, cursor_log}};

void on_cursor_present() { cursor.on_present(); }
void on_cursor_state_destroyed(lua_State*) { cursor.reset(); }
bool on_cursor_message(void*, unsigned int message, unsigned long long, long long) {
    return cursor.on_message(message);
}
#endif

template <typename Function>
bool resolve(Function& target, HMODULE host, const char* name) {
    const FARPROC address = GetProcAddress(host, name);
    if (!address) {
        unavailable_reason = name;
        if (host_functions && host_functions->log_error) {
            host_functions->log_error("[GHL QOL Native] Missing host export: %s", name);
        }
        return false;
    }
    static_assert(sizeof(target) == sizeof(address), "Windows x64 function pointer size changed");
    std::memcpy(&target, &address, sizeof(target));
    return true;
}

int not_ready(lua_State* state, const char* reason) {
    lua_pushboolean(state, 0);
    lua_pushstring(state, reason);
    return 2;
}

int native_ready(lua_State* state) {
    lua_pushboolean(state, ui_ready.load(std::memory_order_acquire));
    return 1;
}

int native_draw(lua_State* state) {
    if (!ui_ready.load(std::memory_order_acquire)) return not_ready(state, unavailable_reason);
    if (!lua_istable(state, 1)) return not_ready(state, "Native draw expects a menu table");
    if (!host_ui.get_current_context()) return not_ready(state, "Host ImGui context is unavailable");

    // The existing Lua draw callback owns the frame and Lua lock. This bridge
    // neither retains the state nor starts an additional render loop.
    char failure[512]{};
    try {
        return ghl::draw_menu(state);
    } catch (const std::exception& error) {
        std::snprintf(failure, sizeof(failure), "%s", error.what());
    } catch (...) {
        std::snprintf(failure, sizeof(failure), "%s", "Unknown native menu exception");
    }

    // All C++ draw scopes have unwound before Lua's C longjmp. The adapter must
    // defer fallback until the next frame because drawing may already have begun.
    unavailable_reason = "Native menu failed; Lua fallback is required";
    ui_ready.store(false, std::memory_order_release);
    if (host_functions && host_functions->log_error) {
        host_functions->log_error("[GHL QOL Native] Native menu disabled: %s", failure);
    }
    lua_pushstring(state, failure);
    return lua_error(state);
}

void on_lua_state_created(lua_State* state) {
    if (!state) return;
    // REFramework invokes this callback while setting up its Lua state. The
    // functions operate only on the state passed by their caller, including reset.
    lua_createtable(state, 0, 2);
    lua_pushcfunction(state, native_ready);
    lua_setfield(state, -2, "ready");
    lua_pushcfunction(state, native_draw);
    lua_setfield(state, -2, "draw");
    lua_setglobal(state, "ghl_native");
#ifdef GHL_ROOT_PACKAGE
#ifdef GHL_EMBEDDED_RUNTIME
    lua_createtable(state, 0, 2);
    lua_pushstring(state, "integrated-runtime-preview-2"); lua_setfield(state, -2, "variant");
    lua_pushstring(state, ghl::builtin_runtime_host(active_runtime_module) ? "builtin" : "external");
    lua_setfield(state, -2, "backend");
    lua_setglobal(state, "__ghl_runtime");
#endif
    cursor.reset();
    if (!ghl::register_cursor_lua(state, cursor)) {
        if (host_functions && host_functions->log_error) {
            host_functions->log_error("[GHL QOL Cursor] Could not register integrated refcursor; embedded menu startup refused");
        }
        return;
    }
    cursor_log(nullptr, "Integrated refcursor ready; no SetCursorPos patch", false);
    lua_createtable(state, 0, 5);
    for (const char* name : {"root", "settings", "diagnostics", "backups", "legacy_data"}) {
        lua_pushstring(state, ghl::data_path(name));
        lua_setfield(state, -2, name);
    }
    lua_setglobal(state, "__ghl_paths");
    if (!ghl::register_embedded_storage(state)) {
        if (host_functions && host_functions->log_error) host_functions->log_error("[GHL QOL Root] Storage registration failed: %s", ghl::embedded_storage_error());
        return;
    }
    if (!ghl::register_embedded_lua(state) && host_functions && host_functions->log_error) {
        host_functions->log_error("[GHL QOL Root] Embedded Lua registration failed: %s", ghl::embedded_lua_error());
    }
#endif
}

} // namespace

namespace ghl {

Ui& ui() { return host_ui; }

bool initialize_ui(HMODULE host) {
    ui_ready.store(false, std::memory_order_release);
    if (!host) {
        unavailable_reason = "REFramework module handle is unavailable";
        return false;
    }
    Ui candidate{};
#define GHL_RESOLVE(member, symbol) if (!resolve(candidate.member, host, symbol)) return false
    GHL_RESOLVE(get_version, "igGetVersion");
    const char* version = candidate.get_version();
    if (!version || std::strcmp(version, "1.92.0") != 0) {
        unavailable_reason = "Host ImGui version must be 1.92.0";
        return false;
    }
    GHL_RESOLVE(get_current_context, "igGetCurrentContext");
    GHL_RESOLVE(begin, "igBegin");
    GHL_RESOLVE(end, "igEnd");
    GHL_RESOLVE(begin_child, "igBeginChild_Str");
    GHL_RESOLVE(end_child, "igEndChild");
    GHL_RESOLVE(get_window_pos, "igGetWindowPos");
    GHL_RESOLVE(get_window_size, "igGetWindowSize");
    GHL_RESOLVE(get_content_region_avail, "igGetContentRegionAvail");
    GHL_RESOLVE(set_next_window_pos, "igSetNextWindowPos");
    GHL_RESOLVE(set_next_window_size, "igSetNextWindowSize");
    GHL_RESOLVE(set_next_window_size_constraints, "igSetNextWindowSizeConstraints");
    GHL_RESOLVE(selectable, "igSelectable_Bool");
    GHL_RESOLVE(button, "igButton");
    GHL_RESOLVE(text_unformatted, "igTextUnformatted");
    GHL_RESOLVE(same_line, "igSameLine");
    GHL_RESOLVE(separator, "igSeparator");
    GHL_RESOLVE(spacing, "igSpacing");
    GHL_RESOLVE(push_style_color, "igPushStyleColor_Vec4");
    GHL_RESOLVE(pop_style_color, "igPopStyleColor");
    GHL_RESOLVE(push_style_var_float, "igPushStyleVar_Float");
    GHL_RESOLVE(push_style_var_vec2, "igPushStyleVar_Vec2");
    GHL_RESOLVE(pop_style_var, "igPopStyleVar");
    GHL_RESOLVE(is_window_hovered, "igIsWindowHovered");
    GHL_RESOLVE(get_io, "igGetIO_Nil");
    GHL_RESOLVE(push_id, "igPushID_Int");
    GHL_RESOLVE(pop_id, "igPopID");
    GHL_RESOLVE(set_cursor_pos, "igSetCursorPos");
    GHL_RESOLVE(get_cursor_pos, "igGetCursorPos");
    GHL_RESOLVE(get_frame_height, "igGetFrameHeight");
    GHL_RESOLVE(begin_combo, "igBeginCombo");
    GHL_RESOLVE(end_combo, "igEndCombo");
    GHL_RESOLVE(set_next_item_width, "igSetNextItemWidth");
    GHL_RESOLVE(push_text_wrap_pos, "igPushTextWrapPos");
    GHL_RESOLVE(pop_text_wrap_pos, "igPopTextWrapPos");
#undef GHL_RESOLVE
    host_ui = candidate;
    unavailable_reason = "";
    ui_ready.store(true, std::memory_order_release);
    return true;
}

} // namespace ghl

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    if (!version) return;
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name = nullptr;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    if (!param || !param->functions || !param->version || !param->reframework_module) return false;
    host_functions = param->functions;
    if (param->version->major != REFRAMEWORK_PLUGIN_VERSION_MAJOR
        || param->version->minor < REFRAMEWORK_PLUGIN_VERSION_MINOR
        || !host_functions->on_lua_state_created) {
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Native] Unsupported REFramework plugin API");
        return false;
    }

    // The public API version does not cover Lua's private layout. Every accepted
    // profile retains an exact host hash and reviewed Lua/ImGui ABI evidence.
    const auto* profile = ghl::identify_host(static_cast<HMODULE>(param->reframework_module));
    bool builtin = false;
#ifdef GHL_EMBEDDED_RUNTIME
    builtin = ghl::builtin_runtime_host(static_cast<HMODULE>(param->reframework_module));
#endif
    if (!profile && !builtin) {
        if (host_functions->log_error) {
            host_functions->log_error("[GHL QOL Native] No validated host profile matched; Lua bridge was not registered and original UI remains active");
        }
        return false;
    }
    if (profile && host_functions->log_info) {
        host_functions->log_info("[GHL QOL Native] Validated host profile: %s (SHA256 %s)", profile->name, profile->sha256);
    }
    if (builtin && host_functions->log_info) host_functions->log_info("[GHL QOL Native] Using privately linked runtime");
#ifdef GHL_ROOT_PACKAGE
    if (!ghl::direct_host_initializing()) {
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Root] Initialization must come from the validated host-frame handoff; obsolete bootstrap refused");
        return false;
    }
    if (!param->renderer_data || !host_functions->on_present || !host_functions->on_message
        || !host_functions->on_lua_state_destroyed) {
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Cursor] Required host cursor callbacks are unavailable");
        return false;
    }
    if (!ghl::prepare_user_data(param)) {
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Root] Initialization refused: %s", ghl::bootstrap_error());
        return false;
    }
    cursor_renderer = param->renderer_data;
    active_runtime_module = static_cast<HMODULE>(param->reframework_module);
    if (!host_functions->on_present(on_cursor_present)
        || !host_functions->on_message(on_cursor_message)
        || !host_functions->on_lua_state_destroyed(on_cursor_state_destroyed)) {
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Cursor] Could not register host cursor callbacks");
        return false;
    }
#endif
    const bool available = ghl::initialize_ui(static_cast<HMODULE>(param->reframework_module));
    if (!host_functions->on_lua_state_created(on_lua_state_created)) {
        ui_ready.store(false, std::memory_order_release);
        if (host_functions->log_error) host_functions->log_error("[GHL QOL Native] Could not register Lua bridge; fallback remains active");
        return false;
    }
    if (available) {
        if (host_functions->log_info) host_functions->log_info("[GHL QOL Native] Host ImGui 1.92.0 bridge ready");
    } else if (host_functions->log_warn) {
        host_functions->log_warn("[GHL QOL Native] Native UI unavailable (%s); Lua fallback remains active", unavailable_reason);
    }
    return true;
}

#ifdef GHL_ROOT_PACKAGE
extern "C" __declspec(dllexport) bool ghl_qol_initialize(const REFrameworkPluginInitializeParam* param) {
    // A retained 0.0.10 bridge must not consume the one allowed initialization.
    if (!ghl::direct_host_initializing()) return false;
    static std::atomic_bool attempted{false};
    if (attempted.exchange(true)) return false;
    return reframework_plugin_initialize(param);
}
#endif
