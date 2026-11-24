// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>

struct lua_State;

namespace ghl {
struct EmbeddedEngine {
    const char* name;
    const unsigned char* data;
    std::size_t size;
};

// Install getters without running engine code. Bytecode is copied into Lua
// closures, so neither the descriptors nor their backing buffers are retained.
bool register_embedded_engines(lua_State* state, const EmbeddedEngine* engines, std::size_t count) noexcept;

// Preload engine getters/modules and schedule one-shot startup.
// The caller owns the Lua state/lock; no state is retained between callbacks.
bool register_embedded_lua(lua_State* state) noexcept;
const char* embedded_lua_error() noexcept;
}
