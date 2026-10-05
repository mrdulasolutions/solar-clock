import QtQuick
import qs.Commons

// Sun above the horizon, moon below. Progress runs sunrise → sunset across
// the top, then sunset → sunrise across the bottom.
Item {
  id: root

  property real dayProgress: 0
  property real nightProgress: 0
  property bool daytime: false
  property bool ready: false
  property color ink: "#cacccc"

  implicitWidth: Style.space(360)
  implicitHeight: Style.space(196)

  readonly property real labelBand: Style.space(16)
  readonly property real sideGutter: Style.space(52)
  readonly property real radius: Math.max(8, Math.min((width - sideGutter * 2) / 2, (height - labelBand * 2 - Style.space(8)) / 2))
  readonly property real cx: width / 2
  readonly property real hy: labelBand + Style.space(4) + radius

  Canvas {
    id: canvas
    anchors.fill: parent

    function pixelRatio() {
      return Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
    }

    function syncSize() {
      var scale = pixelRatio()
      canvas.canvasSize = Qt.size(Math.max(1, width * scale), Math.max(1, height * scale))
      requestPaint()
    }

    onWidthChanged: syncSize()
    onHeightChanged: syncSize()
    onVisibleChanged: if (visible) syncSize()
    Component.onCompleted: syncSize()
    onDayProgressChanged: requestPaint()
    onNightProgressChanged: requestPaint()
    onDaytimeChanged: requestPaint()
    onReadyChanged: requestPaint()
    onInkChanged: requestPaint()

    property real dayProgress: root.dayProgress
    property real nightProgress: root.nightProgress
    property bool daytime: root.daytime
    property bool ready: root.ready
    property color ink: root.ink

    onPaint: {
      var ctx = getContext("2d")
      var scale = pixelRatio()
      var w = width
      var h = height
      var cx = root.cx
      var hy = root.hy
      var r = root.radius
      var ink = root.ink

      ctx.reset()
      ctx.setTransform(scale, 0, 0, scale, 0, 0)
      ctx.clearRect(0, 0, w, h)
      if (!(r > 0)) return

      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      function inkAlpha(alpha) {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha)
      }

      // Day arc: canvas angle PI is the left horizon, 2PI the right, passing overhead.
      ctx.beginPath()
      ctx.arc(cx, hy, r, Math.PI, Math.PI * 2, false)
      ctx.strokeStyle = inkAlpha(0.22)
      ctx.lineWidth = 2
      ctx.stroke()

      if (root.ready && root.dayProgress > 0) {
        ctx.beginPath()
        ctx.arc(cx, hy, r, Math.PI, Math.PI + Math.PI * root.dayProgress, false)
        ctx.strokeStyle = inkAlpha(root.daytime ? 0.95 : 0.45)
        ctx.lineWidth = 2.5
        ctx.stroke()
      }

      // Night arc: angle 0 is the right horizon, PI the left, passing underfoot.
      ctx.beginPath()
      ctx.arc(cx, hy, r, 0, Math.PI, false)
      ctx.strokeStyle = inkAlpha(0.14)
      ctx.lineWidth = 2
      ctx.stroke()

      if (root.ready && !root.daytime && root.nightProgress > 0) {
        ctx.beginPath()
        ctx.arc(cx, hy, r, 0, Math.PI * root.nightProgress, false)
        ctx.strokeStyle = inkAlpha(0.9)
        ctx.lineWidth = 2.5
        ctx.stroke()
      }

      ctx.beginPath()
      ctx.moveTo(cx - r, hy)
      ctx.lineTo(cx + r, hy)
      ctx.strokeStyle = inkAlpha(0.28)
      ctx.lineWidth = 1
      ctx.stroke()

      function dot(angle, filled) {
        var x = cx + Math.cos(angle) * r
        var y = hy + Math.sin(angle) * r
        ctx.beginPath()
        ctx.arc(x, y, filled ? 3.2 : 2.2, 0, Math.PI * 2, false)
        ctx.fillStyle = inkAlpha(filled ? 0.95 : 0.4)
        ctx.fill()
      }

      dot(Math.PI, false)
      dot(Math.PI * 1.5, false)
      dot(0, false)
      dot(Math.PI * 0.5, false)

      if (root.ready) {
        var marker = root.daytime
          ? Math.PI + Math.PI * root.dayProgress
          : Math.PI * root.nightProgress
        var mx = cx + Math.cos(marker) * r
        var my = hy + Math.sin(marker) * r
        ctx.beginPath()
        ctx.arc(mx, my, 8, 0, Math.PI * 2, false)
        ctx.fillStyle = inkAlpha(0.16)
        ctx.fill()
        ctx.beginPath()
        ctx.arc(mx, my, 4.2, 0, Math.PI * 2, false)
        ctx.fillStyle = inkAlpha(1)
        ctx.fill()
        if (!root.daytime) {
          ctx.beginPath()
          ctx.arc(mx, my, 1.6, 0, Math.PI * 2, false)
          ctx.fillStyle = inkAlpha(0)
          ctx.globalCompositeOperation = "destination-out"
          ctx.fill()
          ctx.globalCompositeOperation = "source-over"
        }
      }
    }
  }

  Text {
    x: root.cx - root.radius
    y: root.hy - root.radius - height - Style.space(2)
    width: root.radius * 2
    horizontalAlignment: Text.AlignHCenter
    text: "MIDDAY"
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }

  Text {
    x: root.cx - root.radius
    y: root.hy + root.radius + Style.space(2)
    width: root.radius * 2
    horizontalAlignment: Text.AlignHCenter
    text: "MIDNIGHT"
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }

  Text {
    x: root.cx - root.radius - width - Style.space(8)
    y: root.hy - height / 2
    text: "RISE"
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }

  Text {
    x: root.cx + root.radius + Style.space(4)
    y: root.hy - height / 2
    text: "SET"
    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.1
  }
}
