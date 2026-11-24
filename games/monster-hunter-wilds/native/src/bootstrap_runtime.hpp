// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <reframework/API.h>
namespace ghl {
bool prepare_user_data(const REFrameworkPluginInitializeParam* param) noexcept;
const char* bootstrap_error() noexcept;
const char* data_path(const char* name) noexcept;
}
