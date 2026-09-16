import QtQuick

// The four bullet-journal statuses, drawn rather than set in a font.
//
// A box every state shares plus one mark inside it, so the column reads as
// one family at a glance. Drawn because Nerd Font glyph coverage varies by
// version and a missing box would be a tofu in the middle of the list —
// and because a painted mark takes the palette colour like everything else.
Canvas {
  id: root

  property string status: " "   // " " open · "x" done · ">" migrated · "-" dropped
  property color stroke: "#ffffff"
  property int size: 14

  implicitWidth: size
  implicitHeight: size
  width: size
  height: size

  onStatusChanged: requestPaint()
  onStrokeChanged: requestPaint()
  onSizeChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var s = width / 16
    ctx.strokeStyle = root.stroke
    ctx.lineWidth = 1.4 * s
    ctx.lineCap = "square"
    ctx.lineJoin = "miter"

    ctx.beginPath()
    ctx.rect(2.5 * s, 2.5 * s, 11 * s, 11 * s)
    ctx.stroke()

    ctx.beginPath()
    if (root.status === "x") {
      ctx.moveTo(5.2 * s, 8.2 * s); ctx.lineTo(7.2 * s, 10.2 * s); ctx.lineTo(10.8 * s, 6.3 * s)
    } else if (root.status === ">") {
      ctx.moveTo(6.6 * s, 5.4 * s); ctx.lineTo(9.4 * s, 8 * s); ctx.lineTo(6.6 * s, 10.6 * s)
    } else if (root.status === "-") {
      ctx.moveTo(4.8 * s, 11.2 * s); ctx.lineTo(11.2 * s, 4.8 * s)
    } else {
      return
    }
    ctx.stroke()
  }
}
