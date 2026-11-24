// SPDX-License-Identifier: GPL-3.0-or-later
#include "embedded_lua.hpp"
#ifndef GHL_EMBEDDED_ENGINE_TESTING
#include "embedded_payload.hpp"
#include <array>
#endif

#include <cstdio>
#include <exception>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
thread_local char last_error[1024]{};

struct EngineBatch {
    const ghl::EmbeddedEngine* engines;
    std::size_t count;
};

void load_engine(lua_State* state, const char* name, const char* bytes, std::size_t size) {
    if (luaL_loadbufferx(state, bytes, size, name, "b") != LUA_OK) lua_error(state);
    const int function = lua_gettop(state);
    // Stripped engine bytecode has no debug upvalue name. Validate the actual
    // environment identity and count instead of relying on optional symbols.
    if (!lua_getupvalue(state, function, 1)) {
        luaL_error(state, "%s must have only the global _ENV upvalue", name);
    }
    lua_pushglobaltable(state);
    const bool global_environment = lua_rawequal(state, -1, -2) != 0;
    lua_pop(state, 2);
    if (!global_environment || lua_getupvalue(state, function, 2)) {
        luaL_error(state, "%s has unsupported captured state", name);
    }
}

int engine_getter(lua_State* state) {
    std::size_t size{};
    const char* name = lua_tostring(state, lua_upvalueindex(1));
    const char* bytes = lua_tolstring(state, lua_upvalueindex(2), &size);
    load_engine(state, name, bytes, size);
    return 1;
}

int install_engines(lua_State* state) {
    const auto* batch = static_cast<const EngineBatch*>(lua_touserdata(state, 1));
    if (!batch || !batch->engines || !batch->count) return luaL_error(state, "No embedded engines supplied");
    lua_pushglobaltable(state);
    const int globals = lua_gettop(state);
    lua_pushliteral(state, "__sl_entries");
    lua_rawget(state, globals);
    const int existing = lua_gettop(state);
    if (!lua_isnil(state, existing) && !lua_istable(state, existing)) {
        return luaL_error(state, "__sl_entries is already owned by an incompatible provider");
    }
    lua_createtable(state, 0, static_cast<int>(batch->count));
    const int staged = lua_gettop(state);
    for (std::size_t i = 0; i < batch->count; ++i) {
        const auto& engine = batch->engines[i];
        if (!engine.name || !engine.name[0] || !engine.data || !engine.size) {
            return luaL_error(state, "Embedded engine descriptor is incomplete");
        }
        if (lua_istable(state, existing)) {
            lua_pushstring(state, engine.name);
            lua_rawget(state, existing);
            const bool collision = !lua_isnil(state, -1);
            lua_pop(state, 1);
            if (collision) return luaL_error(state, "Embedded engine entry already exists: %s", engine.name);
        }
        lua_pushstring(state, engine.name);
        lua_rawget(state, staged);
        const bool duplicate = !lua_isnil(state, -1);
        lua_pop(state, 1);
        if (duplicate) return luaL_error(state, "Duplicate embedded engine: %s", engine.name);
        // Validate every binary and captured environment before publishing any
        // getter. Loading a Lua chunk does not execute its body.
        load_engine(state, engine.name, reinterpret_cast<const char*>(engine.data), engine.size);
        lua_pop(state, 1);
        lua_pushstring(state, engine.name);
        lua_pushstring(state, engine.name);
        lua_pushlstring(state, reinterpret_cast<const char*>(engine.data), engine.size);
        lua_pushcclosure(state, engine_getter, 2);
        lua_rawset(state, staged);
    }
    if (lua_isnil(state, existing)) {
        lua_pushliteral(state, "__sl_entries");
        lua_pushvalue(state, staged);
        lua_rawset(state, globals);
    } else {
        for (std::size_t i = 0; i < batch->count; ++i) {
            lua_pushstring(state, batch->engines[i].name);
            lua_pushvalue(state, -1);
            lua_rawget(state, staged);
            lua_rawset(state, existing);
        }
    }
    return 0;
}

#ifndef GHL_EMBEDDED_ENGINE_TESTING
int install(lua_State* state) {
    lua_getglobal(state, "__ghl_embedded_status");
    const bool registered = lua_istable(state, -1);
    lua_pop(state, 1);
    if (registered) return 0;

    std::array<ghl::EmbeddedEngine, ghl::embedded::engine_count> engines{};
    for (std::size_t i = 0; i < engines.size(); ++i) {
        const auto& engine = ghl::embedded::engines[i];
        engines[i] = {engine.name, engine.data, engine.size};
    }
    if (!ghl::register_embedded_engines(state, engines.data(), engines.size())) {
        return luaL_error(state, "%s", ghl::embedded_lua_error());
    }

    lua_getglobal(state, "package");
    luaL_checktype(state, -1, LUA_TTABLE);
    lua_getfield(state, -1, "preload");
    luaL_checktype(state, -1, LUA_TTABLE);
    const int preload = lua_gettop(state);
    lua_createtable(state, 0, static_cast<int>(ghl::embedded::module_count));
    const int loaders = lua_gettop(state);
    // Compile every source before publishing any loader. Lua errors stay inside
    // the enclosing lua_pcall; this callback owns no C++ RAII scopes.
    for (const auto& module : ghl::embedded::modules) {
        if (luaL_loadbufferx(state, reinterpret_cast<const char*>(module.data),
                module.size, module.source, "t") != LUA_OK) return lua_error(state);
        lua_setfield(state, loaders, module.name);
    }
    for (const auto& module : ghl::embedded::modules) {
        lua_pushstring(state, module.name);
        lua_getfield(state, loaders, module.name);
        lua_rawset(state, preload);
    }
    if (luaL_loadbufferx(state, reinterpret_cast<const char*>(ghl::embedded::bootstrap_script),
            ghl::embedded::bootstrap_script_size, "@embedded/GHLQOL-startup", "t") != LUA_OK) {
        return lua_error(state);
    }
    lua_call(state, 0, 0);
    return 0;
}
#endif
}

namespace ghl {
const char* embedded_lua_error() noexcept { return last_error; }

namespace {
bool protected_install(lua_State* state, lua_CFunction function, const EngineBatch* batch = nullptr) noexcept {
    last_error[0] = '\0';
    if (!state) {
        std::snprintf(last_error, sizeof(last_error), "%s", "Lua state is null");
        return false;
    }
    const int before = lua_gettop(state);
    try {
        if (!lua_checkstack(state, 2)) {
            std::snprintf(last_error, sizeof(last_error), "%s", "Lua stack cannot grow");
            return false;
        }
        lua_pushcfunction(state, function);
        if (batch) lua_pushlightuserdata(state, const_cast<EngineBatch*>(batch));
        if (lua_pcall(state, batch ? 1 : 0, 0, 0) != LUA_OK) {
            const char* message = lua_tostring(state, -1);
            std::snprintf(last_error, sizeof(last_error), "%s", message ? message : "Embedded Lua registration failed");
            lua_settop(state, before);
            return false;
        }
        lua_settop(state, before);
        return true;
    } catch (const std::exception& error) {
        std::snprintf(last_error, sizeof(last_error), "%s", error.what());
    } catch (...) {
        std::snprintf(last_error, sizeof(last_error), "%s", "Unexpected embedded Lua exception");
    }
    lua_settop(state, before);
    return false;
}
}

bool register_embedded_engines(lua_State* state, const EmbeddedEngine* engines, std::size_t count) noexcept {
    const EngineBatch batch{engines, count};
    return protected_install(state, install_engines, &batch);
}

#ifndef GHL_EMBEDDED_ENGINE_TESTING
bool register_embedded_lua(lua_State* state) noexcept {
    return protected_install(state, install);
}
#endif
}
