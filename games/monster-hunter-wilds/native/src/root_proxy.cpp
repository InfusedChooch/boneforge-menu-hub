// SPDX-License-Identifier: GPL-3.0-or-later
#include "bootstrap_files.hpp"
#include "direct_host.hpp"
#include "version_target.hpp"
#include <Windows.h>
#include <vector>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {
wchar_t original_path[ghl::path_capacity]{};
wchar_t startup_expected[ghl::path_capacity]{};
bool root_location = false;
INIT_ONCE version_once = INIT_ONCE_STATIC_INIT;
FARPROC version_functions[17]{};
constexpr const char* version_names[] = {
    "GetFileVersionInfoA", "GetFileVersionInfoByHandle", "GetFileVersionInfoExA", "GetFileVersionInfoExW",
    "GetFileVersionInfoSizeA", "GetFileVersionInfoSizeExA", "GetFileVersionInfoSizeExW", "GetFileVersionInfoSizeW",
    "GetFileVersionInfoW", "VerFindFileA", "VerFindFileW", "VerInstallFileA", "VerInstallFileW",
    "VerLanguageNameA", "VerLanguageNameW", "VerQueryValueA", "VerQueryValueW"
};
bool equal_path(const wchar_t* a, const wchar_t* b) noexcept {
    // Paths here come from the same process executable/module directory. Use
    // ordinal case comparison; no filesystem traversal or shell API is needed.
    return CompareStringOrdinal(a, -1, b, -1, TRUE) == CSTR_EQUAL;
}
BOOL CALLBACK load_system_version(PINIT_ONCE, PVOID, PVOID*) try {
    std::vector<wchar_t> path(ghl::path_capacity);
    const UINT length = GetSystemDirectoryW(path.data(), static_cast<UINT>(path.size()));
    if (!length || length >= path.size() || !ghl::append_path(path.data(), path.size(), L"\\version.dll")) return TRUE;
    // Our DllMain never calls this routine. Forwarded API callers own their
    // context; do not claim another DLL cannot call a version API from DllMain.
    const HMODULE module = LoadLibraryExW(path.data(), nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    const HMODULE self = reinterpret_cast<HMODULE>(&__ImageBase);
    if (!module || module == self) return TRUE;
    for (size_t i = 0; i < 17; ++i) {
        FARPROC target = GetProcAddress(module, version_names[i]);
        if (ghl::external_version_target(target, self)) version_functions[i] = target;
    }
    return TRUE;
} catch (...) { return TRUE; }
extern "C" ULONG_PTR WINAPI unavailable_version_api() {
    SetLastError(ERROR_PROC_NOT_FOUND);
    return 0;
}
}

extern "C" FARPROC ghl_resolve_version_export(unsigned int index) {
    const DWORD last_error = GetLastError();
    // The current Windows host implements 15 exports in the already-loaded
    // KernelBase, including every version API imported by Wilds. This path
    // cannot load a dependency even when another DLL calls us from DllMain.
    const HMODULE kernel_base = GetModuleHandleW(L"kernelbase.dll");
    if (index < 17 && kernel_base) {
        FARPROC direct = GetProcAddress(kernel_base, version_names[index]);
        if (ghl::external_version_target(direct, reinterpret_cast<HMODULE>(&__ImageBase))) {
            SetLastError(last_error);
            return direct;
        }
    }
    // VerInstallFileA/W are absent from this host's KernelBase. They retain a
    // normal System32 fallback; arbitrary third-party DllMain calls to these two
    // APIs are not claimed to be free of loader-lock risks.
    InitOnceExecuteOnce(&version_once, load_system_version, nullptr, nullptr);
    FARPROC result = index < 17 && version_functions[index] ? version_functions[index] : reinterpret_cast<FARPROC>(unavailable_version_api);
    SetLastError(last_error);
    return result;
}
extern "C" __declspec(dllexport) bool ghl_qol_root_identity(const wchar_t* expected) {
    return root_location && expected && equal_path(original_path, expected);
}

// Keep this out of DllMain: MSVC reserves a function's stack before evaluating
// early returns. Even an unused 64 KiB local caused DLL_THREAD_ATTACH overflow.
__declspec(noinline) void attach_root(HINSTANCE self, LPVOID reserved) noexcept {
    const DWORD length = GetModuleFileNameW(self, original_path, static_cast<DWORD>(ghl::path_capacity));
    wchar_t* expected = startup_expected;
    root_location = length && length < ghl::path_capacity
        && ghl::executable_directory(expected, ghl::path_capacity)
        && ghl::append_path(expected, ghl::path_capacity, L"\\version.dll")
        && equal_path(original_path, expected);
    // A root static import queues one worker. Its user entry runs only after
    // serialized DLL attach notifications; no host work or waits happen here.
    if (root_location && reserved) ghl::queue_direct_host(self);
}
BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) attach_root(self, reserved);
    if (reason == DLL_PROCESS_DETACH) ghl::stop_direct_host();
    return TRUE; // A mod startup failure must not prevent the game loading.
}
