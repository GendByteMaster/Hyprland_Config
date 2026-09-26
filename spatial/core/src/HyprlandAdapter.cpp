#include "spatial/HyprlandAdapter.hpp"

#include "spatial/Projection.hpp"

#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopTimer.hpp>

#include <hyprland/src/desktop/state/GlobalWindowController.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>

#include <algorithm>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <utility>
#include <vector>

namespace spatial {
namespace {

constexpr auto kMotionTick = std::chrono::milliseconds(16);
constexpr double kWorkspaceLaneGap = 160.0;

} // namespace

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
    windowFloating_ = Event::bus()->m_events.window.floating.listen([this](PHLWINDOW window) {
        onWindowEligibilityChanged(window);
    });
    windowFullscreen_ = Event::bus()->m_events.window.fullscreen.listen([this](PHLWINDOW window) {
        onWindowEligibilityChanged(window);
    });
    windowMovedWorkspace_ = Event::bus()->m_events.window.moveToWorkspace.listen([this](PHLWINDOW window, PHLWORKSPACE) {
        onWindowMovedWorkspace(window);
    });
    workspaceActivated_ = Event::bus()->m_events.workspace.active.listen([this](PHLWORKSPACE workspace) {
        onWorkspaceActivated(workspace);
    });
    monitorLayoutChanged_ = Event::bus()->m_events.monitor.layoutChanged.listen([this] {
        onMonitorLayoutChanged();
    });

    if (!windowOpened_ || !windowClosed_ || !windowFloating_ || !windowFullscreen_
        || !windowMovedWorkspace_ || !workspaceActivated_ || !monitorLayoutChanged_) {
        stop();
        return false;
    }

    return true;
}

void HyprlandAdapter::stop() noexcept {
    deactivate(true);

    if (pendingProjectionRefresh_ != 0 && g_pEventLoopManager) {
        g_pEventLoopManager->removeDoLater(pendingProjectionRefresh_);
        pendingProjectionRefresh_ = 0;
    }

    if (motionTimer_) {
        motionTimer_->cancel();
        if (g_pEventLoopManager) {
            g_pEventLoopManager->removeTimer(motionTimer_);
        }
        motionTimer_.reset();
    }

    monitorLayoutChanged_.reset();
    workspaceActivated_.reset();
    windowMovedWorkspace_.reset();
    windowFullscreen_.reset();
    windowFloating_.reset();
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

    if (!activateWorkspaceCanvas()) {
        return false;
    }

    std::vector<ManagedWindow> windows;
    std::vector<WindowBinding> bindings;
    windows.reserve(std::min<std::size_t>(Desktop::windowState()->windows().size(), SpatialState::kMaxManagedWindows));
    bindings.reserve(SpatialState::kMaxManagedWindows);

    for (const auto& window : Desktop::windowState()->windows()) {
        const auto compositorRect = currentCompositorRect(window);
        const auto managed = toManagedWindow(window, *desk);
        if (!compositorRect || !managed) {
            continue;
        }

        if (windows.size() >= SpatialState::kMaxManagedWindows) {
            restoreWorkspaceCanvas();
            return false;
        }

        windows.push_back(*managed);
        bindings.push_back(WindowBinding{
            .id = managed->id,
            .window = window,
            .originalCompositorRect = *compositorRect,
        });
    }

    if (!state_->enable(*desk, std::move(windows))) {
        restoreWorkspaceCanvas();
        return false;
    }

    bindings_ = std::move(bindings);
    return true;
}

void HyprlandAdapter::disable() noexcept {
    deactivate(true);
}

PanResult HyprlandAdapter::pan(double dx, double dy) {
    if (state_ == nullptr || !state_->enabled()) {
        return PanResult::Disabled;
    }

    pruneBindings();

    if (!projectionReady()) {
        return PanResult::ProjectionUnavailable;
    }

    if (!state_->pan(dx, dy)) {
        return PanResult::OutOfRange;
    }

    applyProjection();
    return PanResult::Success;
}

PanResult HyprlandAdapter::setZoom(double value) {
    if (state_ == nullptr || !state_->enabled()) {
        return PanResult::Disabled;
    }

    pruneBindings();

    if (!projectionReady()) {
        return PanResult::ProjectionUnavailable;
    }

    if (!state_->setZoom(value)) {
        return PanResult::OutOfRange;
    }

    applyProjection();
    return PanResult::Success;
}

PanResult HyprlandAdapter::resetCamera() {
    if (state_ == nullptr || !state_->enabled()) {
        return PanResult::Disabled;
    }

    pruneBindings();

    if (!projectionReady()) {
        return PanResult::ProjectionUnavailable;
    }

    if (!state_->resetCamera()) {
        return PanResult::OutOfRange;
    }

    applyProjection();
    return PanResult::Success;
}

PanResult HyprlandAdapter::nudge(int xDirection, int yDirection) {
    if (state_ == nullptr || !state_->enabled()) {
        return PanResult::Disabled;
    }

    pruneBindings();
    if (!projectionReady()) {
        return PanResult::ProjectionUnavailable;
    }

    if (!motion_.nudge(xDirection, yDirection, Time::steadyNow())) {
        return PanResult::OutOfRange;
    }

    if (!ensureMotionTimer()) {
        motion_.stop();
        return PanResult::ProjectionUnavailable;
    }

    motionTimer_->updateTimeout(std::chrono::milliseconds(1));
    return PanResult::Success;
}

void HyprlandAdapter::releaseMotion() noexcept {
    motion_.release();
}

void HyprlandAdapter::cancelMotion() noexcept {
    motion_.stop();
    if (motionTimer_ && !motionTimer_->cancelled()) {
        motionTimer_->updateTimeout(std::nullopt);
    }
}

bool HyprlandAdapter::ensureMotionTimer() {
    if (motionTimer_) {
        return true;
    }

    if (!g_pEventLoopManager) {
        return false;
    }

    motionTimer_ = makeShared<CEventLoopTimer>(
        std::nullopt,
        [this](SP<CEventLoopTimer>, void*) {
            onMotionTick();
        },
        nullptr
    );
    g_pEventLoopManager->addTimer(motionTimer_);
    return true;
}

void HyprlandAdapter::onMotionTick() {
    if (state_ == nullptr || !state_->enabled() || !motion_.active()) {
        cancelMotion();
        return;
    }

    const auto frame = motion_.tick(Time::steadyNow());

    if (frame.delta.x != 0.0 || frame.delta.y != 0.0) {
        const auto result = pan(frame.delta.x, frame.delta.y);
        if (result != PanResult::Success) {
            cancelMotion();
            return;
        }
    }

    if (frame.active && motion_.active()) {
        motionTimer_->updateTimeout(kMotionTick);
    } else {
        cancelMotion();
    }
}

void HyprlandAdapter::scheduleProjectionRefresh() {
    if (pendingProjectionRefresh_ != 0 || !g_pEventLoopManager || state_ == nullptr || !state_->enabled()) {
        return;
    }

    pendingProjectionRefresh_ = g_pEventLoopManager->doLater([this] {
        pendingProjectionRefresh_ = 0;

        if (state_ == nullptr || !state_->enabled()) {
            return;
        }

        reassertWorkspaceCanvas();
        pruneBindings();
        if (projectionReady()) {
            applyProjection();
        }
    });
}

void HyprlandAdapter::deactivate(bool restoreGeometry) noexcept {
    cancelMotion();
    if (state_ == nullptr || !state_->enabled()) {
        bindings_.clear();
        restoreWorkspaceCanvas();
        return;
    }

    if (restoreGeometry) {
        restoreOriginalGeometry();
    }

    restoreWorkspaceCanvas();
    bindings_.clear();
    state_->disable();
}

void HyprlandAdapter::restoreOriginalGeometry() noexcept {
    std::vector<SP<Layout::CSpace>> tiledSpaces;

    for (const auto& binding : bindings_) {
        const auto window = binding.window.lock();
        if (!Desktop::View::validMapped(window) || Fullscreen::controller()->isFullscreen(window)) {
            continue;
        }

        if (window->m_isFloating) {
            (void)applyCompositorRect(window, binding.originalCompositorRect);
            continue;
        }

        const auto target = window->layoutTarget();
        const auto space = target ? target->space() : nullptr;
        if (!space) {
            g_pHyprRenderer->damageWindow(window);
            window->setBox(CBox{
                Vector2D{binding.originalCompositorRect.x, binding.originalCompositorRect.y},
                Vector2D{binding.originalCompositorRect.width, binding.originalCompositorRect.height},
            });
            window->updateWindowDecos();
            g_pHyprRenderer->damageWindow(window);
            continue;
        }

        if (!std::ranges::contains(tiledSpaces, space)) {
            tiledSpaces.push_back(space);
        }
    }

    // Tiled targets never leave Hyprland's layout tree. Recalculate the
    // untouched tree to restore canonical geometry exactly.
    for (const auto& space : tiledSpaces) {
        if (space) {
            space->recalculate();
        }
    }
}

void HyprlandAdapter::pruneBindings() {
    if (state_ == nullptr || !state_->enabled()) {
        bindings_.clear();
        return;
    }

    auto it = bindings_.begin();
    while (it != bindings_.end()) {
        const auto window = it->window.lock();
        if (!eligible(window)) {
            (void)state_->removeWindow(it->id);
            it = bindings_.erase(it);
            continue;
        }

        ++it;
    }
}

bool HyprlandAdapter::projectionReady() const {
    if (state_ == nullptr || !state_->enabled() || bindings_.size() != state_->windows().size()) {
        return false;
    }

    for (const auto& binding : bindings_) {
        const auto window = binding.window.lock();
        if (!eligible(window) || !window->layoutTarget() || state_->findWindow(binding.id) == nullptr) {
            return false;
        }
    }

    return true;
}

void HyprlandAdapter::applyProjection() noexcept {
    if (state_ == nullptr || !state_->enabled()) {
        return;
    }

    for (const auto& binding : bindings_) {
        const auto window = binding.window.lock();
        const auto* managed = state_->findWindow(binding.id);
        if (!window || managed == nullptr) {
            continue;
        }

        const auto projected = projectWorldRect(managed->world, state_->camera(), state_->desk());
        (void)applyCompositorRect(window, projected);
    }
}

bool HyprlandAdapter::applyCompositorRect(const PHLWINDOW& window, const Rect& rect) const noexcept {
    if (!eligible(window) || !isValid(rect)) {
        return false;
    }

    const CBox box{
        Vector2D{rect.x, rect.y},
        Vector2D{rect.width, rect.height},
    };

    if (!window->m_isFloating) {
        // Keep the tiled target inside Hyprland's layout tree. Only override
        // the live compositor box. This preserves the split/master topology
        // for exact restoration through space->recalculate().
        g_pHyprRenderer->damageWindow(window);
        window->setBox(box);
        window->updateWindowDecos();
        g_pHyprRenderer->damageWindow(window);
        return true;
    }

    const auto target = window->layoutTarget();
    if (!target) {
        return false;
    }

    target->setPositionGlobal(box, Layout::TARGET_UPDATE_NO_CLIENT_CONFIGURE);
    target->warpPositionSize();
    return true;
}

void HyprlandAdapter::dropBinding(std::string_view id) noexcept {
    std::erase_if(bindings_, [&](const WindowBinding& binding) {
        return binding.id == id;
    });
}

bool HyprlandAdapter::activateWorkspaceCanvas() {
    workspaceBindings_.clear();
    workspaceCanvasActive_ = false;

    // Phase 2 all-workspace projection is deliberately limited to one physical
    // monitor. On multi-monitor setups, changing visibility for hidden tiled
    // workspaces would expose unmanaged tiled windows across monitor ownership
    // boundaries, which Hyprland 0.56 does not support safely.
    if (!tiledProjectionAllowed()) {
        return true;
    }

    PHLMONITOR monitor;
    for (const auto& candidate : State::monitorState()->monitors()) {
        if (!candidate) {
            continue;
        }
        monitor = candidate;
        break;
    }

    if (!monitor || !monitor->m_activeWorkspace) {
        return false;
    }

    std::vector<PHLWORKSPACE> workspaces;
    for (const auto& workspace : State::Workspace::state()->workspaces()) {
        if (!workspace || workspace->type() != Workspace::eWorkspaceType::NORMAL) {
            continue;
        }

        if (workspace->m_monitor.lock() != monitor) {
            continue;
        }

        // Do not snapshot a workspace in the middle of a transition. Warping
        // those animation variables would make exact restoration ambiguous.
        if (workspace->m_alpha->isBeingAnimated() || workspace->m_renderOffset->isBeingAnimated()) {
            return false;
        }

        workspaces.push_back(workspace);
    }

    if (workspaces.empty() || workspaces.size() > SpatialState::kMaxManagedWindows) {
        return false;
    }

    std::ranges::sort(workspaces, [](const PHLWORKSPACE& lhs, const PHLWORKSPACE& rhs) {
        const auto lhsNumber = lhs->numberedID();
        const auto rhsNumber = rhs->numberedID();

        if (lhsNumber && rhsNumber && *lhsNumber != *rhsNumber) {
            return *lhsNumber < *rhsNumber;
        }
        if (lhsNumber.has_value() != rhsNumber.has_value()) {
            return lhsNumber.has_value();
        }
        return lhs->addressableName() < rhs->addressableName();
    });

    const auto activeIt = std::ranges::find(workspaces, monitor->m_activeWorkspace);
    if (activeIt == workspaces.end()) {
        return false;
    }

    const auto activeIndex = static_cast<std::ptrdiff_t>(std::distance(workspaces.begin(), activeIt));
    workspaceBindings_.reserve(workspaces.size());

    for (std::size_t index = 0; index < workspaces.size(); ++index) {
        const auto& workspace = workspaces[index];
        const auto offset = workspace->m_renderOffset->value();

        workspaceBindings_.push_back(WorkspaceBinding{
            .workspace = workspace,
            .originalVisible = workspace->visible(),
            .originalForceRendering = workspace->m_forceRendering,
            .originalAlpha = workspace->m_alpha->value(),
            .originalRenderOffset = Point{offset.x, offset.y},
            .lane = static_cast<int>(static_cast<std::ptrdiff_t>(index) - activeIndex),
        });
    }

    workspaceCanvasActive_ = true;
    reassertWorkspaceCanvas();
    return true;
}

void HyprlandAdapter::restoreWorkspaceCanvas() noexcept {
    if (!workspaceCanvasActive_ && workspaceBindings_.empty()) {
        return;
    }

    for (const auto& binding : workspaceBindings_) {
        const auto workspace = binding.workspace.lock();
        if (!workspace) {
            continue;
        }

        workspace->m_forceRendering = binding.originalForceRendering;
        workspace->m_alpha->setValueAndWarp(binding.originalAlpha);
        workspace->m_renderOffset->setValueAndWarp(Vector2D{
            binding.originalRenderOffset.x,
            binding.originalRenderOffset.y,
        });
        workspace->setVisible(binding.originalVisible);

        if (const auto monitor = workspace->m_monitor.lock(); monitor) {
            g_pHyprRenderer->damageMonitor(monitor);
        }
    }

    workspaceCanvasActive_ = false;
    workspaceBindings_.clear();
    Desktop::globalWindowController()->updateSuspendedStates();
}

void HyprlandAdapter::reassertWorkspaceCanvas() noexcept {
    if (!workspaceCanvasActive_) {
        return;
    }

    for (const auto& binding : workspaceBindings_) {
        const auto workspace = binding.workspace.lock();
        if (!workspace) {
            continue;
        }

        workspace->setVisible(true);
        workspace->m_forceRendering = true;
        workspace->m_alpha->setValueAndWarp(1.0F);
        workspace->m_renderOffset->setValueAndWarp(Vector2D{});

        if (const auto monitor = workspace->m_monitor.lock(); monitor) {
            g_pHyprRenderer->damageMonitor(monitor);
        }
    }

    Desktop::globalWindowController()->updateSuspendedStates();
}

std::optional<int> HyprlandAdapter::workspaceLane(const PHLWORKSPACE& workspace) const noexcept {
    if (!workspaceCanvasActive_) {
        return 0;
    }

    if (!workspace) {
        return std::nullopt;
    }

    const auto it = std::ranges::find_if(workspaceBindings_, [&](const WorkspaceBinding& binding) {
        return binding.workspace.lock() == workspace;
    });
    if (it == workspaceBindings_.end()) {
        return std::nullopt;
    }

    return it->lane;
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

std::optional<Rect> HyprlandAdapter::currentCompositorRect(const PHLWINDOW& window) const {
    if (!eligible(window)) {
        return std::nullopt;
    }

    const auto position = window->position(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    const auto size = window->size(Desktop::View::IGeometric::GEOMETRIC_GOAL);
    Rect rect{
        .x = position.x,
        .y = position.y,
        .width = size.x,
        .height = size.y,
    };

    return isValid(rect) ? std::optional<Rect>{rect} : std::nullopt;
}

bool HyprlandAdapter::eligible(const PHLWINDOW& window) const {
    if (!Desktop::View::validMapped(window)) {
        return false;
    }

    if (Fullscreen::controller()->isFullscreen(window)) {
        return false;
    }

    const auto monitor = window->m_monitor.lock();
    if (!monitor || !window->m_workspace) {
        return false;
    }

    const bool visible = workspaceCanvasActive_
        ? workspaceLane(window->m_workspace).has_value()
        : (window->m_workspace == monitor->m_activeWorkspace || window->m_workspace == monitor->m_activeSpecialWorkspace);
    if (!visible) {
        return false;
    }

    // Hyprland 0.56.2 does not render tiled windows across monitor ownership
    // boundaries. Single-monitor tiled projection is safe because the live
    // box and hit-testing geometry move together while the layout tree stays
    // untouched. Multi-monitor tiled cross-seam support is intentionally
    // deferred.
    return window->m_isFloating || tiledProjectionAllowed();
}

bool HyprlandAdapter::tiledProjectionAllowed() const {
    std::size_t monitors = 0;
    for (const auto& monitor : State::monitorState()->monitors()) {
        if (monitor) {
            ++monitors;
        }
    }

    return monitors == 1;
}

std::optional<ManagedWindow> HyprlandAdapter::toManagedWindow(const PHLWINDOW& window, const DeskRect& desk) const {
    if (state_ == nullptr) {
        return std::nullopt;
    }

    const auto compositorRect = currentCompositorRect(window);
    if (!compositorRect) {
        return std::nullopt;
    }

    auto world = captureWorldRect(*compositorRect, state_->camera(), desk);
    const auto lane = workspaceLane(window->m_workspace);
    if (!lane) {
        return std::nullopt;
    }

    if (workspaceCanvasActive_) {
        world.x += static_cast<double>(*lane) * (desk.width() + kWorkspaceLaneGap);
    }

    if (!isValid(world)) {
        return std::nullopt;
    }

    return ManagedWindow{
        .id = sessionWindowId(window),
        .world = world,
    };
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

    const auto compositorRect = currentCompositorRect(window);
    const auto managed = toManagedWindow(window, state_->desk());
    if (!compositorRect || !managed || state_->findWindow(managed->id) != nullptr) {
        return;
    }

    if (!state_->addWindow(*managed)) {
        return;
    }

    bindings_.push_back(WindowBinding{
        .id = managed->id,
        .window = window,
        .originalCompositorRect = *compositorRect,
    });

    scheduleProjectionRefresh();
}

void HyprlandAdapter::onWindowClosed(const PHLWINDOW& window) {
    if (state_ == nullptr || !state_->enabled() || !window) {
        return;
    }

    const auto id = sessionWindowId(window);
    (void)state_->removeWindow(id);
    dropBinding(id);
    scheduleProjectionRefresh();
}

void HyprlandAdapter::onWindowEligibilityChanged(const PHLWINDOW& window) {
    if (state_ == nullptr || !state_->enabled() || !window) {
        return;
    }

    const auto id = sessionWindowId(window);

    if (!eligible(window)) {
        (void)state_->removeWindow(id);
        dropBinding(id);
        scheduleProjectionRefresh();
        return;
    }

    if (state_->findWindow(id) != nullptr) {
        scheduleProjectionRefresh();
        return;
    }

    onWindowOpened(window);
}

void HyprlandAdapter::onWindowMovedWorkspace(const PHLWINDOW& window) {
    if (state_ == nullptr || !state_->enabled() || !window) {
        return;
    }

    // World coordinates remain authoritative across ordinary workspace moves.
    // If the destination leaves the managed normal-workspace canvas (for
    // example a special workspace), normal eligibility pruning releases it.
    onWindowEligibilityChanged(window);
}

void HyprlandAdapter::onWorkspaceActivated(const PHLWORKSPACE& workspace) {
    if (state_ == nullptr || !state_->enabled() || !workspaceCanvasActive_ || !workspace) {
        return;
    }

    const auto lane = workspaceLane(workspace);
    if (!lane) {
        return;
    }

    // Treat the user's ordinary workspace hotkey as a camera jump while
    // Spatial is active, then remember that workspace as the one that should
    // be visible again when Spatial exits.
    for (auto& binding : workspaceBindings_) {
        const auto candidate = binding.workspace.lock();
        if (!candidate || candidate->m_monitor != workspace->m_monitor) {
            continue;
        }

        const bool active = candidate == workspace;
        binding.originalVisible = active;
        binding.originalAlpha = active ? 1.0F : 0.0F;
        binding.originalRenderOffset = {};
    }

    reassertWorkspaceCanvas();

    if (state_->resetCamera()) {
        const double laneDelta = static_cast<double>(*lane) * (state_->desk().width() + kWorkspaceLaneGap);
        (void)state_->pan(laneDelta, 0.0);
    }

    scheduleProjectionRefresh();
}

void HyprlandAdapter::onMonitorLayoutChanged() {
    if (state_ == nullptr || !state_->enabled()) {
        return;
    }

    // Hyprland has already changed monitor topology at this point. Restoring
    // pre-change compositor coordinates could place windows off-screen, so the
    // safe Phase 1 behavior is to relinquish spatial ownership without restore.
    deactivate(false);
}

} // namespace spatial
