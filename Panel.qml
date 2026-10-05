import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.mrdulasolutions.solar-clock"
  ipcTarget: "io.github.mrdulasolutions.solar-clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var solar: hostWidget && hostWidget.solar ? hostWidget.solar : ({
    label: "—", tooltip: "", detail: "", phase: "unknown",
    sunrise: null, sunset: null, midday: null, midnight: null, wallClock: null, polar: null, daytime: false
  })
  readonly property string locationName: hostWidget && hostWidget.locationName ? hostWidget.locationName : ""
  readonly property var locationLatitude: hostWidget ? hostWidget.latitude : null
  readonly property var locationLongitude: hostWidget ? hostWidget.longitude : null
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(contentForeground, 1.4)

  readonly property var arc: Model.arcState(solar)
  readonly property string activeEvent: Model.activeEvent(solar && solar.phase ? solar.phase : "")
  readonly property var beatRows: [
    { key: "sunrise", name: "Sunrise", value: rowTime(solar.sunrise) },
    { key: "midday", name: "Midday", value: rowTime(solar.midday) },
    { key: "sunset", name: "Sunset", value: rowTime(solar.sunset) },
    { key: "midnight", name: "Midnight", value: rowTime(solar.midnight) }
  ]

  readonly property string locationLabel: {
    if (root.locationName) return root.locationName
    var lat = Number(root.locationLatitude)
    var lon = Number(root.locationLongitude)
    if (!isNaN(lat) && !isNaN(lon)) return lat.toFixed(2) + ", " + lon.toFixed(2)
    return "Location unknown"
  }

  function open() {
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    // Hide even if the hover flag cannot be cleared. A throw here used to
    // leave the panel's click catcher mapped over the desktop.
    try {
      setCenterHoverRevealSuppressed(false)
    } catch (e) {}
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // PluginBarApi marks centerHoverRevealSuppressed read-only. QML then treats
  // setCenterHoverRevealSuppressed() as a write of that property, so the
  // method never runs. The host stores the real callback under
  // _setCenterHoverRevealSuppressed. Older shells still have a writable property.
  function setCenterHoverRevealSuppressed(value) {
    var bar = root.bar
    if (!bar) return
    var setter = bar._setCenterHoverRevealSuppressed
    if (typeof setter === "function") {
      setter(!!value)
      return
    }
    if ("centerHoverRevealSuppressed" in bar)
      bar.centerHoverRevealSuppressed = !!value
  }

  function refresh() {
    if (root.hostWidget && typeof root.hostWidget.refresh === "function")
      root.hostWidget.refresh()
  }

  function rowTime(date) {
    return Model.formatClock(date)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.refresh()

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        PanelHero {
          title: root.solar.label
          meta: root.solar.tooltip
          detail: Qt.formatDateTime(root.solar.wallClock || new Date(), "HH:mm")
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
          iconComponent: Component {
            Text {
              text: root.solar.daytime ? "☀" : "☾"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          width: parent.width
          text: root.solar.detail
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        DayArc {
          width: parent.width
          visible: root.arc.ready
          dayProgress: root.arc.day
          nightProgress: root.arc.night
          daytime: root.arc.daytime
          ready: root.arc.ready
          ink: root.contentForeground
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: root.arc.ready

          Repeater {
            model: [
              { name: "Daylight", value: root.arc.daylight },
              { name: "Night", value: root.arc.nightLength }
            ]

            BorderSurface {
              required property var modelData
              width: (parent.width - Style.space(8)) / 2
              implicitHeight: labelColumn.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)
              borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)

              Column {
                id: labelColumn
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.name.toUpperCase()
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData.value
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.contentForeground }

        PanelSectionHeader {
          text: "TODAY"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        Grid {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(8)
          rowSpacing: Style.space(8)

          Repeater {
            model: root.beatRows

            BorderSurface {
              required property var modelData
              readonly property bool on: modelData.key === root.activeEvent
              width: (parent.width - Style.space(8)) / 2
              implicitHeight: beatColumn.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, on ? 0.12 : 0.04)
              borderSpec: Border.controlSpec(on ? "selected" : "normal", root.contentForeground, Color.accent)

              Column {
                id: beatColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: modelData.name.toUpperCase()
                  color: root.dim
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Text {
                  width: parent.width
                  text: modelData.value
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: on
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: {
            var place = root.locationLabel
            var source = root.solar && root.solar.source ? root.solar.source : ""
            if (source) return place + " · " + source
            return place
          }
          color: root.dim
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
