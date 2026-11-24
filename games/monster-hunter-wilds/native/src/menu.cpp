// SPDX-License-Identifier: GPL-3.0-or-later
#include "host_ui.hpp"
extern "C" {
#include <lua.h>
}
#include <algorithm>
#include <cmath>
#include <iterator>
#include <string>

namespace ghl {
namespace {
void field(lua_State* L, int table, const char* key) {
    table = lua_absindex(L, table);
    lua_pushstring(L, key);
    lua_rawget(L, table);
}
void set_bool(lua_State* L, int table, const char* key, bool value) {
    table = lua_absindex(L, table);
    lua_pushstring(L, key); lua_pushboolean(L, value); lua_rawset(L, table);
}
void set_number(lua_State* L, int table, const char* key, double value) {
    table = lua_absindex(L, table);
    lua_pushstring(L, key); lua_pushnumber(L, value); lua_rawset(L, table);
}
void set_string(lua_State* L, int table, const char* key, const char* value) {
    table = lua_absindex(L, table);
    lua_pushstring(L, key); lua_pushstring(L, value); lua_rawset(L, table);
}
void clear(lua_State* L, int table, const char* key) {
    table = lua_absindex(L, table);
    lua_pushstring(L, key); lua_pushnil(L); lua_rawset(L, table);
}
bool boolean(lua_State* L, int table, const char* key) {
    field(L, table, key); const bool value = lua_toboolean(L, -1) != 0;
    lua_pop(L, 1); return value;
}
double number(lua_State* L, int table, const char* key, double fallback) {
    field(L, table, key);
    const double value = lua_type(L, -1) == LUA_TNUMBER ? lua_tonumber(L, -1) : fallback;
    lua_pop(L, 1); return std::isfinite(value) ? value : fallback;
}
std::string string(lua_State* L, int table, const char* key, const char* fallback = "") {
    field(L, table, key);
    const char* value = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : nullptr;
    std::string result = value ? value : fallback;
    lua_pop(L, 1); return result;
}
std::string error_text(lua_State* L) {
    const char* value = lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : nullptr;
    return value ? std::string(value).substr(0, 2000) : "Lua page returned a non-text error";
}
bool method(lua_State* L, const char* name, int results, std::string& error) {
    field(L, 1, name);
    if (!lua_isfunction(L, -1)) {
        lua_pop(L, 1); error = std::string("Menu method missing: ") + name; return false;
    }
    lua_pushvalue(L, 1);
    if (lua_pcall(L, 1, results, 0) != LUA_OK) {
        error = error_text(L); lua_pop(L, 1); return false;
    }
    return true;
}
int unavailable(lua_State* L, const std::string& error) {
    lua_pushboolean(L, false);
    if (error.empty()) return 1;
    lua_pushlstring(L, error.data(), error.size()); return 2;
}

struct Color { ImGuiCol slot; const char* key; float r, g, b, a; };
// GHL's native skin is independent of RefShell's legacy midnight palette.
const Color palette[] = {
    {ImGuiCol_Text, "text", .94f,.93f,.88f,1},
    {ImGuiCol_TextDisabled, "muted", .62f,.66f,.69f,1},
    {ImGuiCol_WindowBg, "window", .055f,.070f,.085f,.98f},
    {ImGuiCol_ChildBg, "child", .080f,.100f,.118f,1},
    {ImGuiCol_PopupBg, "popup", .060f,.080f,.095f,1},
    {ImGuiCol_Border, "border", .28f,.29f,.26f,1},
    {ImGuiCol_FrameBg, "frame", .045f,.060f,.072f,1},
    {ImGuiCol_FrameBgHovered, "frame_h", .13f,.21f,.24f,1},
    {ImGuiCol_FrameBgActive, "frame_a", .16f,.27f,.29f,1},
    {ImGuiCol_TitleBg, "title", .045f,.055f,.065f,1},
    {ImGuiCol_TitleBgActive, "title_active", .045f,.055f,.065f,1},
    {ImGuiCol_TitleBgCollapsed, "title_closed", .045f,.055f,.065f,1},
    {ImGuiCol_CheckMark, "check", .90f,.73f,.40f,1},
    {ImGuiCol_SliderGrab, "grab", .72f,.56f,.28f,1},
    {ImGuiCol_SliderGrabActive, "accent", .94f,.78f,.45f,1},
    {ImGuiCol_Button, "button", .12f,.16f,.18f,1},
    {ImGuiCol_ButtonHovered, "button_h", .18f,.27f,.29f,1},
    {ImGuiCol_ButtonActive, "button_a", .30f,.26f,.16f,1},
    {ImGuiCol_Header, "header", .12f,.16f,.18f,1},
    {ImGuiCol_HeaderHovered, "header_h", .16f,.25f,.28f,1},
    {ImGuiCol_HeaderActive, "accent_d", .30f,.26f,.16f,1},
    {ImGuiCol_Separator, "sep", .42f,.35f,.22f,.75f},
    {ImGuiCol_ResizeGrip, "resize", .48f,.40f,.25f,.65f},
    {ImGuiCol_ResizeGripHovered, "resize_h", .90f,.73f,.40f,1},
    {ImGuiCol_ResizeGripActive, "resize_a", .94f,.78f,.45f,1},
    {ImGuiCol_ScrollbarBg, "scroll", .045f,.060f,.072f,1},
    {ImGuiCol_ScrollbarGrab, "scroll_grab", .30f,.35f,.36f,1},
    {ImGuiCol_ScrollbarGrabHovered, "scroll_h", .48f,.43f,.31f,1},
    {ImGuiCol_ScrollbarGrabActive, "selected", .54f,.44f,.25f,1},
};

class Theme {
    lua_State* state_;
    int previous_;
public:
    explicit Theme(lua_State* L) : state_(L) {
        field(L, 1, "_draw_theme"); previous_ = lua_gettop(L);
        field(L, 1, "_native_theme");
        if (!lua_istable(L, -1)) {
            lua_pop(L, 1); lua_createtable(L, 0, static_cast<int>(std::size(palette)));
            for (const auto& entry : palette) {
                lua_createtable(L, 4, 0);
                const float values[] = {entry.r, entry.g, entry.b, entry.a};
                for (int i = 0; i < 4; ++i) { lua_pushnumber(L, values[i]); lua_rawseti(L, -2, i + 1); }
                lua_setfield(L, -2, entry.key);
            }
            lua_pushvalue(L, -1); lua_setfield(L, 1, "_native_theme");
        }
        lua_setfield(L, 1, "_draw_theme");
        for (const auto& entry : palette)
            ui().push_style_color(entry.slot, ImVec4(entry.r, entry.g, entry.b, entry.a));
        ui().push_style_var_float(ImGuiStyleVar_WindowRounding, 3);
        ui().push_style_var_float(ImGuiStyleVar_FrameRounding, 2);
        ui().push_style_var_float(ImGuiStyleVar_ChildRounding, 2);
        ui().push_style_var_vec2(ImGuiStyleVar_WindowPadding, ImVec2(12, 12));
        ui().push_style_var_vec2(ImGuiStyleVar_FramePadding, ImVec2(8, 5));
        ui().push_style_var_vec2(ImGuiStyleVar_ItemSpacing, ImVec2(8, 6));
    }
    ~Theme() {
        ui().pop_style_var(6); ui().pop_style_color(static_cast<int>(std::size(palette)));
        lua_pushvalue(state_, previous_); lua_setfield(state_, 1, "_draw_theme");
        lua_remove(state_, previous_);
    }
};
struct Window { ~Window() { ui().end(); } };
struct Child { ~Child() { ui().end_child(); } };
struct Combo { ~Combo() { ui().end_combo(); } };

std::string tab_name(lua_State* L, int tabs, int index) {
    lua_rawgeti(L, tabs, index);
    std::string name = lua_istable(L, -1) ? string(L, -1, "name", "Page") : "Page";
    lua_pop(L, 1); return name;
}
void navigation(lua_State* L, int tabs, int count, int& active, float height) {
    for (int i = 1; i <= count; ++i) {
        const auto name = tab_name(L, tabs, i);
        if (height > 0) {
            ui().push_style_color(ImGuiCol_Text, i == active ? ImVec4(.94f,.78f,.45f,1) : ImVec4(.78f,.81f,.80f,1));
            ui().push_style_color(ImGuiCol_Header, ImVec4(.25f,.23f,.16f,1));
        }
        if (ui().selectable(name.c_str(), i == active, 0, ImVec2(0, height))) {
            active = i;
            set_number(L, 1, "active_tab", i);
        }
        if (height > 0) ui().pop_style_color(2);
    }
}
void draw_page(lua_State* L, int tabs, int active) {
    lua_rawgeti(L, tabs, active);
    if (!lua_istable(L, -1)) { lua_pop(L, 1); return; }
    field(L, -1, "draw");
    std::string error;
    if (lua_isfunction(L, -1)) {
        field(L, 1, "ui"); lua_pushvalue(L, 1);
        if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
            error = error_text(L); lua_pop(L, 1);
        }
    } else { lua_pop(L, 1); error = "This page has no renderer."; }
    lua_pop(L, 1);
    if (!error.empty()) {
        ui().separator();
        ui().text_unformatted("This page could not be drawn. Other pages remain available.", nullptr);
        ui().push_text_wrap_pos(0);
        ui().text_unformatted(error.c_str(), nullptr);
        ui().pop_text_wrap_pos();
    }
    field(L, 1, "__ghl_native_status");
    if (lua_istable(L, -1)) {
        lua_pushstring(L, "page_error");
        if (error.empty()) lua_pushnil(L); else lua_pushlstring(L, error.data(), error.size());
        lua_rawset(L, -3);
    }
    lua_pop(L, 1);
}
void rectangle(lua_State* L, ImVec2 pos, ImVec2 size) {
    lua_pushstring(L, "_win_rect"); lua_createtable(L, 0, 4);
    set_number(L, -1, "x", pos.x); set_number(L, -1, "y", pos.y);
    set_number(L, -1, "w", size.x); set_number(L, -1, "h", size.y);
    lua_rawset(L, 1);
}
void remember_layout(lua_State* L, ImVec2 size, const std::string& page, bool resized) {
    field(L, 1, "remember_native_layout"); lua_pushvalue(L, 1);
    lua_pushnumber(L, size.x); lua_pushnumber(L, size.y);
    lua_pushlstring(L, page.data(), page.size()); lua_pushboolean(L, resized);
    std::string error;
    if (lua_pcall(L, 5, 0, 0) != LUA_OK) { error = error_text(L); lua_pop(L, 1); }
    field(L, 1, "__ghl_native_status");
    if (lua_istable(L, -1)) {
        if (error.empty()) clear(L, -1, "layout_error"); else set_string(L, -1, "layout_error", error.c_str());
        set_string(L, -1, "skin", "GHL Slate / Gold");
        set_string(L, -1, "layout", size.x >= 600 ? "Sidebar" : "Compact");
        set_number(L, -1, "width", size.x); set_number(L, -1, "height", size.y);
    }
    lua_pop(L, 1);
}
}

int draw_menu(lua_State* L) {
    // false is reserved for failures BEFORE Begin, allowing safe same-frame fallback.
    if (!lua_istable(L, 1)) return unavailable(L, "Native menu expected a menu table");
    if (!ui().get_current_context()) return unavailable(L, "No ImGui context");
    field(L, 1, "cfg"); const int cfg = lua_gettop(L);
    field(L, 1, "tabs"); const int tabs = lua_gettop(L);
    field(L, 1, "ui"); const bool valid_ui = lua_istable(L, -1); lua_pop(L, 1);
    if (!lua_istable(L, cfg) || !lua_istable(L, tabs) || !valid_ui)
        return unavailable(L, "Native menu configuration is incomplete");
    if (!boolean(L, cfg, "open")) { lua_pushboolean(L, true); return 1; }
    std::string error;
    if (!method(L, "refresh_layout", 0, error) || !method(L, "sync_live_layout", 0, error))
        return unavailable(L, error);
    // The optional developer Live workspace keeps its original split-screen layout.
    if (boolean(L, 1, "_live_layout")) return unavailable(L, "");
    const ImVec2 display = ui().get_io()->DisplaySize;
    if (display.x < 240 || display.y < 220) return unavailable(L, "");
    field(L, 1, "remember_native_layout"); const bool can_remember = lua_isfunction(L, -1); lua_pop(L, 1);
    if (!can_remember) return unavailable(L, "Menu method missing: remember_native_layout");
    if (!method(L, "prepare_native_layout", 0, error)) return unavailable(L, error);
    if (!method(L, "current_size", 2, error)) return unavailable(L, error);
    const float requested_w = static_cast<float>(lua_tonumber(L, -2));
    const float requested_h = static_cast<float>(lua_tonumber(L, -1));
    lua_pop(L, 2);
    if (!std::isfinite(requested_w) || !std::isfinite(requested_h) || requested_w <= 0 || requested_h <= 0)
        return unavailable(L, "Invalid menu size");
    field(L, 1, "set_open"); const bool can_close = lua_isfunction(L, -1); lua_pop(L, 1);
    if (!can_close) return unavailable(L, "Menu method missing: set_open");
    const float margin = std::clamp(static_cast<float>(number(L, cfg, "margin", 16)), 0.0f, 100.0f);
    const float max_w = std::max(240.0f, display.x - margin * 2);
    const float max_h = std::max(220.0f, display.y - margin * 2);
    const ImVec2 wanted(std::clamp(requested_w, 240.0f, max_w), std::clamp(requested_h, 220.0f, max_h));
    std::string dock = string(L, 1, "pending_dock");
    if (dock.empty()) dock = string(L, 1, "_dock_override");
    if (dock.empty()) dock = string(L, cfg, "dock", "right");
    const float x = dock == "left" ? margin : dock == "center" ? (display.x - wanted.x) / 2 : display.x - wanted.x - margin;
    const bool layout = boolean(L, 1, "apply_layout") || boolean(L, 1, "pending_dock");
    const bool resize = layout || boolean(L, 1, "pending_size");
    ui().set_next_window_pos(ImVec2(x, std::max(8.0f, margin)), layout ? ImGuiCond_Always : ImGuiCond_FirstUseEver, ImVec2(0, 0));
    ui().set_next_window_size(wanted, resize ? ImGuiCond_Always : ImGuiCond_FirstUseEver);
    ui().set_next_window_size_constraints(ImVec2(240, 220), ImVec2(max_w, max_h), nullptr, nullptr);
    clear(L, 1, "pending_dock"); set_bool(L, 1, "pending_size", false); set_bool(L, 1, "apply_layout", false);
    set_bool(L, 1, "_imgui_hover", false);
    const auto title = string(L, 1, "title", "GHL QOL") + "###GHLQOLNative";
    bool open = true;
    {
        Theme theme(L);
        const bool visible = ui().begin(title.c_str(), &open, ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
        Window window;
        ImVec2 pos, size;
        ui().get_window_pos(&pos); ui().get_window_size(&size);
        field(L, 1, "_win_rect");
        const bool user_resized = !resize && lua_istable(L, -1) &&
            (std::abs(size.x - number(L, -1, "w", size.x)) >= 1 || std::abs(size.y - number(L, -1, "h", size.y)) >= 1);
        lua_pop(L, 1); rectangle(L, pos, size);
        if (pos.x + size.x < 16 || pos.y + size.y < 16 || pos.x >= display.x - 16 || pos.y >= display.y - 16)
            set_bool(L, 1, "apply_layout", true);
        if (visible) {
            const int count = static_cast<int>(std::min<size_t>(lua_rawlen(L, tabs), 256));
            int active = static_cast<int>(std::clamp(number(L, 1, "active_tab", 1), 1.0, static_cast<double>(std::max(1, count))));
            set_number(L, 1, "active_tab", active);
            const bool wide = size.x >= 600;
            if (!wide && count > 0) {
                ui().set_next_item_width(-1);
                if (ui().begin_combo("##ghl_pages", tab_name(L, tabs, active).c_str(), 0)) {
                    Combo combo;
                    navigation(L, tabs, count, active, 0);
                }
                ui().separator();
            }
            ImVec2 available;
            ui().get_content_region_avail(&available);
            const float body_height = std::max(60.0f, available.y - 40);
            if (wide) {
                ui().push_style_color(ImGuiCol_ChildBg, ImVec4(.045f,.060f,.072f,1));
                const bool shown = ui().begin_child("##ghl_navigation", ImVec2(164, body_height), ImGuiChildFlags_Borders | ImGuiChildFlags_AlwaysUseWindowPadding, 0);
                { Child child; if (shown) {
                    ui().push_style_color(ImGuiCol_Text, ImVec4(.94f,.78f,.45f,1));
                    ui().text_unformatted("G H L  Q O L", nullptr);
                    ui().pop_style_color(1);
                    ui().push_style_color(ImGuiCol_Text, ImVec4(.62f,.66f,.69f,1));
                    ui().text_unformatted("HUNTER'S TOOLKIT", nullptr);
                    ui().pop_style_color(1);
                    ui().spacing(); ui().separator(); ui().spacing();
                    navigation(L, tabs, count, active, 32);
                } }
                ui().pop_style_color(1);
                ui().same_line(0, 12);
            }
            const auto selected = count ? tab_name(L, tabs, active) : "No pages";
            const auto child_id = std::string("##ghl_page_") + selected;
            const bool shown = ui().begin_child(child_id.c_str(), ImVec2(0, body_height), ImGuiChildFlags_AlwaysUseWindowPadding, 0);
            {
                Child child;
                if (shown) {
                    if (wide) {
                        ui().push_style_color(ImGuiCol_Text, ImVec4(.94f,.78f,.45f,1));
                        ui().text_unformatted(selected.c_str(), nullptr);
                        ui().pop_style_color(1);
                        ui().separator(); ui().spacing();
                    }
                    if (count) draw_page(L, tabs, active);
                }
            }
            remember_layout(L, size, selected, user_resized);
            ui().spacing();
            ui().get_content_region_avail(&available);
            const bool logs = boolean(L, 1, "show_logs");
            const float button_width = logs ? std::max(1.0f, (available.x - 8) / 2) : available.x;
            if (logs) {
                const bool expanded = boolean(L, 1, "_logs_open");
                if (ui().button(expanded ? "Hide Logs" : "Show Logs", ImVec2(button_width, 30))) set_bool(L, 1, "_logs_open", !expanded);
                ui().same_line(0, 8);
            } else { set_bool(L, 1, "_logs_open", false); }
            if (ui().button("Close", ImVec2(button_width, 30))) open = false;
        }
        if (ui().is_window_hovered(ImGuiHoveredFlags_RootAndChildWindows)) set_bool(L, 1, "_imgui_hover", true);
    }
    // Includes combo popups outside the root rectangle, matching RefShell capture.
    if (ui().is_window_hovered(ImGuiHoveredFlags_AnyWindow)) set_bool(L, 1, "_imgui_hover", true);
    if (!open) {
        field(L, 1, "set_open"); lua_pushvalue(L, 1); lua_pushboolean(L, false);
        if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
            lua_pop(L, 1); set_bool(L, cfg, "open", false); set_bool(L, 1, "dirty", true);
        }
        clear(L, 1, "_win_rect"); set_bool(L, 1, "_imgui_hover", false);
    }
    lua_pushboolean(L, true); return 1;
}
}
