// SPDX-License-Identifier: GPL-3.0-or-later
#include "bootstrap_files.hpp"

namespace ghl {
bool append_path(wchar_t* path, size_t capacity, const wchar_t* suffix) noexcept {
    size_t length = 0, extra = 0;
    while (length < capacity && path[length]) ++length;
    while (suffix[extra]) ++extra;
    if (length == capacity || extra >= capacity - length) return false;
    for (size_t i = 0; i <= extra; ++i) path[length + i] = suffix[i];
    return true;
}
bool executable_directory(wchar_t* path, size_t capacity) noexcept {
    const DWORD length = GetModuleFileNameW(nullptr, path, static_cast<DWORD>(capacity));
    if (!length || length >= capacity) return false;
    for (DWORD i = length; i > 0; --i) {
        if (path[i - 1] == L'\\') { path[i - 1] = 0; return true; }
    }
    return false;
}
PublishResult publish_exact_file(const wchar_t* path, const unsigned char* bytes, size_t size) noexcept {
    if (!bytes || !size || size > MAXDWORD) return PublishResult::failed;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER length{};
        bool match = GetFileSizeEx(file, &length) && length.QuadPart == static_cast<LONGLONG>(size);
        unsigned char buffer[4096];
        size_t offset = 0;
        while (match && offset < size) {
            const DWORD amount = static_cast<DWORD>((size - offset) < sizeof(buffer) ? size - offset : sizeof(buffer));
            DWORD read{};
            match = ReadFile(file, buffer, amount, &read, nullptr) && read == amount;
            for (DWORD i = 0; match && i < read; ++i) match = buffer[i] == bytes[offset + i];
            offset += read;
        }
        CloseHandle(file);
        return match ? PublishResult::identical : PublishResult::conflict;
    }
    if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) return PublishResult::failed;
    file = CreateFileW(path, GENERIC_WRITE, 0, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return PublishResult::failed;
    DWORD written{};
    const bool success = WriteFile(file, bytes, static_cast<DWORD>(size), &written, nullptr) && written == size;
    CloseHandle(file);
    // A failed/partial file remains an explicit conflict on the next launch;
    // never delete or overwrite an unknown existing executable automatically.
    return success ? PublishResult::created : PublishResult::failed;
}
}
