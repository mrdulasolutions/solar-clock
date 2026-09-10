import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.mrdulasolutions.solar-clock"

  property date displayDate: new Date()
  property var weatherLocation: ({ name: "", latitude: null, longitude: null })
  property var latitude: null
  property var longitude: null
  property string locationName: ""
  property string sunSource: ""
  property var sunDays: []
  property var solar: ({
    label: "—",
    tooltip: "Waiting for location",
    detail: "",
    phase: "unknown",
    sunrise: null,
    sunset: null,
    midday: null,
    midnight: null,
    wallClock: null,
    polar: null,
    daytime: false,
    source: ""
  })

  readonly property bool hasLocation: latitude !== null && longitude !== null && !isNaN(Number(latitude)) && !isNaN(Number(longitude))
  readonly property string displayText: solar && solar.label ? solar.label : "—"
  readonly property var verticalLines: Model.verticalLines(displayText)

  function applyLocation(loc, sourceName) {
    if (!loc) return
    var lat = loc.latitude !== null && loc.latitude !== undefined ? loc.latitude : null
    var lon = loc.longitude !== null && loc.longitude !== undefined ? loc.longitude : null
    var name = loc.name ? String(loc.name) : ""
    var changed = root.latitude !== lat || root.longitude !== lon
    if (root.latitude !== lat) root.latitude = lat
    if (root.longitude !== lon) root.longitude = lon
    if (name && root.locationName !== name) root.locationName = name
    if (sourceName) root.sunSource = sourceName
    if (changed && Model.hasCoordinates({ latitude: lat, longitude: lon })) root.fetchSunTimes()
    else root.recompute()
  }

  function recompute() {
    root.solar = Model.solarState(root.displayDate, root.sunDays, root.sunSource)
  }

  function pluginFile(name) {
    var text = String(Qt.resolvedUrl(name))
    if (text.indexOf("file://") === 0)
      return decodeURIComponent(text.slice(7))
    return text
  }

  function startHttps(proc, url) {
    if (!proc || proc.running) return
    var command = Model.httpsGetCommand(root.pluginFile("fetch-https"), url)
    if (!command.length) return
    proc.command = command
    proc.running = true
  }

  function fetchSunTimes() {
    if (!root.hasLocation) return
    root.startHttps(sunProc, Model.openMeteoSunUrl(root.latitude, root.longitude))
  }

  function fetchWeatherLocation() {
    root.startHttps(wttrProc, Model.wttrLocationUrl(root.weatherLocation))
  }

  function refresh() {
    root.displayDate = new Date()
    locationFile.reload()
    if (Model.hasCoordinates(root.weatherLocation)) root.applyLocation(root.weatherLocation, root.sunSource)
    else root.fetchWeatherLocation()
    root.recompute()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: {
    if (Model.hasCoordinates(root.weatherLocation)) root.applyLocation(root.weatherLocation, "")
    else root.fetchWeatherLocation()
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      var rolledOver = Model.localDateKey(date) !== Model.localDateKey(root.displayDate)
      root.displayDate = date
      if (rolledOver) root.fetchSunTimes()
      else root.recompute()
    }
  }

  FileView {
    id: locationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.weatherLocation = Model.parseLocationFile(text())
      if (Model.hasCoordinates(root.weatherLocation)) root.applyLocation(root.weatherLocation, root.sunSource)
      else root.fetchWeatherLocation()
    }
    onLoadFailed: {
      root.weatherLocation = Model.parseLocationFile("")
      root.fetchWeatherLocation()
    }
  }

  Process {
    id: wttrProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var body = Model.acceptHttpsBody(text)
        if (!body) return
        var loc = Model.parseWttrLocation(body)
        var days = Model.parseWttrSunDays(body)
        if (days.length && (!root.sunDays || !root.sunDays.length || root.sunSource !== "Open-Meteo")) {
          root.sunDays = days
          root.sunSource = "wttr.in"
          root.recompute()
        }
        if (loc) root.applyLocation(loc, root.sunSource)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.log("solar-clock wttr exit " + exitCode)
    }
  }

  Process {
    id: sunProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var body = Model.acceptHttpsBody(text)
        if (!body) return
        var parsed = Model.parseOpenMeteoSunDays(body)
        if (parsed.days && parsed.days.length) {
          root.sunDays = parsed.days
          root.sunSource = "Open-Meteo"
          root.recompute()
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.log("solar-clock open-meteo exit " + exitCode)
        if (!root.hasLocation && !wttrProc.running) root.fetchWeatherLocation()
      }
    }
  }

  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: {
      if (root.hasLocation) root.fetchSunTimes()
      else root.fetchWeatherLocation()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.mrdulasolutions.solar-clock"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    tooltipText: root.solar && root.solar.tooltip ? root.solar.tooltip : ""
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3 ? button.fontSize * 0.9 : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
