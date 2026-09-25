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
