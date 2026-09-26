#pragma once

#include "spatial/Camera.hpp"
#include "spatial/Geometry.hpp"

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace spatial {

using SessionWindowId = std::string;

struct ManagedWindow {
    SessionWindowId id;
    Rect world;

    friend bool operator==(const ManagedWindow&, const ManagedWindow&) = default;
};

class SpatialState {
public:
    static constexpr std::size_t kMaxManagedWindows = 512;
    static constexpr std::size_t kMaxWindowIdLength = 256;

    [[nodiscard]] bool enabled() const noexcept;
    [[nodiscard]] std::uint64_t epoch() const noexcept;
    [[nodiscard]] const Camera& camera() const noexcept;
    [[nodiscard]] const DeskRect& desk() const noexcept;

    [[nodiscard]] bool enable(DeskRect desk) noexcept;
    [[nodiscard]] bool enable(DeskRect desk, std::vector<ManagedWindow> windows);
    void disable() noexcept;

    [[nodiscard]] bool addWindow(ManagedWindow window);
    [[nodiscard]] bool removeWindow(std::string_view id) noexcept;
    [[nodiscard]] bool setWindowWorld(std::string_view id, Rect world) noexcept;
    [[nodiscard]] const ManagedWindow* findWindow(std::string_view id) const noexcept;

    [[nodiscard]] bool pan(double dx, double dy) noexcept;
    [[nodiscard]] bool setZoom(double value) noexcept;
    [[nodiscard]] bool resetCamera() noexcept;

    [[nodiscard]] std::span<const ManagedWindow> windows() const noexcept;

private:
    [[nodiscard]] static bool validWindow(const ManagedWindow& window) noexcept;
    [[nodiscard]] static bool validWindowSet(const std::vector<ManagedWindow>& windows);

    bool enabled_ = false;
    std::uint64_t epoch_ = 0;
    Camera camera_{};
    DeskRect desk_{};
    std::vector<ManagedWindow> windows_{};
};

} // namespace spatial
