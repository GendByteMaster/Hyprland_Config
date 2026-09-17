import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property real cpuPercent: 0
  property real memoryPercent: 0
  property real temperatureC: 0
  property bool hasCpu: false
  property bool hasMemory: false
  property bool hasTemperature: false
  property date lastSampleAt: new Date(0)
  property bool collectorHealthy: false

  readonly property string collectorPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/gendbyte.system-monitor/telemetry-collector.lua"

  Component.onCompleted: collector.running = true

  function parseMetric(value) {
    var text = String(value === undefined ? "" : value).trim()
    if (text === "-" || text === "") return null
    var number = Number(text)
    return isFinite(number) ? number : null
  }

  function invalidateTelemetry() {
    hasCpu = false
    hasMemory = false
    hasTemperature = false
    collectorHealthy = false
  }

  function acceptSample(line) {
    var parts = String(line || "").trim().split("\t")
    if (parts.length < 4 || parts[0] !== "v1") return

    var values = {}
    for (var i = 1; i < parts.length; i++) {
      var separator = parts[i].indexOf("=")
      if (separator <= 0) continue
      values[parts[i].substring(0, separator)] = parts[i].substring(separator + 1)
    }

    var cpu = parseMetric(values.cpu)
    var memory = parseMetric(values.mem)
    var temperature = parseMetric(values.temp)

    hasCpu = cpu !== null && cpu >= 0 && cpu <= 100
    hasMemory = memory !== null && memory >= 0 && memory <= 100
    hasTemperature = temperature !== null && temperature >= 0 && temperature <= 150

    if (hasCpu) cpuPercent = cpu
    if (hasMemory) memoryPercent = memory
    if (hasTemperature) temperatureC = temperature

    lastSampleAt = new Date()
    collectorHealthy = true
    staleTimer.restart()
  }

  Process {
    id: collector
    command: ["setpriv", "--pdeathsig", "TERM", "lua5.1", root.collectorPath]
    stdout: SplitParser {
      onRead: function(line) { root.acceptSample(line) }
    }
    onExited: function(exitCode) {
      staleTimer.stop()
      root.invalidateTelemetry()
      restartTimer.restart()
    }
  }

  Timer {
    id: staleTimer
    interval: 7000
    repeat: false
    onTriggered: root.invalidateTelemetry()
  }

  Timer {
    id: restartTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (!collector.running) collector.running = true
    }
  }
}
