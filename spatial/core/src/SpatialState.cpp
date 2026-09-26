#include "spatial/SpatialState.hpp"

#include <algorithm>
#include <unordered_set>
#include <utility>

namespace spatial {

bool SpatialState::enabled() const noexcept {
    return enabled_;
}

std::uint64_t SpatialState::epoch() const noexcept {
    return epoch_;
}

const Camera& SpatialState::camera() const noexcept {
    return camera_;
}

const DeskRect& SpatialState::desk() const noexcept {
    return desk_;
}

bool SpatialState::enable(DeskRect desk) noexcept {
    if (!isValid(desk)) {
        return false;
    }

    if (enabled_) {
        return desk_ == desk;
    }

    enabled_ = true;
    desk_ = desk;
    camera_ = Camera{};
    windows_.clear();
    ++epoch_;
    return true;
}

bool SpatialState::enable(DeskRect desk, std::vector<ManagedWindow> windows) {
    if (enabled_ || !isValid(desk) || !validWindowSet(windows)) {
        return false;
    }

    enabled_ = true;
    desk_ = desk;
    camera_ = Camera{};
    windows_ = std::move(windows);
    ++epoch_;
    return true;
}

void SpatialState::disable() noexcept {
    if (!enabled_) {
        return;
    }

    enabled_ = false;
    camera_ = Camera{};
    desk_ = DeskRect{};
    windows_.clear();
    ++epoch_;
}

bool SpatialState::validWindow(const ManagedWindow& window) noexcept {
    return !window.id.empty() && window.id.size() <= kMaxWindowIdLength && isValid(window.world);
}

bool SpatialState::validWindowSet(const std::vector<ManagedWindow>& windows) {
    if (windows.size() > kMaxManagedWindows) {
        return false;
    }

    std::unordered_set<std::string_view> ids;
    ids.reserve(windows.size());

    for (const auto& window : windows) {
        if (!validWindow(window) || !ids.emplace(window.id).second) {
            return false;
        }
    }

    return true;
}

bool SpatialState::addWindow(ManagedWindow window) {
    if (!enabled_ || !validWindow(window) || windows_.size() >= kMaxManagedWindows) {
        return false;
    }

    if (findWindow(window.id) != nullptr) {
        return false;
    }

    windows_.push_back(std::move(window));
    ++epoch_;
    return true;
}

bool SpatialState::removeWindow(std::string_view id) noexcept {
    if (!enabled_ || id.empty()) {
        return false;
    }

    const auto it = std::find_if(windows_.begin(), windows_.end(), [&](const ManagedWindow& window) {
        return window.id == id;
    });
    if (it == windows_.end()) {
        return false;
    }

    windows_.erase(it);
    ++epoch_;
    return true;
}

const ManagedWindow* SpatialState::findWindow(std::string_view id) const noexcept {
    const auto it = std::find_if(windows_.begin(), windows_.end(), [&](const ManagedWindow& window) {
        return window.id == id;
    });
    return it == windows_.end() ? nullptr : &*it;
}

bool SpatialState::pan(double dx, double dy) noexcept {
    if (!enabled_) {
        return false;
    }

    const auto before = camera_.position();
    if (!camera_.pan(dx, dy)) {
        return false;
    }

    if (camera_.position() != before) {
        ++epoch_;
    }
    return true;
}

bool SpatialState::setZoom(double value) noexcept {
    if (!enabled_) {
        return false;
    }

    const auto beforeZoom = camera_.zoom();
    const auto beforePosition = camera_.position();
    const Point deskCenter{desk_.width() / 2.0, desk_.height() / 2.0};
    const auto worldCenter = camera_.deskToWorld(deskCenter);

    if (!camera_.setZoom(value)) {
        return false;
    }

    const Point nextPosition{
        worldCenter.x - deskCenter.x / value,
        worldCenter.y - deskCenter.y / value,
    };

    if (!camera_.setPosition(nextPosition)) {
        (void)camera_.setZoom(beforeZoom);
        (void)camera_.setPosition(beforePosition);
        return false;
    }

    if (camera_.zoom() != beforeZoom || camera_.position() != beforePosition) {
        ++epoch_;
    }
    return true;
}

std::span<const ManagedWindow> SpatialState::windows() const noexcept {
    return windows_;
}

} // namespace spatial
