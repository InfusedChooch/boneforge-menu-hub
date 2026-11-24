// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <Windows.h>
#include <imgui.h>

struct lua_State;

namespace ghl {

// Signatures match the pinned host cimgui 1.92.0 exports, not ImGui's C++ API.
struct Ui {
    const char* (*get_version)(){};
    ImGuiContext* (*get_current_context)(){};
    bool (*begin)(const char*, bool*, ImGuiWindowFlags){};
    void (*end)(){};
    bool (*begin_child)(const char*, ImVec2, ImGuiChildFlags, ImGuiWindowFlags){};
    void (*end_child)(){};
    void (*get_window_pos)(ImVec2*){};
    void (*get_window_size)(ImVec2*){};
    void (*get_content_region_avail)(ImVec2*){};
    void (*set_next_window_pos)(ImVec2, ImGuiCond, ImVec2){};
    void (*set_next_window_size)(ImVec2, ImGuiCond){};
    void (*set_next_window_size_constraints)(ImVec2, ImVec2, ImGuiSizeCallback, void*){};
    bool (*selectable)(const char*, bool, ImGuiSelectableFlags, ImVec2){};
    bool (*button)(const char*, ImVec2){};
    void (*text_unformatted)(const char*, const char*){};
    void (*same_line)(float, float){};
    void (*separator)(){};
    void (*spacing)(){};
    void (*push_style_color)(ImGuiCol, ImVec4){};
    void (*pop_style_color)(int){};
    void (*push_style_var_float)(ImGuiStyleVar, float){};
    void (*push_style_var_vec2)(ImGuiStyleVar, ImVec2){};
    void (*pop_style_var)(int){};
    bool (*is_window_hovered)(ImGuiHoveredFlags){};
    ImGuiIO* (*get_io)(){};
    void (*push_id)(int){};
    void (*pop_id)(){};
    void (*set_cursor_pos)(ImVec2){};
    void (*get_cursor_pos)(ImVec2*){};
    float (*get_frame_height)(){};
    bool (*begin_combo)(const char*, const char*, ImGuiComboFlags){};
    void (*end_combo)(){};
    void (*set_next_item_width)(float){};
    void (*push_text_wrap_pos)(float){};
    void (*pop_text_wrap_pos)(){};
};

Ui& ui();
bool initialize_ui(HMODULE host);
int draw_menu(lua_State* state);

} // namespace ghl
