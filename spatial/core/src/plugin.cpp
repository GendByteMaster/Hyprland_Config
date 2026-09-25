#include "spatial/Command.hpp"
#include "spatial/HyprlandAdapter.hpp"
#include "spatial/Protocol.hpp"
#include "spatial/SpatialState.hpp"

#include <hyprland/src/plugins/PluginAPI.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <array>
#include <stdexcept>
#include <string>

namespace {

HANDLE g_pluginHandle = nullptr;
spatial::SpatialState g_state;
spatial::HyprlandAdapter g_adapter;
SP<SHyprCtlCommand> g_hyprCtlCommand;

constexpr std::string_view kLuaNamespace = "gendbyte_spatial";

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

int luaPanError(lua_State* L, spatial::PanResult result) {
    switch (result) {
    case spatial::PanResult::Success:
        return 0;
    case spatial::PanResult::Disabled:
        return luaL_error(L, "gendbyte-spatial: spatial mode is not enabled");
    case spatial::PanResult::OutOfRange:
        return luaL_error(L, "gendbyte-spatial: camera pan would exceed the allowed range");
    case spatial::PanResult::ProjectionUnavailable:
        return luaL_error(L, "gendbyte-spatial: managed window projection is not currently safe");
    }

    return luaL_error(L, "gendbyte-spatial: unreachable pan result");
}

int luaToggle(lua_State* L) {
    if (lua_gettop(L) != 0) {
        return luaL_error(L, "gendbyte-spatial.toggle: expected no arguments");
    }

    if (g_state.enabled()) {
        g_adapter.disable();
        return 0;
    }

    if (!g_adapter.enable()) {
        return luaL_error(L, "gendbyte-spatial.toggle: failed to initialize spatial desk/window snapshot");
    }

    return 0;
}

int luaPan(lua_State* L) {
    if (lua_gettop(L) != 2) {
        return luaL_error(L, "gendbyte-spatial.pan: expected dx and dy");
    }

    const double dx = static_cast<double>(luaL_checknumber(L, 1));
    const double dy = static_cast<double>(luaL_checknumber(L, 2));

    g_adapter.cancelMotion();
    return luaPanError(L, g_adapter.pan(dx, dy));
}

int luaNudge(lua_State* L) {
    if (lua_gettop(L) != 2) {
        return luaL_error(L, "gendbyte-spatial.nudge: expected xDirection and yDirection");
    }

    const auto xDirection = static_cast<int>(luaL_checkinteger(L, 1));
    const auto yDirection = static_cast<int>(luaL_checkinteger(L, 2));
    return luaPanError(L, g_adapter.nudge(xDirection, yDirection));
}

int luaBrake(lua_State* L) {
    if (lua_gettop(L) != 0) {
        return luaL_error(L, "gendbyte-spatial.brake: expected no arguments");
    }

    g_adapter.releaseMotion();
    return 0;
}

int luaReset(lua_State* L) {
    if (lua_gettop(L) != 0) {
        return luaL_error(L, "gendbyte-spatial.reset: expected no arguments");
    }

    if (!g_state.enabled()) {
        return luaL_error(L, "gendbyte-spatial.reset: spatial mode is not enabled");
    }

    const auto camera = g_state.camera().position();
    g_adapter.cancelMotion();
    return luaPanError(L, g_adapter.pan(-camera.x, -camera.y));
}

struct LuaFunctionRegistration {
    const char* name;
    PLUGIN_LUA_FN function;
};

constexpr std::array<LuaFunctionRegistration, 5> kLuaFunctions{{
    {"toggle", luaToggle},
    {"pan", luaPan},
    {"nudge", luaNudge},
    {"brake", luaBrake},
    {"reset", luaReset},
}};

void unregisterLuaFunctions() noexcept {
    if (g_pluginHandle == nullptr) {
        return;
    }

    for (const auto& registration : kLuaFunctions) {
        (void)HyprlandAPI::removeLuaFunction(
            g_pluginHandle,
            std::string{kLuaNamespace},
            registration.name
        );
    }
}

bool registerLuaFunctions() {
    std::size_t registered = 0;

    for (const auto& registration : kLuaFunctions) {
        if (!HyprlandAPI::addLuaFunction(
                g_pluginHandle,
                std::string{kLuaNamespace},
                registration.name,
                registration.function
            )) {
            for (std::size_t index = 0; index < registered; ++index) {
                (void)HyprlandAPI::removeLuaFunction(
                    g_pluginHandle,
                    std::string{kLuaNamespace},
                    kLuaFunctions[index].name
                );
            }
            return false;
        }

        ++registered;
    }

    return true;
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
        if (!g_adapter.enable()) {
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::InternalError,
                "failed to initialize spatial desk/window snapshot"
            );
        }
        return spatial::protocol::statusJson(g_state);
    case spatial::command::Kind::Disable:
        g_adapter.disable();
        return spatial::protocol::statusJson(g_state);
    case spatial::command::Kind::Pan:
        g_adapter.cancelMotion();
        switch (g_adapter.pan(parsed.command->dx, parsed.command->dy)) {
        case spatial::PanResult::Success:
            return spatial::protocol::cameraJson(g_state);
        case spatial::PanResult::Disabled:
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::SpatialDisabled,
                "spatial mode is not enabled"
            );
        case spatial::PanResult::OutOfRange:
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::OutOfRange,
                "camera pan would exceed the allowed range"
            );
        case spatial::PanResult::ProjectionUnavailable:
            return spatial::protocol::errorJson(
                spatial::protocol::ErrorCode::InternalError,
                "managed window projection is not currently safe"
            );
        }
        break;
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

    if (!g_adapter.start(g_state)) {
        notifyFailure("failed to register Hyprland lifecycle listeners");
        g_pluginHandle = nullptr;
        throw std::runtime_error("gendbyte-spatial: failed to initialize Hyprland adapter");
    }

    g_hyprCtlCommand = HyprlandAPI::registerHyprCtlCommand(
        g_pluginHandle,
        SHyprCtlCommand{
            .name = "gendbyte-spatial",
            .exact = false,
            .fn = handleHyprCtl,
        }
    );

    if (!g_hyprCtlCommand) {
        g_adapter.stop();
        notifyFailure("failed to register hyprctl command");
        g_pluginHandle = nullptr;
        throw std::runtime_error("gendbyte-spatial: failed to register hyprctl command");
    }

    if (!registerLuaFunctions()) {
        (void)HyprlandAPI::unregisterHyprCtlCommand(g_pluginHandle, g_hyprCtlCommand);
        g_hyprCtlCommand.reset();
        g_adapter.stop();
        notifyFailure("failed to register Lua plugin functions");
        g_pluginHandle = nullptr;
        throw std::runtime_error("gendbyte-spatial: failed to register Lua plugin functions");
    }

    return {
        "gendbyte-spatial",
        "Developer Spatial Desktop core for Hyprland",
        "GendByteMaster",
        "0.2.0-dev",
    };
}

APICALL EXPORT void PLUGIN_EXIT() {
    unregisterLuaFunctions();

    if (g_pluginHandle != nullptr && g_hyprCtlCommand) {
        (void)HyprlandAPI::unregisterHyprCtlCommand(g_pluginHandle, g_hyprCtlCommand);
    }
    g_hyprCtlCommand.reset();

    g_adapter.stop();
    g_state.disable();
    g_pluginHandle = nullptr;
}
