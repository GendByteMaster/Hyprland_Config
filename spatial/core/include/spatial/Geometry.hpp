#pragma once

#include <cmath>

namespace spatial {

struct Point {
    double x = 0.0;
    double y = 0.0;

    friend bool operator==(const Point&, const Point&) = default;
};

struct Rect {
    double x = 0.0;
    double y = 0.0;
    double width = 0.0;
    double height = 0.0;

    friend bool operator==(const Rect&, const Rect&) = default;
};

struct DeskRect {
    double minX = 0.0;
    double minY = 0.0;
    double maxX = 0.0;
    double maxY = 0.0;

    [[nodiscard]] double width() const noexcept { return maxX - minX; }
    [[nodiscard]] double height() const noexcept { return maxY - minY; }

    friend bool operator==(const DeskRect&, const DeskRect&) = default;
};

[[nodiscard]] inline bool isFinite(double value) noexcept {
    return std::isfinite(value);
}

[[nodiscard]] inline bool isFinite(Point point) noexcept {
    return isFinite(point.x) && isFinite(point.y);
}

[[nodiscard]] inline bool isValid(Rect rect) noexcept {
    return isFinite(rect.x) && isFinite(rect.y) && isFinite(rect.width) && isFinite(rect.height) && rect.width >= 0.0 && rect.height >= 0.0;
}

[[nodiscard]] inline bool isValid(DeskRect desk) noexcept {
    return isFinite(desk.minX) && isFinite(desk.minY) && isFinite(desk.maxX) && isFinite(desk.maxY) && desk.maxX >= desk.minX && desk.maxY >= desk.minY;
}

[[nodiscard]] inline Point compositorToDesk(Point compositor, DeskRect desk) noexcept {
    return {
        compositor.x - desk.minX,
        compositor.y - desk.minY,
    };
}

[[nodiscard]] inline Point deskToCompositor(Point deskPoint, DeskRect desk) noexcept {
    return {
        deskPoint.x + desk.minX,
        deskPoint.y + desk.minY,
    };
}

} // namespace spatial
