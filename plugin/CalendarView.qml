import QtQuick
import qs.Commons
import qs.Ui

// A month at a glance, shown in place of the list.
//
// The dot is the reason this exists rather than a date picker: a past day
// still carrying open todos is drawn in `urgent`, so a month reads as a map
// of what is owed. Everything it draws comes from one `bujo days` call — a
// process per cell is not a calendar, it is thirty processes.
Column {
  id: root

  property date month: new Date()
  property int cursorDay: 1
  property date today: new Date()
  property var days: []           // [{day, todos, open, done, notes}]

  signal dayPicked(int day)

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.38)
  readonly property color labelColor: Qt.darker(Color.popups.text, 1.4)

  readonly property int daysInMonth: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()

  // Monday-first, which is what the week is here.
  readonly property int leadingBlanks: {
    var first = new Date(month.getFullYear(), month.getMonth(), 1).getDay()
    return (first + 6) % 7
  }

  readonly property var cells: {
    var out = []
    for (var i = 0; i < leadingBlanks; i++) out.push(0)
    for (var d = 1; d <= daysInMonth; d++) out.push(d)
    while (out.length % 7 !== 0) out.push(0)
    return out
  }

  function iso(day) {
    return Qt.formatDate(new Date(root.month.getFullYear(), root.month.getMonth(), day), "yyyy-MM-dd")
  }

  function entry(day) {
    var want = iso(day)
    for (var i = 0; i < root.days.length; i++) {
      if (root.days[i].day === want) return root.days[i]
    }
    return null
  }

  function isToday(day) {
    return root.month.getFullYear() === root.today.getFullYear()
      && root.month.getMonth() === root.today.getMonth()
      && day === root.today.getDate()
  }

  function isPast(day) {
    var d = new Date(root.month.getFullYear(), root.month.getMonth(), day)
    var t = new Date(root.today)
    d.setHours(0, 0, 0, 0)
    t.setHours(0, 0, 0, 0)
    return d < t
  }

  readonly property var cursorEntry: entry(cursorDay)

  spacing: Style.space(8)

  Grid {
    width: parent.width
    columns: 7
    spacing: Style.space(2)

    Repeater {
      model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

      Text {
        required property var modelData
        width: Math.floor((root.width - Style.space(2) * 6) / 7)
        horizontalAlignment: Text.AlignHCenter
        text: modelData
        color: root.labelColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Repeater {
      model: root.cells

      Item {
        id: cell
        required property var modelData

        readonly property int day: modelData
        readonly property var info: cell.day > 0 ? root.entry(cell.day) : null
        readonly property bool hasCursor: cell.day === root.cursorDay
        readonly property bool isToday: cell.day > 0 && root.isToday(cell.day)
        readonly property int openCount: cell.info ? cell.info.open : 0

        width: Math.floor((root.width - Style.space(2) * 6) / 7)
        height: Style.space(30)

        Rectangle {
          anchors.fill: parent
          visible: cell.hasCursor
          color: Util.alpha(root.fg, 0.08)
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(2)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: cell.day > 0
            text: cell.day
            color: cell.hasCursor || cell.isToday
              ? Color.accent
              : (cell.info ? root.fg : root.dim)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: cell.isToday
          }

          // The one thing that should bother you: a day gone by that is still
          // owed. Today's open work is accent, not urgent — it is not late yet.
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Style.space(3)
            height: width
            radius: width / 2
            visible: cell.openCount > 0
            color: root.isPast(cell.day) ? Color.urgent : Color.accent
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: cell.day > 0
          onClicked: root.dayPicked(cell.day)
        }
      }
    }
  }

  PanelSeparator { width: parent.width }

  // What the cursor is standing on, so a month can be read without leaving it.
  Row {
    width: parent.width
    spacing: Style.space(9)

    Text {
      id: cursorLabel
      text: Qt.formatDate(new Date(root.month.getFullYear(), root.month.getMonth(), root.cursorDay), "ddd d MMM")
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.baseline: cursorLabel.baseline
      text: {
        if (!root.cursorEntry) return "no note"
        var e = root.cursorEntry
        var bits = []
        if (e.todos > 0) bits.push(e.open > 0 ? e.todos + " todo, " + e.open + " open" : e.todos + " todo, none open")
        if (e.notes > 0) bits.push(e.notes + " noted")
        return bits.length > 0 ? bits.join(" · ") : "empty"
      }
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
