// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <Windows.h>
#include <reframework/API.h>
#include "host_profiles.hpp"

namespace ghl {
enum class DirectHostStatus { idle, waiting, queued, initializing, active, failed, stopped };

// Queue only from the static root's process attach. Never wait in DllMain.
void queue_direct_host(HMODULE root) noexcept;
void stop_direct_host() noexcept;
DirectHostStatus direct_host_status() noexcept;
bool direct_host_initializing() noexcept;

#ifdef GHL_DIRECT_HOST_TESTING
namespace direct_host_test {
bool inspect(HMODULE host, const HostProfile& profile, const REFrameworkPluginInitializeParam** param, bool* ready) noexcept;
struct lua_State* main_state(HMODULE host, const HostProfile& profile, const REFrameworkPluginInitializeParam* param) noexcept;
bool enqueue(struct lua_State* state, const REFrameworkPluginInitializeParam* param) noexcept;
DirectHostStatus await_frame(unsigned int timeout_ms) noexcept;
DirectHostStatus run(unsigned int timeout_ms, HMODULE candidate = nullptr) noexcept;
void reset() noexcept;
}
#endif
}
