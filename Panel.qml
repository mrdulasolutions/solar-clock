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
    setCenterHoverRevealSuppressed(false)
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

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
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

        Column {
          width: parent.width
          spacing: Style.space(8)

          Repeater {
            model: [
              { name: "Sunrise", value: root.rowTime(root.solar.sunrise) },
              { name: "Midday", value: root.rowTime(root.solar.midday) },
              { name: "Sunset", value: root.rowTime(root.solar.sunset) },
              { name: "Midnight", value: root.rowTime(root.solar.midnight) }
            ]

            Row {
              required property var modelData
              width: parent.width
              spacing: Style.space(10)

              Text {
                width: Style.space(90)
                text: modelData.name.toUpperCase()
                color: root.dim
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }

              Text {
                text: modelData.value
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
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
