#pragma once

#include "spatial/Camera.hpp"
#include "spatial/Geometry.hpp"

namespace spatial {

[[nodiscard]] Rect captureWorldRect(const Rect& compositorRect, const Camera& camera, const DeskRect& desk) noexcept;
[[nodiscard]] Rect projectWorldRect(const Rect& worldRect, const Camera& camera, const DeskRect& desk) noexcept;

} // namespace spatial
