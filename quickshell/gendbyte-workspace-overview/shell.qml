//@ pragma AppId gendbyte-workspace-overview
//@ pragma ShellId gendbyte-workspace-overview
//@ pragma NativeTextRendering

import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  Overview {
    id: overview
  }

  IpcHandler {
    target: "gendbyte-workspace-overview"

    function toggle(): string {
      overview.toggleOverview()
      return "ok"
    }

    function show(): string {
      overview.showOverview()
      return "ok"
    }

    function toggleSwitcher(): string {
      overview.toggleTaskSwitcher()
      return "ok"
    }

    function showSwitcher(): string {
      overview.showTaskSwitcher()
      return "ok"
    }

    function hide(): string {
      overview.hideOverview()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }
}
