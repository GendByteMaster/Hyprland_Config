#include "spatial/Command.hpp"
#include "spatial/Protocol.hpp"
#include "spatial/SpatialState.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>

#include <stdexcept>
#include <string>

namespace {

HANDLE g_pluginHandle = nullptr;
spatial::SpatialState g_state;

void notifyFailure(const std::string& message) {
    if (g_pluginHandle == nullptr) {
        return;
    }

    HyprlandAPI::addNotification(
        g_pluginHandle,
        "[gendbyte-spatial] " + message,
        CHyprColor{1.0, 0.2, 0.2, 1.0},
        6000.F
    );
}

std::string handleHyprCtl(eHyprCtlOutputFormat, std::string request) {
    const auto parsed = spatial::command::parse(request);
    if (!parsed) {
        return spatial::protocol::errorJson(parsed.error, parsed.message);
    }

    switch (parsed.command->kind) {
    case spatial::command::Kind::Status:
        return spatial::protocol::statusJson(g_state);
    case spatial::command::Kind::Windows:
        return spatial::protocol::windowsJson(g_state);
    case spatial::command::Kind::Camera:
        return spatial::protocol::cameraJson(g_state);
    case spatial::command::Kind::Enable:
        return spatial::protocol::errorJson(
            spatial::protocol::ErrorCode::InternalError,
            "spatial enable is gated until the monitor topology adapter is initialized"
        );
    case spatial::command::Kind::Disable:
        g_state.disable();
        return spatial::protocol::statusJson(g_state);
    case spatial::command::Kind::Pan:
        if (!g_state.enabled()) {
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::SpatialDisabled,
                "spatial mode is not enabled"
            );
        }
        if (!g_state.pan(parsed.command->dx, parsed.command->dy)) {
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::OutOfRange,
                "camera pan would exceed the allowed range"
            );
        }
        return spatial::protocol::cameraJson(g_state);
    }

    return spatial::protocol::errorJson(
        spatial::protocol::ErrorCode::InternalError,
        "unreachable command state"
    );
}

} // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_pluginHandle = handle;

    const std::string serverHash = __hyprland_api_get_hash();
    const std::string clientHash = __hyprland_api_get_client_hash();

    if (serverHash != clientHash) {
        notifyFailure("refusing to load: Hyprland/header build mismatch");
        g_pluginHandle = nullptr;
        throw std::runtime_error("gendbyte-spatial: Hyprland/header build mismatch");
    }

    g_state.disable();

    const auto command = HyprlandAPI::registerHyprCtlCommand(
        g_pluginHandle,
        SHyprCtlCommand{
            .name = "gendbyte-spatial",
            .exact = false,
            .fn = handleHyprCtl,
        }
    );

    if (!command) {
        notifyFailure("failed to register hyprctl command");
        g_pluginHandle = nullptr;
        throw std::runtime_error("gendbyte-spatial: failed to register hyprctl command");
    }

    return {
        "gendbyte-spatial",
        "Developer Spatial Desktop core for Hyprland",
        "GendByteMaster",
        "0.1.0-dev",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_state.disable();
    g_pluginHandle = nullptr;
}
