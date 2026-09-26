#pragma once

#include "spatial/CameraMotion.hpp"
#include "spatial/SpatialState.hpp"

#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

class CEventLoopTimer;

namespace spatial {

enum class PanResult {
    Success,
    Disabled,
    OutOfRange,
    ProjectionUnavailable,
};

class HyprlandAdapter {
public:
    HyprlandAdapter() = default;
    ~HyprlandAdapter();

    HyprlandAdapter(const HyprlandAdapter&) = delete;
    HyprlandAdapter& operator=(const HyprlandAdapter&) = delete;

    [[nodiscard]] bool start(SpatialState& state);
    void stop() noexcept;

    [[nodiscard]] bool enable();
    void disable() noexcept;
    [[nodiscard]] PanResult pan(double dx, double dy);
    [[nodiscard]] PanResult setZoom(double value);
    [[nodiscard]] PanResult resetCamera();
    [[nodiscard]] PanResult arrangeOverview();
    [[nodiscard]] bool selectAtPointer();
    [[nodiscard]] PanResult nudge(int xDirection, int yDirection);
    void releaseMotion() noexcept;
    void cancelMotion() noexcept;

private:
    struct WindowBinding {
        SessionWindowId id;
        PHLWINDOWREF window;
        Rect originalCompositorRect;
    };

    struct WorkspaceBinding {
        PHLWORKSPACEREF workspace;
        bool originalVisible = false;
        bool originalForceRendering = false;
        float originalAlpha = 0.0F;
        Point originalRenderOffset{};
        int lane = 0;
    };

    [[nodiscard]] std::optional<DeskRect> currentDesk() const;
    [[nodiscard]] std::optional<Rect> currentCompositorRect(const PHLWINDOW& window) const;
    [[nodiscard]] std::optional<ManagedWindow> toManagedWindow(const PHLWINDOW& window, const DeskRect& desk) const;
    [[nodiscard]] bool eligible(const PHLWINDOW& window) const;
    [[nodiscard]] bool tiledProjectionAllowed() const;
    [[nodiscard]] static std::string sessionWindowId(const PHLWINDOW& window);

    [[nodiscard]] bool activateWorkspaceCanvas();
    void restoreWorkspaceCanvas() noexcept;
    void reassertWorkspaceCanvas() noexcept;
    [[nodiscard]] std::optional<int> workspaceLane(const PHLWORKSPACE& workspace) const noexcept;

    void deactivate(bool restoreGeometry) noexcept;
    void restoreOriginalGeometry() noexcept;
    void pruneBindings();
    [[nodiscard]] bool projectionReady() const;
    void applyProjection() noexcept;
    [[nodiscard]] bool applyCompositorRect(const PHLWINDOW& window, const Rect& rect) const noexcept;
    void dropBinding(std::string_view id) noexcept;

    [[nodiscard]] bool ensureMotionTimer();
    void onMotionTick();
    void scheduleProjectionRefresh();

    void onWindowOpened(const PHLWINDOW& window);
    void onWindowClosed(const PHLWINDOW& window);
    void onWindowEligibilityChanged(const PHLWINDOW& window);
    void onWindowMovedWorkspace(const PHLWINDOW& window);
    void onWorkspaceActivated(const PHLWORKSPACE& workspace);
    void onMonitorLayoutChanged();

    SpatialState* state_ = nullptr;
    std::vector<WindowBinding> bindings_;
    std::vector<WorkspaceBinding> workspaceBindings_;
    bool workspaceCanvasActive_ = false;
    bool overviewModeActive_ = false;
    CameraMotion motion_;
    SP<CEventLoopTimer> motionTimer_;
    std::uint64_t pendingProjectionRefresh_ = 0;
    CHyprSignalListener windowOpened_;
    CHyprSignalListener windowClosed_;
    CHyprSignalListener windowFloating_;
    CHyprSignalListener windowFullscreen_;
    CHyprSignalListener windowMovedWorkspace_;
    CHyprSignalListener workspaceActivated_;
    CHyprSignalListener monitorLayoutChanged_;
};

} // namespace spatial
