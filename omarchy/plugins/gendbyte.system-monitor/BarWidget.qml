import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ServiceHost.js" as ServiceHost

BarWidget {
  id: root
  moduleName: "gendbyte.system-monitor"

  QtObject {
    id: dummyService
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
  }

  readonly property var hostedService: {
    var services = bar && bar.shell ? bar.shell._services : null
    return ServiceHost.hostedService(bar)
  }
  readonly property var service: hostedService !== null ? hostedService : dummyService

  function formatRate(bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      var mib = bytesPerSecond / (1024 * 1024)
      return (mib >= 10 ? Math.round(mib).toString() : mib.toFixed(1)) + "MB/s"
    }
    if (bytesPerSecond >= 1024) {
      return Math.round(bytesPerSecond / 1024) + "KB/s"
    }
    return Math.round(bytesPerSecond) + "B/s"
  }

  readonly property string cpuText: service.hasCpu
    ? "CPU " + Math.round(service.cpuPercent) + "%" + (service.hasCpuFrequency ? " " + service.cpuGhz.toFixed(1) + "GHz" : "")
    : "CPU --%"
  readonly property string memoryText: service.hasMemory
    ? "RAM " + Math.round(service.memoryPercent) + "%" + (service.hasMemorySize ? " " + service.memoryUsedGib.toFixed(1) + "/" + service.memoryTotalGib.toFixed(1) + "GB" : "")
    : "RAM --%"
  readonly property string gpuText: service.hasGpu ? "GPU " + Math.round(service.gpuPercent) + "%" : ""
  readonly property string networkText: service.hasNetwork
    ? "↓" + formatRate(service.networkRxBps) + " ↑" + formatRate(service.networkTxBps)
    : ""
  readonly property string temperatureText: service.hasTemperature ? Math.round(service.temperatureC) + "°C" : ""
  readonly property string summaryText: {
    var parts = [cpuText, memoryText]
    if (gpuText.length > 0) parts.push(gpuText)
    if (networkText.length > 0) parts.push(networkText)
    if (temperatureText.length > 0) parts.push(temperatureText)
    return parts.join(" · ")
  }

  implicitWidth: vertical ? barSize : labelText.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: barSize

  Text {
    id: labelText
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.vertical ? "CPU" : root.summaryText
    color: root.bar ? root.bar.barForeground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    opacity: root.service.collectorHealthy ? 1.0 : 0.65
  }

  Process {
    id: activityProcess
    command: ["omarchy-launch-or-focus-tui", "btop"]
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton && !activityProcess.running) {
        activityProcess.running = true
      }
    }

    onEntered: {
      if (root.bar) {
        var status = root.service.collectorHealthy ? "" : " · telemetry unavailable"
        root.bar.showTooltip(root, root.summaryText + " · Open Activity (btop)" + status)
      }
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
