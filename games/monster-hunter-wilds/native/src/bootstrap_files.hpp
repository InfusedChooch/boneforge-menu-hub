// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <Windows.h>
#include <cstddef>

namespace ghl {
constexpr size_t path_capacity = 32768;
enum class PublishResult { created, identical, conflict, failed };
// No allocation, library loading, hashing, or thread synchronization. Safe for
// the small bootstrap publication performed during static DLL attachment.
bool append_path(wchar_t* path, size_t capacity, const wchar_t* suffix) noexcept;
bool executable_directory(wchar_t* path, size_t capacity) noexcept;
PublishResult publish_exact_file(const wchar_t* path, const unsigned char* bytes, size_t size) noexcept;
}
