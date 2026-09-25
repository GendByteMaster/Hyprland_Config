#pragma once

#include "spatial/Geometry.hpp"

namespace spatial {

class Camera {
public:
    static constexpr double kMinCoordinate = -1.0e9;
    static constexpr double kMaxCoordinate = 1.0e9;

    [[nodiscard]] Point position() const noexcept;
    [[nodiscard]] double zoom() const noexcept;

    [[nodiscard]] bool pan(double dx, double dy) noexcept;
    [[nodiscard]] bool setPosition(Point value) noexcept;
    [[nodiscard]] bool setZoom(double value) noexcept;

    [[nodiscard]] Point deskToWorld(Point desk) const noexcept;
    [[nodiscard]] Point worldToDesk(Point world) const noexcept;

private:
    [[nodiscard]] static bool validCoordinate(double value) noexcept;

    Point position_{};
    double zoom_ = 1.0;
};

} // namespace spatial
