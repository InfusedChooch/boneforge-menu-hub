// SPDX-License-Identifier: GPL-3.0-or-later
#include "embedded_storage.hpp"
#include "bootstrap_runtime.hpp"
#include <Windows.h>
#include <atomic>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>
extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace {
namespace fs = std::filesystem;
constexpr std::size_t max_bytes = 16 * 1024 * 1024;
struct Entry { const char* name; const char* directory; };
constexpr Entry entries[] = {
    {"refshell_mhwilds.json", "settings"}, {"AutoGuardGS.json", "settings"},
    {"WpSeries_GreatSword_Config.json", "settings"}, {"GenSeries_ParryWindow_Config.json", "settings"},
    {"GHLQOL-gameplay.json", "settings"}, {"GHLQOL-buffer.json", "settings"},
    {"GHLQOL-buffer-cache.json", "settings"}, {"GHLQOL-status.json", "diagnostics"},
    {"GHLQOL-profiles.json", "settings"},
    {"ParryMeister-status.json", "diagnostics"}, {"AutoGuardGS-diagnostics.json", "diagnostics"},
};
thread_local std::string result_text, failure;
thread_local char registration_error[1024]{};
std::atomic<unsigned long> serial{0};
std::mutex profile_mutex;
std::string session_profile_id;

const Entry& entry(std::string_view name) {
    for (const auto& item : entries) if (name == item.name) return item;
    throw std::runtime_error("Filename is outside GHL's storage allowlist");
}
fs::path directory(const char* key) {
    const char* raw = ghl::data_path(key);
    if (!raw || !*raw) throw std::runtime_error("GHL storage path is unavailable");
    const auto path = fs::u8path(raw);
    if (!path.is_absolute()) throw std::runtime_error("GHL storage path must be absolute");
    if (!fs::is_directory(path)) throw std::runtime_error("GHL storage directory is unavailable");
    return path;
}
bool present(const fs::path& path) {
    std::error_code error;
    const auto state = fs::symlink_status(path, error);
    if (error == std::errc::no_such_file_or_directory || state.type() == fs::file_type::not_found) return false;
    if (error) throw fs::filesystem_error("Cannot inspect GHL storage file", path, error);
    if (fs::is_symlink(state) || !fs::is_regular_file(state)) throw std::runtime_error("GHL storage target is not a regular file");
    return true;
}
std::string read_bytes(const fs::path& path) {
    const auto size = fs::file_size(path);
    if (size > max_bytes) throw std::runtime_error("GHL JSON file exceeds the 16 MiB limit");
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("Cannot open GHL JSON file");
    std::string data(static_cast<std::size_t>(size), '\0');
    if (size && !file.read(data.data(), static_cast<std::streamsize>(size))) throw std::runtime_error("Cannot read complete GHL JSON file");
    if (file.peek() != std::char_traits<char>::eof()) throw std::runtime_error("GHL JSON file changed during read");
    return data;
}
void write_atomic(const fs::path& target, std::string_view data, bool overwrite = true) {
    if (data.size() > max_bytes) throw std::runtime_error("GHL JSON write exceeds the 16 MiB limit");
    if (present(target) && !overwrite) return;
    auto temporary = target;
    temporary += L".tmp-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(++serial);
    HANDLE file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) throw std::runtime_error("Cannot create GHL atomic-write file");
    DWORD written{};
    const bool complete = WriteFile(file, data.data(), static_cast<DWORD>(data.size()), &written, nullptr)
        && written == data.size() && FlushFileBuffers(file);
    const bool closed = CloseHandle(file) != 0;
    if (!complete || !closed) {
        DeleteFileW(temporary.c_str());
        throw std::runtime_error("GHL JSON write failed; previous file preserved");
    }
    if (!MoveFileExW(temporary.c_str(), target.c_str(), (overwrite ? MOVEFILE_REPLACE_EXISTING : 0) | MOVEFILE_WRITE_THROUGH)) {
        DeleteFileW(temporary.c_str());
        if (!overwrite && present(target)) return;
        throw std::runtime_error("Cannot replace GHL JSON file; previous file preserved");
    }
}
void migrate(const Entry& item) {
    const auto target = directory(item.directory) / item.name;
    if (present(target) || std::string_view(item.directory) != "settings") return;
    const char* raw = ghl::data_path("legacy_data");
    if (!raw || !*raw || !fs::u8path(raw).is_absolute()) throw std::runtime_error("Legacy GHL data path is unavailable");
    const auto original = fs::u8path(raw) / item.name;
    if (!present(original)) return;
    const auto data = read_bytes(original);
    const auto backups = directory("backups") / "legacy-import";
    fs::create_directories(backups);
    const auto backup = backups / item.name;
    write_atomic(backup, data, false);
    // No-replace publication also preserves a Documents file created concurrently.
    write_atomic(target, data, false);
}

enum class Operation { Read, Write, Exists, Migrate };
template <Operation operation> int invoke(lua_State* state) {
    std::size_t name_size{}, data_size{};
    const char* name = luaL_checklstring(state, 1, &name_size);
    const char* data = nullptr;
    if constexpr (operation == Operation::Write) data = luaL_checklstring(state, 2, &data_size);
    bool found = false;
    failure.clear(); result_text.clear();
    try {
        const auto& item = entry(std::string_view(name, name_size));
        const auto path = directory(item.directory) / item.name;
        if constexpr (operation == Operation::Read) {
            found = present(path);
            if (found) result_text = read_bytes(path);
        } else if constexpr (operation == Operation::Write) write_atomic(path, std::string_view(data, data_size));
        else if constexpr (operation == Operation::Exists) found = present(path);
        else migrate(item);
    } catch (const std::exception& error) { failure = error.what(); }
      catch (...) { failure = "Unexpected GHL storage failure"; }
    // File handles and C++ temporaries are gone before Lua can longjmp.
    if (!failure.empty()) {
        if constexpr (operation == Operation::Write || operation == Operation::Migrate) lua_pushboolean(state, false);
        else lua_pushnil(state);
        lua_pushlstring(state, failure.data(), failure.size());
        return 2;
    }
    if constexpr (operation == Operation::Read) {
        if (found) lua_pushlstring(state, result_text.data(), result_text.size()); else lua_pushnil(state);
    } else if constexpr (operation == Operation::Exists) lua_pushboolean(state, found);
    else lua_pushboolean(state, true);
    return 1;
}
int profile_session(lua_State* state) {
    std::size_t size{};
    const char* candidate = luaL_checklstring(state, 1, &size);
    failure.clear(); result_text.clear();
    try {
        if (!size || size > 64) throw std::runtime_error("Invalid profile identifier");
        for (std::size_t i = 0; i < size; ++i) {
            const char c = candidate[i];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-'))
                throw std::runtime_error("Invalid profile identifier");
        }
        // A Lua reset must not activate a pending profile in the same game session.
        const std::lock_guard<std::mutex> lock(profile_mutex);
        if (session_profile_id.empty()) session_profile_id.assign(candidate, size);
        result_text = session_profile_id;
    } catch (const std::exception& error) { failure = error.what(); }
      catch (...) { failure = "Cannot select the session profile"; }
    if (!failure.empty()) {
        lua_pushnil(state); lua_pushlstring(state, failure.data(), failure.size()); return 2;
    }
    lua_pushlstring(state, result_text.data(), result_text.size()); return 1;
}
int install(lua_State* state) {
    lua_createtable(state, 0, 5);
    lua_pushcfunction(state, invoke<Operation::Read>); lua_setfield(state, -2, "read");
    lua_pushcfunction(state, invoke<Operation::Write>); lua_setfield(state, -2, "write");
    lua_pushcfunction(state, invoke<Operation::Exists>); lua_setfield(state, -2, "exists");
    lua_pushcfunction(state, invoke<Operation::Migrate>); lua_setfield(state, -2, "migrate");
    lua_pushcfunction(state, profile_session); lua_setfield(state, -2, "profile_session");
    lua_setglobal(state, "__ghl_storage");
    return 0;
}
}
namespace ghl {
const char* embedded_storage_error() noexcept { return registration_error; }
bool register_embedded_storage(lua_State* state) noexcept {
    registration_error[0] = '\0';
    if (!state) { std::snprintf(registration_error, sizeof(registration_error), "Lua state is null"); return false; }
    const int before = lua_gettop(state);
    if (!lua_checkstack(state, 2)) { std::snprintf(registration_error, sizeof(registration_error), "Lua stack cannot grow"); return false; }
    lua_pushcfunction(state, install);
    if (lua_pcall(state, 0, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(state, -1);
        std::snprintf(registration_error, sizeof(registration_error), "%s", error ? error : "Storage registration failed");
        lua_settop(state, before); return false;
    }
    lua_settop(state, before); return true;
}
}
