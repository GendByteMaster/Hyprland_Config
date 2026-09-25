#include "spatial/Protocol.hpp"

#include <iomanip>
#include <limits>
#include <locale>
#include <sstream>

namespace spatial::protocol {
namespace {

void appendJsonString(std::ostringstream& out, std::string_view value) {
    static constexpr char kHex[] = "0123456789abcdef";
    out << '"';
    for (const char raw : value) {
        const auto ch = static_cast<unsigned char>(raw);
        switch (ch) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\b': out << "\\b"; break;
        case '\f': out << "\\f"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (ch < 0x20) {
                out << "\\u00" << kHex[(ch >> 4) & 0x0f] << kHex[ch & 0x0f];
            } else {
                out << static_cast<char>(ch);
            }
        }
    }
    out << '"';
}

std::ostringstream jsonStream() {
    std::ostringstream out;
    out.imbue(std::locale::classic());
    out << std::setprecision(std::numeric_limits<double>::max_digits10);
    return out;
}

void appendCamera(std::ostringstream& out, const Camera& camera) {
    const auto pos = camera.position();
    out << "{\"x\":" << pos.x << ",\"y\":" << pos.y << ",\"zoom\":" << camera.zoom() << '}';
}

void appendDesk(std::ostringstream& out, const DeskRect& desk) {
    out << "{\"min_x\":" << desk.minX
        << ",\"min_y\":" << desk.minY
        << ",\"max_x\":" << desk.maxX
        << ",\"max_y\":" << desk.maxY << '}';
}

void appendRect(std::ostringstream& out, const Rect& rect) {
    out << "{\"x\":" << rect.x
        << ",\"y\":" << rect.y
        << ",\"width\":" << rect.width
        << ",\"height\":" << rect.height << '}';
}

} // namespace

std::string_view errorCodeName(ErrorCode code) noexcept {
    switch (code) {
    case ErrorCode::SpatialDisabled: return "SPATIAL_DISABLED";
    case ErrorCode::InvalidCommand: return "INVALID_COMMAND";
    case ErrorCode::InvalidArgument: return "INVALID_ARGUMENT";
    case ErrorCode::OutOfRange: return "OUT_OF_RANGE";
    case ErrorCode::InternalError: return "INTERNAL_ERROR";
    }
    return "INTERNAL_ERROR";
}

std::string statusJson(const SpatialState& state) {
    auto out = jsonStream();
    out << "{\"protocol\":" << kVersion
        << ",\"enabled\":" << (state.enabled() ? "true" : "false")
        << ",\"epoch\":" << state.epoch()
        << ",\"camera\":";
    appendCamera(out, state.camera());
    out << ",\"desk\":";
    appendDesk(out, state.desk());
    out << ",\"managed_window_count\":" << state.windows().size() << '}';
    return out.str();
}

std::string cameraJson(const SpatialState& state) {
    auto out = jsonStream();
    out << "{\"protocol\":" << kVersion
        << ",\"epoch\":" << state.epoch()
        << ",\"camera\":";
    appendCamera(out, state.camera());
    out << '}';
    return out.str();
}

std::string windowsJson(const SpatialState& state) {
    auto out = jsonStream();
    out << "{\"protocol\":" << kVersion
        << ",\"epoch\":" << state.epoch()
        << ",\"windows\":[";

    bool first = true;
    for (const auto& window : state.windows()) {
        if (!first) {
            out << ',';
        }
        first = false;
        out << "{\"session_id\":";
        appendJsonString(out, window.id);
        out << ",\"world\":";
        appendRect(out, window.world);
        out << '}';
    }

    out << "]}";
    return out.str();
}

std::string errorJson(ErrorCode code, std::string_view message) {
    auto out = jsonStream();
    out << "{\"protocol\":" << kVersion << ",\"error\":{\"code\":";
    appendJsonString(out, errorCodeName(code));
    out << ",\"message\":";
    appendJsonString(out, message);
    out << "}}";
    return out.str();
}

} // namespace spatial::protocol
