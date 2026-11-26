#include <cstddef>
#include <cstdint>
#include <reframework/API.h>
extern "C" {
#include <lua.h>
}
#include "identity.h"

// Supply the current area's name from the game adapter when available.
static int currentArea(lua_State* state) {
    lua_pushnil(state);
    return 1;
}

static void publish(lua_State* state) {
    if (!state) return;
    lua_newtable(state);
    lua_pushstring(state, MENU_VERSION);
    lua_setfield(state, -2, "version");
    lua_pushboolean(state, true);
    lua_setfield(state, -2, "ready");
    lua_pushcfunction(state, currentArea);
    lua_setfield(state, -2, "current_area");
    lua_setglobal(state, MENU_ID);
}

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    if (version) *version = {REFRAMEWORK_PLUGIN_VERSION_MAJOR, REFRAMEWORK_PLUGIN_VERSION_MINOR,
        REFRAMEWORK_PLUGIN_VERSION_PATCH, nullptr};
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* host) {
    if (!host || !host->version || !host->functions) return false;
    const auto& version = *host->version;
    if (version.major != REFRAMEWORK_PLUGIN_VERSION_MAJOR || version.minor < REFRAMEWORK_PLUGIN_VERSION_MINOR)
        return false;
    // The table belongs to the Lua state. A script reset discards it naturally.
    const auto subscribe = host->functions->on_lua_state_created;
    return subscribe && subscribe(publish);
}
