#include "spatial/Projection.hpp"

namespace spatial {

Rect captureWorldRect(const Rect& compositorRect, const Camera& camera, const DeskRect& desk) noexcept {
    const Point deskPosition = compositorToDesk({compositorRect.x, compositorRect.y}, desk);
    const Point worldPosition = camera.deskToWorld(deskPosition);

    return {
        .x = worldPosition.x,
        .y = worldPosition.y,
        .width = compositorRect.width,
        .height = compositorRect.height,
    };
}

Rect projectWorldRect(const Rect& worldRect, const Camera& camera, const DeskRect& desk) noexcept {
    const Point deskPosition = camera.worldToDesk({worldRect.x, worldRect.y});
    const Point compositorPosition = deskToCompositor(deskPosition, desk);

    return {
        .x = compositorPosition.x,
        .y = compositorPosition.y,
        .width = worldRect.width,
        .height = worldRect.height,
    };
}

} // namespace spatial
