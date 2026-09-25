#include "spatial/Command.hpp"

#include "spatial/Camera.hpp"

#include <charconv>
#include <cmath>
#include <string_view>
#include <vector>

namespace spatial::command {
namespace {

constexpr std::size_t kMaxRequestLength = 1024;
constexpr std::size_t kMaxTokens = 4;

std::vector<std::string_view> splitTokens(std::string_view request) {
    std::vector<std::string_view> tokens;
    tokens.reserve(kMaxTokens);

    std::size_t index = 0;
    while (index < request.size()) {
        while (index < request.size() && (request[index] == ' ' || request[index] == '\t' || request[index] == '\n' || request[index] == '\r')) {
            ++index;
        }
        if (index >= request.size()) {
            break;
        }

        const std::size_t start = index;
        while (index < request.size() && request[index] != ' ' && request[index] != '\t' && request[index] != '\n' && request[index] != '\r') {
            ++index;
        }

        tokens.emplace_back(request.substr(start, index - start));
        if (tokens.size() > kMaxTokens) {
            break;
        }
    }

    return tokens;
}

bool parseFiniteDouble(std::string_view token, double& output) {
    const char* begin = token.data();
    const char* end = token.data() + token.size();
    double value = 0.0;

    const auto [ptr, error] = std::from_chars(begin, end, value, std::chars_format::general);
    if (error != std::errc{} || ptr != end || !std::isfinite(value)) {
        return false;
    }

    output = value;
    return true;
}

ParseResult fail(protocol::ErrorCode error, std::string message) {
    return {
        .command = std::nullopt,
        .error = error,
        .message = std::move(message),
    };
}

} // namespace

ParseResult parse(std::string_view request) {
    if (request.empty()) {
        return fail(protocol::ErrorCode::InvalidCommand, "empty request");
    }

    if (request.size() > kMaxRequestLength) {
        return fail(protocol::ErrorCode::InvalidArgument, "request is too long");
    }

    const auto tokens = splitTokens(request);
    if (tokens.empty() || tokens[0] != "gendbyte-spatial") {
        return fail(protocol::ErrorCode::InvalidCommand, "invalid command namespace");
    }

    if (tokens.size() < 2) {
        return fail(protocol::ErrorCode::InvalidCommand, "missing spatial subcommand");
    }

    if (tokens.size() > kMaxTokens) {
        return fail(protocol::ErrorCode::InvalidArgument, "too many arguments");
    }

    const auto subcommand = tokens[1];

    if (subcommand == "status" || subcommand == "windows" || subcommand == "camera" || subcommand == "enable" || subcommand == "disable") {
        if (tokens.size() != 2) {
            return fail(protocol::ErrorCode::InvalidArgument, "subcommand does not accept arguments");
        }

        Kind kind = Kind::Status;
        if (subcommand == "windows") {
            kind = Kind::Windows;
        } else if (subcommand == "camera") {
            kind = Kind::Camera;
        } else if (subcommand == "enable") {
            kind = Kind::Enable;
        } else if (subcommand == "disable") {
            kind = Kind::Disable;
        }

        return {.command = Command{.kind = kind}};
    }

    if (subcommand == "pan") {
        if (tokens.size() != 4) {
            return fail(protocol::ErrorCode::InvalidArgument, "pan requires dx and dy");
        }

        double dx = 0.0;
        double dy = 0.0;
        if (!parseFiniteDouble(tokens[2], dx) || !parseFiniteDouble(tokens[3], dy)) {
            return fail(protocol::ErrorCode::InvalidArgument, "pan arguments must be finite numbers");
        }

        if (std::abs(dx) > Camera::kMaxCoordinate || std::abs(dy) > Camera::kMaxCoordinate) {
            return fail(protocol::ErrorCode::OutOfRange, "pan delta is out of range");
        }

        return {.command = Command{.kind = Kind::Pan, .dx = dx, .dy = dy}};
    }

    return fail(protocol::ErrorCode::InvalidCommand, "unknown spatial subcommand");
}

} // namespace spatial::command
