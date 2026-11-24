// SPDX-License-Identifier: GPL-3.0-or-later
#include "bootstrap_runtime.hpp"
#include "bootstrap_files.hpp"
#include "utf8_path.hpp"
#include <ShlObj.h>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

namespace ghl {
namespace {
const char* failure = "";
std::string data_root, settings_path, diagnostics_path, backups_path, legacy_data_path;
bool fail(const char* reason) { failure = reason; return false; }
}
const char* bootstrap_error() noexcept { return failure; }
const char* data_path(const char* name) noexcept {
    if (std::strcmp(name, "root") == 0) return data_root.c_str();
    if (std::strcmp(name, "settings") == 0) return settings_path.c_str();
    if (std::strcmp(name, "diagnostics") == 0) return diagnostics_path.c_str();
    if (std::strcmp(name, "backups") == 0) return backups_path.c_str();
    if (std::strcmp(name, "legacy_data") == 0) return legacy_data_path.c_str();
    return "";
}
bool prepare_user_data(const REFrameworkPluginInitializeParam* param) noexcept {
    try {
        std::vector<wchar_t> directory(path_capacity);
        if (!executable_directory(directory.data(), directory.size())) return fail("Cannot determine game directory");
        const std::filesystem::path root(directory.data());
        const auto plugins = root / L"reframework" / L"plugins";
        for (const wchar_t* name : {L"GHLQOL.dll", L"ref_cursor.dll", L"WpSeries_GreatSword.dll", L"GenSeries_ParryWindow.dll"}) {
            if (std::filesystem::exists(plugins / name)) return fail("Legacy GHL QOL/companion DLL remains in reframework/plugins");
            if (GetModuleHandleW(name)) return fail("Legacy GHL QOL/companion DLL is already loaded by another owner");
        }
        for (const wchar_t* name : {L"GHLQOL.lua", L"ParryMeister.lua", L"mhwilds_qol.lua", L"Buffer.lua", L"GreatSword_Auto.lua",
                L"AutoGuardGS.lua", L"WpSeries_GreatSword_entry.lua", L"GenSeries_ParryWindow_entry.lua"}) {
            if (std::filesystem::exists(root / L"reframework" / L"autorun" / name)) return fail("Legacy GHL QOL/Parry/Buffer autorun loader remains installed");
        }
        PWSTR documents_raw{};
        if (FAILED(SHGetKnownFolderPath(FOLDERID_Documents, KF_FLAG_CREATE, nullptr, &documents_raw)))
            return fail("Cannot locate Windows Documents folder");
        struct DocumentsMemory { PWSTR value; ~DocumentsMemory() { CoTaskMemFree(value); } } documents_memory{documents_raw};
        const auto documents = std::filesystem::path(documents_raw) / L"WildsMenu";
        data_root = path_utf8(documents);
        settings_path = path_utf8(documents / L"settings");
        diagnostics_path = path_utf8(documents / L"diagnostics");
        backups_path = path_utf8(documents / L"backups");
        legacy_data_path = path_utf8(root / L"reframework" / L"data");
        for (const auto* child : {L"settings", L"diagnostics", L"backups"}) std::filesystem::create_directories(documents / child);
        if (param->functions->log_info) param->functions->log_info("[GHL QOL Root] Data folder: %s", data_root.c_str());
        return true;
    } catch (...) { return fail("Exception preparing user data"); }
}
}
