#pragma once

#include "spatial/SpatialState.hpp"

#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>

#include <optional>
#include <string>

namespace spatial {

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

private:
    [[nodiscard]] std::optional<DeskRect> currentDesk() const;
    [[nodiscard]] std::optional<ManagedWindow> toManagedWindow(const PHLWINDOW& window, const DeskRect& desk) const;
    [[nodiscard]] bool eligible(const PHLWINDOW& window) const;
    [[nodiscard]] static std::string sessionWindowId(const PHLWINDOW& window);

    void onWindowOpened(const PHLWINDOW& window);
    void onWindowClosed(const PHLWINDOW& window);
    void onMonitorLayoutChanged();

    SpatialState* state_ = nullptr;
    CHyprSignalListener windowOpened_;
    CHyprSignalListener windowClosed_;
    CHyprSignalListener monitorLayoutChanged_;
};

} // namespace spatial
