#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <reframework/API.h>
extern "C" {
#include <lauxlib.h>
#include <lualib.h>
}
#include "identity.h"

static REFLuaStateCreatedCb onCreate;
static bool accept(REFLuaStateCreatedCb cb) { onCreate = cb; return true; }
static bool reject(REFLuaStateCreatedCb) { return false; }

int main(int argc, char** argv) {
    if (argc != 4) return 1;
    HMODULE dll = LoadLibraryA(argv[1]);
    if (!dll) return 2;
    auto init = reinterpret_cast<REFPluginInitializeFn>(GetProcAddress(dll, "reframework_plugin_initialize"));
    auto required = reinterpret_cast<REFPluginRequiredVersionFn>(GetProcAddress(dll, "reframework_plugin_required_version"));
    if (!init || !required) return 3;
    REFrameworkPluginVersion version{};
    required(&version);
    REFrameworkPluginFunctions functions{};
    REFrameworkPluginInitializeParam host{};
    host.version = &version;
    host.functions = &functions;
    if (init(nullptr) || init(&host)) return 4;
    functions.on_lua_state_created = reject;
    if (init(&host)) return 5;
    functions.on_lua_state_created = accept;
    ++version.major;
    if (init(&host)) return 6;
    --version.major;
    if (!init(&host) || !onCreate) return 7;
    for (int i = 0; i < 2; ++i) {
        lua_State* state = luaL_newstate();
        if (!state) return 8;
        luaL_openlibs(state);
        onCreate(state);
        lua_pushstring(state, MENU_ID);
        lua_setglobal(state, "testId");
        lua_pushstring(state, MENU_VERSION);
        lua_setglobal(state, "testVersion");
        lua_pushstring(state, argv[2]);
        lua_setglobal(state, "testScript");
        if (luaL_dofile(state, argv[3]) != LUA_OK) {
            std::fprintf(stderr, "%s\n", lua_tostring(state, -1));
            lua_close(state);
            return 9;
        }
        lua_close(state);
    }
    FreeLibrary(dll);
    return 0;
}
