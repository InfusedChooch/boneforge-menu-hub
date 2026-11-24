// SPDX-License-Identifier: GPL-3.0-or-later
#include "cursor.hpp"

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace ghl {

void Cursor::request(bool acquire) noexcept {
    auto previous = state_.load(std::memory_order_acquire);
    for (;;) {
        const auto count = previous & count_mask;
        const auto next_count = acquire ? (count == count_mask ? count : count + 1)
            : (count == 0 ? 0 : count - 1);
        const auto next = next_count | (next_count ? previous & capture_bit : 0);
        if (state_.compare_exchange_weak(previous, next, std::memory_order_acq_rel)) return;
    }
}

void Cursor::capture(bool enabled) noexcept {
    auto previous = state_.load(std::memory_order_acquire);
    for (;;) {
        const auto next = enabled && (previous & count_mask)
            ? previous | capture_bit : previous & ~capture_bit;
        if (state_.compare_exchange_weak(previous, next, std::memory_order_acq_rel)) return;
    }
}

bool Cursor::is_requested() const noexcept {
    return (state_.load(std::memory_order_acquire) & count_mask) != 0;
}

bool Cursor::is_capturing() const noexcept {
    const auto value = state_.load(std::memory_order_acquire);
    return (value & count_mask) != 0 && (value & capture_bit) != 0;
}

bool Cursor::on_message(unsigned int message) noexcept {
    const bool mouse_message = message == 0x00ff || message == 0x0200
        || (message >= 0x0201 && message <= 0x020c) || message == 0x020e;
    if (!mouse_message || !is_capturing()) return true;
    blocked_messages_.fetch_add(1, std::memory_order_relaxed);
    return false;
}

void Cursor::log(const char* message, bool warning) const noexcept {
    if (platform_.log) platform_.log(platform_.context, message, warning);
}

bool Cursor::post(void* window, bool visible) noexcept {
    if (!window || !platform_.post_visibility
        || !platform_.post_visibility(platform_.context, window, visible)) {
        visibility_failures_.fetch_add(1, std::memory_order_relaxed);
        if (!post_failed_) log("Cursor visibility message failed; will retry", true);
        post_failed_ = true;
        return false;
    }
    visibility_posts_.fetch_add(1, std::memory_order_relaxed);
    if (post_failed_) log("Cursor visibility messages recovered");
    post_failed_ = false;
    visible_.store(visible, std::memory_order_release);
    log(visible ? "Cursor visibility requested" : "Cursor visibility released");
    return true;
}

void Cursor::on_present() noexcept {
    try {
        std::lock_guard<std::mutex> guard(visibility_mutex_);
        void* window = platform_.window ? platform_.window(platform_.context) : nullptr;
        window_available_.store(window != nullptr, std::memory_order_release);
        const bool requested = is_requested();
        const bool visible = visible_.load(std::memory_order_acquire);
        if (visible && (!requested || (window && window != presented_window_))) {
            if (!post(presented_window_, false)) return;
            presented_window_ = nullptr;
        }
        if (requested && window && !visible_.load(std::memory_order_acquire)) {
            if (post(window, true)) presented_window_ = window;
        }
    } catch (...) {
        log("Cursor presentation failed", true);
    }
}

void Cursor::reset() noexcept {
    state_.store(0, std::memory_order_release);
    try {
        std::lock_guard<std::mutex> guard(visibility_mutex_);
        if (visible_.load(std::memory_order_acquire)) {
            if (post(presented_window_, false)) presented_window_ = nullptr;
            // Retain a failed hide so the next present can retry it.
        }
    } catch (...) {
        log("Cursor reset failed", true);
    }
}

CursorStatus Cursor::status() const noexcept {
    const auto value = state_.load(std::memory_order_acquire);
    CursorStatus result{};
    result.request_count = static_cast<std::uint32_t>(value & count_mask);
    result.requested = result.request_count != 0;
    result.capturing = result.requested && (value & capture_bit) != 0;
    result.visible = visible_.load(std::memory_order_acquire);
    result.window_available = window_available_.load(std::memory_order_acquire);
    result.blocked_messages = blocked_messages_.load(std::memory_order_relaxed);
    result.visibility_posts = visibility_posts_.load(std::memory_order_relaxed);
    result.visibility_failures = visibility_failures_.load(std::memory_order_relaxed);
    return result;
}

namespace {

Cursor& from_lua(lua_State* state) {
    return *static_cast<Cursor*>(lua_touserdata(state, lua_upvalueindex(1)));
}
int lua_request(lua_State* state) { from_lua(state).request(lua_toboolean(state, 1) != 0); return 0; }
int lua_capture(lua_State* state) { from_lua(state).capture(lua_toboolean(state, 1) != 0); return 0; }
int lua_requested(lua_State* state) { lua_pushboolean(state, from_lua(state).is_requested()); return 1; }
int lua_capturing(lua_State* state) { lua_pushboolean(state, from_lua(state).is_capturing()); return 1; }
int lua_status(lua_State* state) {
    const auto value = from_lua(state).status();
    lua_createtable(state, 0, 11);
    lua_pushliteral(state, "integrated"); lua_setfield(state, -2, "backend");
    lua_pushinteger(state, value.request_count); lua_setfield(state, -2, "request_count");
    lua_pushboolean(state, value.requested); lua_setfield(state, -2, "requested");
    lua_pushboolean(state, value.capturing); lua_setfield(state, -2, "capturing");
    lua_pushboolean(state, value.visible); lua_setfield(state, -2, "visible");
    lua_pushboolean(state, value.window_available); lua_setfield(state, -2, "window_available");
    lua_pushinteger(state, static_cast<lua_Integer>(value.blocked_messages)); lua_setfield(state, -2, "blocked_messages");
    lua_pushinteger(state, static_cast<lua_Integer>(value.visibility_posts)); lua_setfield(state, -2, "visibility_posts");
    lua_pushinteger(state, static_cast<lua_Integer>(value.visibility_failures)); lua_setfield(state, -2, "visibility_failures");
    lua_pushboolean(state, true); lua_setfield(state, -2, "message_filter");
    lua_pushboolean(state, false); lua_setfield(state, -2, "code_patch");
    return 1;
}
void bind(lua_State* state, Cursor* cursor, const char* name, lua_CFunction function) {
    lua_pushlightuserdata(state, cursor);
    lua_pushcclosure(state, function, 1);
    lua_setfield(state, -2, name);
}
int install(lua_State* state) {
    auto* cursor = static_cast<Cursor*>(lua_touserdata(state, 1));
    lua_getglobal(state, "refcursor");
    if (!lua_isnil(state, -1)) {
        if (lua_istable(state, -1)) {
            lua_getfield(state, -1, "request");
            if (lua_iscfunction(state, -1) && lua_tocfunction(state, -1) == lua_request
                && lua_getupvalue(state, -1, 1) && lua_touserdata(state, -1) == cursor) return 0;
        }
        return luaL_error(state, "refcursor is already owned by another provider");
    }
    lua_pop(state, 1);
    lua_createtable(state, 0, 5);
    bind(state, cursor, "request", lua_request);
    bind(state, cursor, "capture", lua_capture);
    bind(state, cursor, "is_requested", lua_requested);
    bind(state, cursor, "is_capturing", lua_capturing);
    bind(state, cursor, "status", lua_status);
    lua_setglobal(state, "refcursor");
    return 0;
}

} // namespace

bool register_cursor_lua(lua_State* state, Cursor& cursor) noexcept {
    if (!state) return false;
    const int top = lua_gettop(state);
    bool success = false;
    try {
        lua_pushcfunction(state, install);
        lua_pushlightuserdata(state, &cursor);
        success = lua_pcall(state, 1, 0, 0) == LUA_OK;
    } catch (...) {}
    lua_settop(state, top);
    return success;
}

} // namespace ghl
