// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <Windows.h>
namespace ghl {
inline bool external_version_target(FARPROC target, HMODULE proxy) noexcept {
    MEMORY_BASIC_INFORMATION memory{};
    return target && VirtualQuery(reinterpret_cast<const void*>(target), &memory, sizeof(memory)) == sizeof(memory)
        && memory.Type == MEM_IMAGE && memory.AllocationBase != proxy;
}
}
