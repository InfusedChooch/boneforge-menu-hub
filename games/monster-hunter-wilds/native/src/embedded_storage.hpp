// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
struct lua_State;
namespace ghl {
bool register_embedded_storage(lua_State* state) noexcept;
const char* embedded_storage_error() noexcept;
}
