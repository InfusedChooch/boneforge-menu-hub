// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>

struct lua_State;

namespace ghl {

struct CursorPlatform {
    void* context{};
    void* (*window)(void*) noexcept{};
    bool (*post_visibility)(void*, void*, bool) noexcept{};
    void (*log)(void*, const char*, bool warning) noexcept{};
};

struct CursorStatus {
    std::uint32_t request_count{};
    bool requested{};
    bool capturing{};
    bool visible{};
    bool window_available{};
    std::uint64_t blocked_messages{};
    std::uint64_t visibility_posts{};
    std::uint64_t visibility_failures{};
};

class Cursor {
public:
    explicit Cursor(CursorPlatform platform) noexcept : platform_(platform) {}
    void request(bool acquire) noexcept;
    void capture(bool enabled) noexcept;
    bool is_requested() const noexcept;
    bool is_capturing() const noexcept;
    bool on_message(unsigned int message) noexcept;
    void on_present() noexcept;
    void reset() noexcept;
    CursorStatus status() const noexcept;

private:
    static constexpr std::uint64_t count_mask = 0xffffffffu;
    static constexpr std::uint64_t capture_bit = std::uint64_t{1} << 32;
    bool post(void* window, bool visible) noexcept;
    void log(const char* message, bool warning = false) const noexcept;
    CursorPlatform platform_;
    // Keep the reference count and capture flag in one atomic value so the
    // final release cannot race with capture(true) and leave input captured.
    std::atomic<std::uint64_t> state_{};
    std::atomic<std::uint64_t> blocked_messages_{};
    std::atomic<std::uint64_t> visibility_posts_{};
    std::atomic<std::uint64_t> visibility_failures_{};
    std::atomic_bool visible_{};
    std::atomic_bool window_available_{};
    std::mutex visibility_mutex_;
    void* presented_window_{};
    bool post_failed_{};
};

// Only the root package installs this provider. The regular plugin continues
// using its separately installed ref_cursor.dll.
bool register_cursor_lua(lua_State* state, Cursor& cursor) noexcept;

} // namespace ghl
