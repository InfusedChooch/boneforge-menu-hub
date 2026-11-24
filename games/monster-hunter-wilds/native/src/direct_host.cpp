// SPDX-License-Identifier: GPL-3.0-or-later
#include "direct_host.hpp"
#ifdef GHL_EMBEDDED_RUNTIME
#include "runtime_host.hpp"
#endif
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdio>
#include <cstdint>
#include <cstring>
#ifndef GHL_DIRECT_HOST_TESTING
#include <ShlObj.h>
#include <filesystem>
#include <string>
#endif

extern "C" {
#include <lua.h>
#include <lauxlib.h>
bool ghl_qol_initialize(const REFrameworkPluginInitializeParam* param);
}

namespace ghl {
namespace {
// The selected profile was identified by the loaded module's exact SHA-256.
// Validation retains the host's original tables and locked main-state lookup.
static_assert(sizeof(REFrameworkPluginInitializeParam) == 40);
static_assert(sizeof(REFrameworkPluginFunctions) == 18 * sizeof(void*));
static_assert(sizeof(REFrameworkSDKData) == 14 * sizeof(void*));

std::atomic<DirectHostStatus> status{DirectHostStatus::idle};
std::atomic_bool stop_requested{false};
std::atomic<DWORD> initialization_thread{0};
const REFrameworkPluginInitializeParam* active_param{};

bool read_bytes(const void* address, void* out, size_t bytes) noexcept {
    SIZE_T copied{};
    return address && ReadProcessMemory(GetCurrentProcess(), address, out, bytes, &copied) && copied == bytes;
}
template<class T> bool read_value(const void* address, T& out) noexcept {
    return read_bytes(address, &out, sizeof(out));
}
const unsigned char* at(HMODULE host, size_t rva) noexcept {
    return reinterpret_cast<const unsigned char*>(host) + rva;
}
bool image_memory(HMODULE host, const void* address, size_t bytes, bool executable = false) noexcept {
#ifdef GHL_DIRECT_HOST_TESTING
    (void)host;
#endif
    MEMORY_BASIC_INFORMATION info{};
    if (!address || !bytes || !VirtualQuery(address, &info, sizeof(info))
        || info.State != MEM_COMMIT || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
    const auto start = reinterpret_cast<uintptr_t>(address);
    const auto end = reinterpret_cast<uintptr_t>(info.BaseAddress) + info.RegionSize;
    if (start >= end || bytes > end - start) return false;
#ifndef GHL_DIRECT_HOST_TESTING
    if (info.Type != MEM_IMAGE || info.AllocationBase != host) return false;
#endif
    if (executable && !(info.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY))) {
#ifndef GHL_DIRECT_HOST_TESTING
        return false;
#endif
    }
    return true;
}

// The copied values are used only for validation. Initialization receives the
// host's original table, not a reconstructed SDK or modified callback table.
bool inspect_api(HMODULE host, const HostProfile& profile, const REFrameworkPluginInitializeParam*& param, bool& ready) noexcept {
    param = nullptr;
    ready = false;
    IMAGE_DOS_HEADER dos{};
    IMAGE_NT_HEADERS64 nt{};
    if (!image_memory(host, host, sizeof(dos)) || !read_value(host, dos)
        || dos.e_magic != IMAGE_DOS_SIGNATURE || dos.e_lfanew < static_cast<LONG>(sizeof(dos)) || dos.e_lfanew > 0x10000
        || !read_value(at(host, static_cast<size_t>(dos.e_lfanew)), nt)
        || nt.Signature != IMAGE_NT_SIGNATURE || nt.FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64
        || nt.OptionalHeader.Magic != IMAGE_NT_OPTIONAL_HDR64_MAGIC
        || nt.OptionalHeader.SizeOfImage != profile.image_size
        || nt.FileHeader.NumberOfSections != profile.section_count) return false;
    REFrameworkPluginInitializeParam copy{};
    REFrameworkPluginVersion version{};
    if (!image_memory(host, at(host, profile.param_rva), sizeof(copy)) || !read_value(at(host, profile.param_rva), copy)
        || copy.version != reinterpret_cast<const REFrameworkPluginVersion*>(at(host, profile.version_rva))
        || copy.functions != reinterpret_cast<const REFrameworkPluginFunctions*>(at(host, profile.functions_rva))
        || copy.renderer_data != reinterpret_cast<const REFrameworkRendererData*>(at(host, profile.renderer_rva))
        || copy.sdk != reinterpret_cast<const REFrameworkSDKData*>(at(host, profile.sdk_rva))
        || !read_value(copy.version, version)
        || version.major != 1 || version.minor != 15 || version.patch != 0) return false;
    std::array<uintptr_t, 18> functions{};
    std::array<uintptr_t, 14> sdk{};
    if (!read_bytes(copy.functions, functions.data(), sizeof(functions))
        || !read_bytes(copy.sdk, sdk.data(), sizeof(sdk))) return false;
    for (size_t i = 0; i < functions.size(); ++i) {
        if (functions[i] != reinterpret_cast<uintptr_t>(at(host, profile.function_rvas[i]))
            || !image_memory(host, reinterpret_cast<void*>(functions[i]), 1, true)) return false;
    }
    for (size_t i = 0; i < sdk.size(); ++i) {
        if (sdk[i] != reinterpret_cast<uintptr_t>(at(host, profile.sdk_rvas[i]))
            || !image_memory(host, reinterpret_cast<void*>(sdk[i]), sizeof(void*))) return false;
    }
    param = reinterpret_cast<const REFrameworkPluginInitializeParam*>(at(host, profile.param_rva));
    // This field is assigned by initialize_plugins after renderer/SDK setup.
    // A loaded module or an ImGui context alone is not a readiness signal.
    if (!copy.reframework_module) return true;
    if (copy.reframework_module != host) return false;
    REFrameworkRendererData renderer{};
    if (!read_value(copy.renderer_data, renderer)) return false;
    char game_name[64]{};
    if (!version.game_name || !read_bytes(version.game_name, game_name, sizeof(game_name))
        || !std::memchr(game_name, '\0', sizeof(game_name)) || !game_name[0]) return false;
    ready = renderer.renderer_type == REFRAMEWORK_RENDERER_D3D12
        && renderer.device && renderer.swapchain && renderer.command_queue
        && std::strcmp(game_name, "REFramework") != 0;
    return true;
}

struct LuaLock {
    const REFrameworkPluginFunctions* functions;
    explicit LuaLock(const REFrameworkPluginFunctions* value) : functions(value) { functions->lock_lua(); }
    ~LuaLock() { functions->unlock_lua(); }
};

void write_startup_report(const char* phase, const char* reason) noexcept {
#ifndef GHL_DIRECT_HOST_TESTING
    // Only called by the worker or its one-shot frame callback, never DllMain.
    // The two strings are fixed ASCII messages from this file, not user input.
    try {
        PWSTR documents{};
        if (FAILED(SHGetKnownFolderPath(FOLDERID_Documents, KF_FLAG_CREATE, nullptr, &documents))) return;
        struct KnownFolder { PWSTR value; ~KnownFolder() { CoTaskMemFree(value); } } folder{documents};
        const auto directory = std::filesystem::path(documents) / L"WildsMenu" / L"diagnostics";
        std::filesystem::create_directories(directory);
        const auto destination = directory / L"GHLQOL-startup.json";
        const DWORD attributes = GetFileAttributesW(destination.c_str());
        if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) return;
        SYSTEMTIME time{};
        GetSystemTime(&time);
        char report[1024]{};
        const int length = std::snprintf(report, sizeof(report),
            "{\n  \"format\": 1,\n  \"status\": \"%s\",\n  \"reason\": \"%s\",\n  \"utc\": \"%04u-%02u-%02uT%02u:%02u:%02uZ\",\n  \"thread_id\": %lu\n}\n",
            phase, reason, time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond, GetCurrentThreadId());
        if (length <= 0 || static_cast<size_t>(length) >= sizeof(report)) return;
        const auto temporary = directory / (L"GHLQOL-startup-" + std::to_wstring(GetCurrentProcessId()) + L".tmp");
        HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) return;
        DWORD written{};
        const bool complete = WriteFile(file, report, static_cast<DWORD>(length), &written, nullptr)
            && written == static_cast<DWORD>(length) && FlushFileBuffers(file);
        CloseHandle(file);
        if (!complete || !MoveFileExW(temporary.c_str(), destination.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
            DeleteFileW(temporary.c_str());
    } catch (...) {}
#else
    (void)phase;
    (void)reason;
#endif
}

void fail(const char* message, const REFrameworkPluginInitializeParam* param = nullptr) noexcept {
    status.store(DirectHostStatus::failed, std::memory_order_release);
    OutputDebugStringA(message);
    write_startup_report("failed", message);
    if (param && param->functions && param->functions->log_error) {
        try { param->functions->log_error("[GHL QOL Direct] %s", message); } catch (...) {}
    }
}

int initialize_on_frame(lua_State*) noexcept {
    if (stop_requested.load(std::memory_order_acquire)) return 0;
    DirectHostStatus expected = DirectHostStatus::queued;
    if (!status.compare_exchange_strong(expected, DirectHostStatus::initializing)) return 0;
    initialization_thread.store(GetCurrentThreadId(), std::memory_order_release);
    try {
        // Hooks.cpp:954..959,981..988 calls run_imgui_frame(false) BEFORE the
        // BeginRendering pre-entry callbacks. Our ScriptState frame therefore
        // precedes D2D's on_begin_rendering on that same call stack. The host
        // m_imgui_mtx also serializes D3D present. APIProxy callbacks themselves
        // cannot be used here: they hold a shared callback mutex, and registering
        // another API callback requires it exclusively. A worker holding Lua
        // while registering would invert D2D's API-mutex -> Lua-lock order.
        LuaLock lock(active_param->functions);
        if (ghl_qol_initialize(active_param)) {
            status.store(DirectHostStatus::active, std::memory_order_release);
            active_param->functions->log_info("[GHL QOL Direct] Initialized on the host Lua frame; no bootstrap DLL");
            write_startup_report("active", "Initialized on the host Lua frame without a bootstrap DLL");
        } else {
            fail("Frame initialization was refused", active_param);
        }
    } catch (...) {
        fail("Exception during frame initialization; no retry", active_param);
    }
    initialization_thread.store(0, std::memory_order_release);
    return 0;
}

int install_frame_callback(lua_State* state) {
    constexpr char script[] =
        "local initialize = ...\n"
        "assert(type(re) == 'table' and type(re.on_frame) == 'function', 'Host frame API unavailable')\n"
        "local pending = true\n"
        "re.on_frame(function()\n"
        "  if pending then pending = false; initialize() end\n"
        "end)\n";
    if (luaL_loadbuffer(state, script, sizeof(script) - 1, "GHLQOL-direct-host") != LUA_OK) return lua_error(state);
    lua_pushcfunction(state, initialize_on_frame);
    lua_call(state, 1, 0);
    return 0;
}
int frame_api_ready(lua_State* state) {
    lua_getglobal(state, "re");
    if (!lua_istable(state, -1)) { lua_pushboolean(state, false); return 1; }
    lua_getfield(state, -1, "on_frame");
    lua_pushboolean(state, lua_isfunction(state, -1));
    return 1;
}
bool has_frame_api(lua_State* state) noexcept {
    const int top = lua_gettop(state);
    lua_pushcfunction(state, frame_api_ready);
    const bool ready = lua_pcall(state, 0, 1, 0) == LUA_OK && lua_toboolean(state, -1);
    lua_settop(state, top);
    return ready;
}
bool enqueue_frame(lua_State* state, const REFrameworkPluginInitializeParam* param) noexcept {
    if (!state || !param || !has_frame_api(state)) return false;
    const int top = lua_gettop(state);
    active_param = param;
    status.store(DirectHostStatus::queued, std::memory_order_release);
    lua_pushcfunction(state, install_frame_callback);
    const bool ok = lua_pcall(state, 0, 0, 0) == LUA_OK;
    lua_settop(state, top);
    if (!ok) fail("Could not enqueue host-frame initialization", param);
    return ok;
}
DirectHostStatus await_frame(ULONGLONG deadline, const REFrameworkPluginInitializeParam* param) noexcept {
    while (direct_host_status() == DirectHostStatus::queued && !stop_requested.load(std::memory_order_acquire)) {
        const ULONGLONG now = GetTickCount64();
        if (now >= deadline) {
            // A reset can discard the queued Lua closure before its first frame.
            // Never register another initializer; a normal restart is required.
            DirectHostStatus expected = DirectHostStatus::queued;
            if (status.compare_exchange_strong(expected, DirectHostStatus::failed)) {
                OutputDebugStringA("[GHL QOL Direct] Queued frame was not delivered; restart required");
                write_startup_report("failed", "Queued frame was not delivered; restart required");
                if (param && param->functions->log_error) {
                    try { param->functions->log_error("[GHL QOL Direct] Queued frame was not delivered; restart required"); } catch (...) {}
                }
            }
            break;
        }
        Sleep(static_cast<DWORD>(std::min<ULONGLONG>(50, deadline - now)));
    }
    if (stop_requested.load(std::memory_order_acquire)) {
        DirectHostStatus expected = DirectHostStatus::queued;
        status.compare_exchange_strong(expected, DirectHostStatus::stopped);
    }
    return direct_host_status();
}

lua_State* main_lua_state(HMODULE host, const HostProfile& profile) noexcept {
    // Called only while the public lock_lua() protects ScriptRunner state/reset.
    uintptr_t runner{}, state{}, lua{};
    if (!image_memory(host, at(host, profile.script_runner_rva), sizeof(runner))
        || !read_value(at(host, profile.script_runner_rva), runner) || !runner
        || !read_value(reinterpret_cast<void*>(runner + profile.runner_state_offset), state) || !state
        || !read_value(reinterpret_cast<void*>(state + profile.state_lua_offset), lua) || !lua) return nullptr;
    return reinterpret_cast<lua_State*>(lua);
}

DirectHostStatus run_worker(unsigned int timeout_ms, HMODULE candidate = nullptr) noexcept {
    const ULONGLONG deadline = GetTickCount64() + timeout_ms;
    HMODULE host = candidate;
    const HostProfile* profile = nullptr;
    try {
        while (!stop_requested.load(std::memory_order_acquire) && GetTickCount64() < deadline) {
            if (!host) host = GetModuleHandleW(L"dinput8.dll");
            if (host && !profile) {
                HMODULE pinned{};
                if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                    reinterpret_cast<LPCWSTR>(host), &pinned) || pinned != host || !(profile = identify_host(host))) {
                    fail("Unsupported REFramework binary; no private state accessed");
                    return direct_host_status();
                }
            }
            if (profile) {
                const REFrameworkPluginInitializeParam* param{};
                bool ready{};
                if (!inspect_api(host, *profile, param, ready)) {
                    fail("Selected host API layout failed validation");
                    return direct_host_status();
                }
                if (ready) {
                    bool queued = false;
                    {
                        LuaLock lock(param->functions);
                        if (lua_State* state = main_lua_state(host, *profile); state && has_frame_api(state)) {
                            if (!enqueue_frame(state, param)) return direct_host_status();
                            queued = true;
                        }
                    }
                    // Never wait while holding Lua or retaining a native state
                    // pointer. The closure alone owns the scheduled callback.
                    if (queued) return await_frame(deadline, param);
                }
            }
            const ULONGLONG now = GetTickCount64();
            if (now < deadline) Sleep(static_cast<DWORD>(std::min<ULONGLONG>(50, deadline - now)));
        }
        if (stop_requested.load(std::memory_order_acquire)) status.store(DirectHostStatus::stopped);
        else fail("Timed out waiting for a supported host and its main Lua state");
    } catch (...) {
        fail("Exception while preparing direct host startup; no retry");
    }
    return direct_host_status();
}
DWORD WINAPI worker_entry(void* root) noexcept {
    HMODULE pinned{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(root), &pinned) || pinned != root) {
        fail("Could not retain the root DLL for callback lifetime");
        return 0;
    }
    try {
#ifdef GHL_EMBEDDED_RUNTIME
        if (start_builtin_runtime(pinned)) {
            await_frame(GetTickCount64() + 180000, nullptr);
            return 0;
        }
#endif
        run_worker(180000);
    } catch (...) { fail("Private runtime startup failed; no fallback or duplicate runtime"); }
    return 0;
}
} // namespace

void queue_direct_host(HMODULE root) noexcept {
    DirectHostStatus expected = DirectHostStatus::idle;
    if (!root || !status.compare_exchange_strong(expected, DirectHostStatus::waiting)) return;
    // A newly created thread's user entry runs after serialized DLL attach
    // notifications. Do not wait, load libraries or touch host/Lua here.
    HANDLE worker = CreateThread(nullptr, 0, worker_entry, root, 0, nullptr);
    if (worker) CloseHandle(worker);
    else {
        // This caller is DllMain: do not invoke Shell32 or filesystem reporting.
        status.store(DirectHostStatus::failed);
        OutputDebugStringA("[GHL QOL Direct] Could not queue direct host worker");
    }
}
void stop_direct_host() noexcept { stop_requested.store(true, std::memory_order_release); }
DirectHostStatus direct_host_status() noexcept { return status.load(std::memory_order_acquire); }
bool direct_host_initializing() noexcept {
    return direct_host_status() == DirectHostStatus::initializing
        && initialization_thread.load(std::memory_order_acquire) == GetCurrentThreadId();
}

#ifdef GHL_EMBEDDED_RUNTIME
bool enqueue_builtin_frame(lua_State* state, const REFrameworkPluginInitializeParam* param) noexcept {
    if (!param || !builtin_runtime_host(static_cast<HMODULE>(param->reframework_module))
        || direct_host_status() != DirectHostStatus::waiting) return false;
    return has_frame_api(state) && enqueue_frame(state, param);
}
#endif

#ifdef GHL_DIRECT_HOST_TESTING
namespace direct_host_test {
bool inspect(HMODULE host, const HostProfile& profile, const REFrameworkPluginInitializeParam** param, bool* ready) noexcept {
    return param && ready && inspect_api(host, profile, *param, *ready);
}
lua_State* main_state(HMODULE host, const HostProfile& profile, const REFrameworkPluginInitializeParam* param) noexcept {
    LuaLock lock(param->functions);
    return main_lua_state(host, profile);
}
bool enqueue(lua_State* state, const REFrameworkPluginInitializeParam* param) noexcept { return enqueue_frame(state, param); }
DirectHostStatus await_frame(unsigned int timeout_ms) noexcept { return ghl::await_frame(GetTickCount64() + timeout_ms, nullptr); }
DirectHostStatus run(unsigned int timeout_ms, HMODULE candidate) noexcept {
    status.store(DirectHostStatus::waiting);
    return run_worker(timeout_ms, candidate);
}
void reset() noexcept {
    status.store(DirectHostStatus::idle);
    stop_requested.store(false);
    initialization_thread.store(0);
    active_param = nullptr;
}
}
#endif
} // namespace ghl
