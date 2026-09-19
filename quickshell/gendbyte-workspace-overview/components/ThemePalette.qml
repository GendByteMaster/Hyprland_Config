import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

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

  function mix(left, right, amount) {
    var t = Math.max(0, Math.min(1, Number(amount)))
    return Qt.rgba(
      left.r + (right.r - left.r) * t,
      left.g + (right.g - left.g) * t,
      left.b + (right.b - left.b) * t,
      left.a + (right.a - left.a) * t
    )
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

    var derivedMuted = mix(foreground, background, 0.52)
    var raisedSource = raw.lighter_background || raw.selection || foreground
    var selectionSource = raw.selection || raw.lighter_background || accent
    var borderSource = raw.muted || foreground

    muted = raw.muted || derivedMuted
    darkBackground = raw.dark_background || background

    // Theme palette values can be intentionally high-contrast. For shell
    // surfaces keep them near the base background so a bright token cannot
    // turn cards/title bars into white slabs on an otherwise dark theme.
    lighterBackground = mix(background, raisedSource, mode === "light" ? 0.20 : 0.34)
    selection = mix(background, selectionSource, mode === "light" ? 0.30 : 0.46)
    border = mix(background, borderSource, mode === "light" ? 0.34 : 0.46)
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
