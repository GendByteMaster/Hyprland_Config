#include "spatial/HyprlandAdapter.hpp"

#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <vector>

namespace spatial {

HyprlandAdapter::~HyprlandAdapter() {
    stop();
}

bool HyprlandAdapter::start(SpatialState& state) {
    if (state_ != nullptr) {
        return state_ == &state;
    }

    state_ = &state;

    windowOpened_ = Event::bus()->m_events.window.openLate.listen([this](PHLWINDOW window) {
        onWindowOpened(window);
    });
    windowClosed_ = Event::bus()->m_events.window.close.listen([this](PHLWINDOW window) {
        onWindowClosed(window);
    });
    monitorLayoutChanged_ = Event::bus()->m_events.monitor.layoutChanged.listen([this] {
        onMonitorLayoutChanged();
    });

    if (!windowOpened_ || !windowClosed_ || !monitorLayoutChanged_) {
        stop();
        return false;
    }

    return true;
}

void HyprlandAdapter::stop() noexcept {
    disable();

    monitorLayoutChanged_.reset();
    windowClosed_.reset();
    windowOpened_.reset();
    state_ = nullptr;
}

bool HyprlandAdapter::enable() {
    if (state_ == nullptr) {
        return false;
    }

    if (state_->enabled()) {
        return true;
    }

    const auto desk = currentDesk();
    if (!desk) {
        return false;
    }

    std::vector<ManagedWindow> windows;
    windows.reserve(std::min<std::size_t>(Desktop::windowState()->windows().size(), SpatialState::kMaxManagedWindows));

    for (const auto& window : Desktop::windowState()->windows()) {
        const auto managed = toManagedWindow(window, *desk);
        if (!managed) {
            continue;
        }

        if (windows.size() >= SpatialState::kMaxManagedWindows) {
            return false;
        }
        windows.push_back(*managed);
    }

    return state_->enable(*desk, std::move(windows));
}

void HyprlandAdapter::disable() noexcept {
    if (state_ != nullptr) {
        state_->disable();
    }
}

std::optional<DeskRect> HyprlandAdapter::currentDesk() const {
    const auto& monitors = State::monitorState()->monitors();
    if (monitors.empty()) {
        return std::nullopt;
    }

    DeskRect desk{
        .minX = std::numeric_limits<double>::infinity(),
        .minY = std::numeric_limits<double>::infinity(),
        .maxX = -std::numeric_limits<double>::infinity(),
        .maxY = -std::numeric_limits<double>::infinity(),
    };

    std::size_t validMonitors = 0;
    for (const auto& monitor : monitors) {
        if (!monitor) {
            continue;
        }

        const double x = monitor->m_position.x;
        const double y = monitor->m_position.y;
        const double width = monitor->m_size.x;
        const double height = monitor->m_size.y;
        if (!isFinite(x) || !isFinite(y) || !isFinite(width) || !isFinite(height) || width <= 0.0 || height <= 0.0) {
            continue;
        }

        desk.minX = std::min(desk.minX, x);
        desk.minY = std::min(desk.minY, y);
        desk.maxX = std::max(desk.maxX, x + width);
        desk.maxY = std::max(desk.maxY, y + height);
        ++validMonitors;
    }

    if (validMonitors == 0 || !isValid(desk)) {
        return std::nullopt;
    }

    return desk;
}

bool HyprlandAdapter::eligible(const PHLWINDOW& window) const {
    if (!Desktop::View::validMapped(window) || !window->m_isFloating) {
        return false;
    }

    if (Fullscreen::controller()->isFullscreen(window)) {
        return false;
    }

    const auto monitor = window->m_monitor.lock();
    if (!monitor || !window->m_workspace) {
        return false;
    }

    return window->m_workspace == monitor->m_activeWorkspace || window->m_workspace == monitor->m_activeSpecialWorkspace;
}

std::optional<ManagedWindow> HyprlandAdapter::toManagedWindow(const PHLWINDOW& window, const DeskRect& desk) const {
    if (state_ == nullptr || !eligible(window)) {
        return std::nullopt;
    }

    const auto compositorPosition = window->position(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    const auto size = window->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);

    const Point deskPosition = compositorToDesk({compositorPosition.x, compositorPosition.y}, desk);
    const Point worldPosition = state_->camera().deskToWorld(deskPosition);

    ManagedWindow managed{
        .id = sessionWindowId(window),
        .world = {
            .x = worldPosition.x,
            .y = worldPosition.y,
            .width = size.x,
            .height = size.y,
        },
    };

    if (!isValid(managed.world)) {
        return std::nullopt;
    }

    return managed;
}

std::string HyprlandAdapter::sessionWindowId(const PHLWINDOW& window) {
    std::ostringstream out;
    out << "0x" << std::hex << reinterpret_cast<std::uintptr_t>(window.get());
    return out.str();
}

void HyprlandAdapter::onWindowOpened(const PHLWINDOW& window) {
    if (state_ == nullptr || !state_->enabled()) {
        return;
    }

    const auto managed = toManagedWindow(window, state_->desk());
    if (!managed) {
        return;
    }

    (void)state_->addWindow(*managed);
}

void HyprlandAdapter::onWindowClosed(const PHLWINDOW& window) {
    if (state_ == nullptr || !state_->enabled() || !window) {
        return;
    }

    (void)state_->removeWindow(sessionWindowId(window));
}

void HyprlandAdapter::onMonitorLayoutChanged() {
    if (state_ == nullptr || !state_->enabled()) {
        return;
    }

    // Phase 1 deliberately fails closed on topology changes. A later phase may
    // preserve an anchor across monitor reconfiguration once that behavior is
    // covered by nested multi-monitor tests.
    disable();
}

} // namespace spatial
