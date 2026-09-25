#pragma once

#include "spatial/Protocol.hpp"

#include <optional>
#include <string>
#include <string_view>

namespace spatial::command {

enum class Kind {
    Status,
    Windows,
    Camera,
    Enable,
    Disable,
    Pan,
};

struct Command {
    Kind kind = Kind::Status;
    double dx = 0.0;
    double dy = 0.0;
};

struct ParseResult {
    std::optional<Command> command;
    protocol::ErrorCode error = protocol::ErrorCode::InvalidCommand;
    std::string message;

    [[nodiscard]] explicit operator bool() const noexcept {
        return command.has_value();
    }
};

[[nodiscard]] ParseResult parse(std::string_view request);

} // namespace spatial::command
