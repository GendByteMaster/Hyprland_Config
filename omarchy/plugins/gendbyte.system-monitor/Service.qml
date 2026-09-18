import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property real cpuPercent: 0
  property real cpuGhz: 0
  property real memoryPercent: 0
  property real memoryUsedGib: 0
  property real memoryTotalGib: 0
  property real gpuPercent: 0
  property real networkRxBps: 0
  property real networkTxBps: 0
  property real temperatureC: 0
  property bool hasCpu: false
  property bool hasCpuFrequency: false
  property bool hasMemory: false
  property bool hasMemorySize: false
  property bool hasGpu: false
  property bool hasNetwork: false
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
    hasCpuFrequency = false
    hasMemory = false
    hasMemorySize = false
    hasGpu = false
    hasNetwork = false
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
    var cpuFrequency = parseMetric(values.cpu_ghz)
    var memory = parseMetric(values.mem)
    var memoryUsed = parseMetric(values.mem_used_gib)
    var memoryTotal = parseMetric(values.mem_total_gib)
    var gpu = parseMetric(values.gpu)
    var networkRx = parseMetric(values.net_rx_bps)
    var networkTx = parseMetric(values.net_tx_bps)
    var temperature = parseMetric(values.temp)

    hasCpu = cpu !== null && cpu >= 0 && cpu <= 100
    hasCpuFrequency = cpuFrequency !== null && cpuFrequency > 0 && cpuFrequency <= 20
    hasMemory = memory !== null && memory >= 0 && memory <= 100
    hasMemorySize = memoryUsed !== null && memoryTotal !== null
      && memoryUsed >= 0 && memoryTotal > 0 && memoryUsed <= memoryTotal
    hasGpu = gpu !== null && gpu >= 0 && gpu <= 100
    hasNetwork = networkRx !== null && networkTx !== null && networkRx >= 0 && networkTx >= 0
    hasTemperature = temperature !== null && temperature >= 0 && temperature <= 150

    if (hasCpu) cpuPercent = cpu
    if (hasCpuFrequency) cpuGhz = cpuFrequency
    if (hasMemory) memoryPercent = memory
    if (hasMemorySize) {
      memoryUsedGib = memoryUsed
      memoryTotalGib = memoryTotal
    }
    if (hasGpu) gpuPercent = gpu
    if (hasNetwork) {
      networkRxBps = networkRx
      networkTxBps = networkTx
    }
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
