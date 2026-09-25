#include "spatial/Command.hpp"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

} // namespace

int main() {
    using spatial::command::Kind;

    const auto status = spatial::command::parse("gendbyte-spatial status");
    require(status && status.command->kind == Kind::Status, "status parses");

    const auto windows = spatial::command::parse("  gendbyte-spatial\twindows  ");
    require(windows && windows.command->kind == Kind::Windows, "whitespace is normalized");

    const auto camera = spatial::command::parse("gendbyte-spatial camera");
    require(camera && camera.command->kind == Kind::Camera, "camera parses");

    const auto enable = spatial::command::parse("gendbyte-spatial enable");
    require(enable && enable.command->kind == Kind::Enable, "enable parses");

    const auto disable = spatial::command::parse("gendbyte-spatial disable");
    require(disable && disable.command->kind == Kind::Disable, "disable parses");

    const auto pan = spatial::command::parse("gendbyte-spatial pan 125.5 -30.25");
    require(pan && pan.command->kind == Kind::Pan, "pan parses");
    require(pan.command->dx == 125.5 && pan.command->dy == -30.25, "pan values are preserved");

    const auto missing = spatial::command::parse("gendbyte-spatial");
    require(!missing && missing.error == spatial::protocol::ErrorCode::InvalidCommand, "missing subcommand is rejected");

    const auto unknown = spatial::command::parse("gendbyte-spatial explode");
    require(!unknown && unknown.error == spatial::protocol::ErrorCode::InvalidCommand, "unknown subcommand is rejected");

    const auto wrongNamespace = spatial::command::parse("gendbyte-spatial-extra status");
    require(!wrongNamespace && wrongNamespace.error == spatial::protocol::ErrorCode::InvalidCommand, "prefix collision is rejected");

    const auto extra = spatial::command::parse("gendbyte-spatial status extra");
    require(!extra && extra.error == spatial::protocol::ErrorCode::InvalidArgument, "unexpected arguments are rejected");

    const auto missingPan = spatial::command::parse("gendbyte-spatial pan 10");
    require(!missingPan && missingPan.error == spatial::protocol::ErrorCode::InvalidArgument, "incomplete pan is rejected");

    const auto nan = spatial::command::parse("gendbyte-spatial pan nan 0");
    require(!nan && nan.error == spatial::protocol::ErrorCode::InvalidArgument, "NaN is rejected");

    const auto inf = spatial::command::parse("gendbyte-spatial pan inf 0");
    require(!inf && inf.error == spatial::protocol::ErrorCode::InvalidArgument, "infinity is rejected");

    const auto huge = spatial::command::parse("gendbyte-spatial pan 1000000001 0");
    require(!huge && huge.error == spatial::protocol::ErrorCode::OutOfRange, "out-of-range delta is rejected");

    const std::string longRequest(1100, 'x');
    const auto tooLong = spatial::command::parse(longRequest);
    require(!tooLong && tooLong.error == spatial::protocol::ErrorCode::InvalidArgument, "oversized request is rejected");

    std::cout << "command_test: PASS\n";
    return 0;
}
