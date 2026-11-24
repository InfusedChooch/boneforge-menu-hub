// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <Windows.h>
#include <array>
#include <cstddef>

namespace ghl {
// Private host layouts are selected only after hashing the loaded DLL. These
// values are reviewed against the corresponding official binary and source.
struct HostProfile {
    const char* name;
    const char* sha256;
    size_t image_size;
    size_t section_count;
    size_t param_rva;
    size_t version_rva;
    size_t functions_rva;
    size_t renderer_rva;
    size_t sdk_rva;
    size_t script_runner_rva;
    size_t runner_state_offset;
    size_t state_lua_offset;
    std::array<size_t, 18> function_rvas;
    std::array<size_t, 14> sdk_rvas;
};

const HostProfile* host_profiles(size_t& count) noexcept;
const HostProfile* profile_for_sha256(const char* sha256) noexcept;
const HostProfile* identify_host(HMODULE host) noexcept;
}
