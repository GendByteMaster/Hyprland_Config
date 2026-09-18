//@ pragma AppId gendbyte-project-launcher
//@ pragma ShellId gendbyte-project-launcher
//@ pragma NativeTextRendering

import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  ProjectLauncher {
    id: launcher
  }

  IpcHandler {
    target: "gendbyte-project-launcher"

    function toggle(): string {
      launcher.toggleLauncher()
      return "ok"
    }

    function show(): string {
      launcher.showLauncher()
      return "ok"
    }

    function hide(): string {
      launcher.closeLauncher()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }
}
