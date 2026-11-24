// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <filesystem>
#include <string>
namespace ghl {
inline std::string path_utf8(const std::filesystem::path& path) {
    const auto bytes = path.generic_u8string();
    // C++20 changed this container to char8_t; the UTF-8 bytes are unchanged.
    return {reinterpret_cast<const char*>(bytes.data()), bytes.size()};
}
}
