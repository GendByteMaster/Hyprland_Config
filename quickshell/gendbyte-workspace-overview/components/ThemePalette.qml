import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

  property string colorsPath: String(Quickshell.env("OMARCHY_THEME_COLORS") || "")

  property color background: "#0b0b0b"
  property color foreground: "#eeeeee"
  property color accent: "#ff8a3d"
  property color muted: "#707070"
  property color darkBackground: "#151515"
  property color lighterBackground: "#202020"
  property color selection: "#2a211b"
  property color border: "#383838"
  property string mode: "dark"

  function colorWithAlpha(value, alpha) {
    var text = String(value || "")
    if (!/^#[0-9a-fA-F]{6}$/.test(text))
      return value

    var r = parseInt(text.substring(1, 3), 16) / 255
    var g = parseInt(text.substring(3, 5), 16) / 255
    var b = parseInt(text.substring(5, 7), 16) / 255
    return Qt.rgba(r, g, b, alpha)
  }

  function parseToml(text) {
    var result = {}
    var lines = String(text || "").split("\n")

    for (var i = 0; i < lines.length; ++i) {
      var line = lines[i].trim()
      if (line === "" || line.indexOf("#") === 0)
        continue

      var match = /^([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*(?:#.*)?$/.exec(line)
      if (match)
        result[match[1]] = match[2]
    }

    return result
  }

  function apply(raw) {
    if (!raw)
      return

    mode = String(raw.mode || "dark")
    background = raw.background || "#0b0b0b"
    foreground = raw.foreground || "#eeeeee"
    accent = raw.accent || "#ff8a3d"
    muted = raw.muted || raw.color8 || "#707070"
    darkBackground = raw.dark_background || raw.color0 || background
    lighterBackground = raw.lighter_background || raw.color8 || "#202020"
    selection = raw.selection || lighterBackground
    border = raw.color8 || muted
  }

  function refresh() {
    if (colorsPath === "")
      return
    themeProcess.exec(["cat", colorsPath])
  }

  Process {
    id: themeProcess

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(root.parseToml(this.text))
    }
  }

  Component.onCompleted: refresh()
}
