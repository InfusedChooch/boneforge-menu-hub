// SPDX-License-Identifier: GPL-3.0-or-later
#include "host_profiles.hpp"
#include <bcrypt.h>
#include <cstdio>
#include <cstring>
#include <vector>

namespace ghl {
namespace {
constexpr HostProfile profiles[] = {
    {
        "nightly-01410-e6c8c592",
        "0049ef36050af6cea3a7a43a171fde92147174d4c1b7108eb21c73c85eac93fd",
        0x1623000, 7, 0x1567350, 0x1567378, 0x1567390, 0x15672c0, 0x15672e0,
        0x159a518, 0x08, 0x18,
        {0xf14d0, 0xf1530, 0xf1590, 0xf15f0, 0xf1710, 0xf1830, 0xf18d0,
         0xf1940, 0xf19a0, 0xf1cc0, 0xf1db0, 0xf1ea0, 0xf1f90, 0xf1c00,
         0xf1c20, 0xf1a00, 0xf1ad0, 0xf1ba0},
        {0x1567420, 0x1567680, 0x15674a0, 0x15675b0, 0x1567620, 0x159a324,
         0x1567710, 0x1567768, 0x1567778, 0x1567790, 0x15677f0, 0x1567498,
         0x1567810, 0x1567830}
    },
    {
        "nightly-01436-1813bf34",
        "87a67022b995a6aa3410e22f8702daa5f9e17f97c9498cb011403c9a3defe1c1",
        0x162f000, 0x7, 0x1572370, 0x1572398, 0x15723b0, 0x15722e0, 0x1572300, 0x15a59d8, 0x8, 0x18,
        {0xf2450, 0xf24b0, 0xf2510, 0xf2570, 0xf2690, 0xf27b0, 0xf2850,
         0xf28c0, 0xf2920, 0xf2c40, 0xf2d30, 0xf2e20, 0xf2f10, 0xf2b80,
         0xf2ba0, 0xf2980, 0xf2a50, 0xf2b20},
        {0x1572440, 0x15726a0, 0x15724c0, 0x15725d0, 0x1572640, 0x15a57e4, 0x1572730,
         0x1572788, 0x1572798, 0x15727b0, 0x1572810, 0x15724b8, 0x1572830, 0x1572850}
    },
    {
        "nightly-01437-f9cb2ac3",
        "604e02acb2934e07d2d6e840cb53de460ef364e1109478356f0a923e598ec4b0",
        0x162f000, 0x7, 0x1572370, 0x1572398, 0x15723b0, 0x15722e0, 0x1572300, 0x15a59d8, 0x8, 0x18,
        {0xf2450, 0xf24b0, 0xf2510, 0xf2570, 0xf2690, 0xf27b0, 0xf2850,
         0xf28c0, 0xf2920, 0xf2c40, 0xf2d30, 0xf2e20, 0xf2f10, 0xf2b80,
         0xf2ba0, 0xf2980, 0xf2a50, 0xf2b20},
        {0x1572440, 0x15726a0, 0x15724c0, 0x15725d0, 0x1572640, 0x15a57e4, 0x1572730,
         0x1572788, 0x1572798, 0x15727b0, 0x1572810, 0x15724b8, 0x1572830, 0x1572850}
    },
    {
        "nightly-01438-f00d6bee",
        "748d6543b45a5ddd6b2d5170d1ba16ed56219c7f0d52141797a95c3bda189e5f",
        0x1630000, 0x7, 0x1573370, 0x1573398, 0x15733b0, 0x15732e0, 0x1573300, 0x15a6af8, 0x8, 0x18,
        {0xf2f80, 0xf2fe0, 0xf3040, 0xf30a0, 0xf31c0, 0xf32e0, 0xf3380,
         0xf33f0, 0xf3450, 0xf3770, 0xf3860, 0xf3950, 0xf3a40, 0xf36b0,
         0xf36d0, 0xf34b0, 0xf3580, 0xf3650},
        {0x1573440, 0x15736a0, 0x15734c0, 0x15735d0, 0x1573640, 0x15a6904, 0x1573730,
         0x1573788, 0x1573798, 0x15737b0, 0x1573810, 0x15734b8, 0x1573830, 0x1573850}
    },
};
}

const HostProfile* host_profiles(size_t& count) noexcept {
    count = std::size(profiles);
    return profiles;
}

const HostProfile* profile_for_sha256(const char* sha256) noexcept {
    if (!sha256) return nullptr;
    for (const auto& profile : profiles) {
        if (std::strcmp(sha256, profile.sha256) == 0) return &profile;
    }
    return nullptr;
}

const HostProfile* identify_host(HMODULE host) noexcept try {
    if (!host) return nullptr;
    std::vector<wchar_t> path(32768);
    const DWORD length = GetModuleFileNameW(host, path.data(), static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return nullptr;
    struct Handles {
        HANDLE file = INVALID_HANDLE_VALUE;
        BCRYPT_ALG_HANDLE algorithm{};
        BCRYPT_HASH_HANDLE hash{};
        std::vector<UCHAR> hash_object;
        ~Handles() {
            if (hash) BCryptDestroyHash(hash);
            if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0);
            if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
        }
    } handles;
    // Public API versions do not describe Lua or the private startup layout.
    // Select a reviewed binary before accessing either of those interfaces.
    handles.file = CreateFileW(path.data(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_DELETE,
        nullptr, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (handles.file == INVALID_HANDLE_VALUE) return nullptr;
    if (BCryptOpenAlgorithmProvider(&handles.algorithm, BCRYPT_SHA256_ALGORITHM, nullptr, 0) < 0) return nullptr;
    DWORD object_length{}, returned{};
    if (BCryptGetProperty(handles.algorithm, BCRYPT_OBJECT_LENGTH,
        reinterpret_cast<PUCHAR>(&object_length), sizeof(object_length), &returned, 0) < 0
        || returned != sizeof(object_length) || !object_length) return nullptr;
    handles.hash_object.resize(object_length);
    if (BCryptCreateHash(handles.algorithm, &handles.hash, handles.hash_object.data(), object_length,
        nullptr, 0, 0) < 0) return nullptr;
    std::vector<UCHAR> buffer(65536);
    for (;;) {
        DWORD bytes_read{};
        if (!ReadFile(handles.file, buffer.data(), static_cast<DWORD>(buffer.size()), &bytes_read, nullptr)) return nullptr;
        if (!bytes_read) break;
        if (BCryptHashData(handles.hash, buffer.data(), bytes_read, 0) < 0) return nullptr;
    }
    std::array<UCHAR, 32> digest{};
    if (BCryptFinishHash(handles.hash, digest.data(), static_cast<ULONG>(digest.size()), 0) < 0) return nullptr;
    char actual[65]{};
    for (size_t i = 0; i < digest.size(); ++i) {
        std::snprintf(actual + i * 2, 3, "%02x", static_cast<unsigned int>(digest[i]));
    }
    return profile_for_sha256(actual);
} catch (...) { return nullptr; }
}
