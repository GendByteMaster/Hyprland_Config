//@ pragma AppId gendbyte-project-launcher
//@ pragma ShellId gendbyte-project-launcher
//@ pragma NativeTextRendering

import Quickshell
import Quickshell.Io

ShellRoot {
  id: root

  function launcher() {
    launcherLoader.active = true
    return launcherLoader.item
  }

  LazyLoader {
    id: launcherLoader
    active: false

    ProjectLauncher {
    }
  }

  IpcHandler {
    target: "gendbyte-project-launcher"

    function toggle(): string {
      root.launcher().toggleLauncher()
      return "ok"
    }

    function show(): string {
      root.launcher().showLauncher()
      return "ok"
    }

    function hide(): string {
      if (launcherLoader.active && launcherLoader.item)
        launcherLoader.item.closeLauncher()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }
}
