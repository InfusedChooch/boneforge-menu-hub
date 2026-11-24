// SPDX-License-Identifier: GPL-3.0-or-later
#include "bootstrap_files.hpp"
#include <Psapi.h>
#include <reframework/API.h>
#include <vector>

namespace {
HMODULE root_module() noexcept try {
    std::vector<wchar_t> expected(ghl::path_capacity);
    if (!ghl::executable_directory(expected.data(), expected.size())
        || !ghl::append_path(expected.data(), expected.size(), L"\\version.dll")) return nullptr;
    // REFramework can rewrite module paths into _storage_. The root records its
    // original attachment path, so identity is checked without loading it again.
    std::vector<HMODULE> modules(1024);
    DWORD needed{};
    const DWORD bytes = static_cast<DWORD>(modules.size() * sizeof(HMODULE));
    if (!K32EnumProcessModules(GetCurrentProcess(), modules.data(), bytes, &needed)
        || needed > bytes) return nullptr;
    using Identity = bool (*)(const wchar_t*);
    for (DWORD i = 0; i < needed / sizeof(HMODULE); ++i) {
        const auto identity = reinterpret_cast<Identity>(GetProcAddress(modules[i], "ghl_qol_root_identity"));
        if (identity && identity(expected.data())) return modules[i];
    }
    return nullptr;
} catch (...) { return nullptr; }
}

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    if (!version) return;
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name = nullptr;
}
extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    const HMODULE root = root_module();
    const auto initialize = root ? reinterpret_cast<REFPluginInitializeFn>(GetProcAddress(root, "ghl_qol_initialize")) : nullptr;
    if (!initialize) return false;
    HMODULE pinned{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(initialize), &pinned)) return false;
    return initialize(param);
}
