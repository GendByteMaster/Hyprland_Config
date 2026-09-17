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
    property real memoryPercent: 0
    property real temperatureC: 0
    property bool hasCpu: false
    property bool hasMemory: false
    property bool hasTemperature: false
    property date lastSampleAt: new Date(0)
    property bool collectorHealthy: false
  }

  readonly property var hostedService: {
    var services = bar && bar.shell ? bar.shell._services : null
    return ServiceHost.hostedService(bar)
  }
  readonly property var service: hostedService !== null ? hostedService : dummyService

  readonly property string cpuText: service.hasCpu ? "CPU " + Math.round(service.cpuPercent) + "%" : "CPU --%"
  readonly property string memoryText: service.hasMemory ? "RAM " + Math.round(service.memoryPercent) + "%" : "RAM --%"
  readonly property string temperatureText: service.hasTemperature ? Math.round(service.temperatureC) + "°C" : ""
  readonly property string summaryText: temperatureText.length > 0
    ? cpuText + " · " + memoryText + " · " + temperatureText
    : cpuText + " · " + memoryText

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
        root.bar.showTooltip(root, "Open Activity (btop)" + status)
      }
    }
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
