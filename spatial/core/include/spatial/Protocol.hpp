#pragma once

#include "spatial/SpatialState.hpp"

#include <string>
#include <string_view>

namespace spatial::protocol {

inline constexpr int kVersion = 1;

enum class ErrorCode {
    SpatialDisabled,
    InvalidCommand,
    InvalidArgument,
    OutOfRange,
    InternalError,
};

[[nodiscard]] std::string_view errorCodeName(ErrorCode code) noexcept;
[[nodiscard]] std::string statusJson(const SpatialState& state);
[[nodiscard]] std::string cameraJson(const SpatialState& state);
[[nodiscard]] std::string windowsJson(const SpatialState& state);
[[nodiscard]] std::string errorJson(ErrorCode code, std::string_view message);

} // namespace spatial::protocol
