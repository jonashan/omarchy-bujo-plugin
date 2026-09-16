import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Counts in the bar, and the host for the todo panel.
//
// This widget owns the data: the panel is a view over `rows`, so the counts
// stay honest whether or not anyone has opened it. Reading is a rescan
// rather than a file watch — an inotify watch on a file breaks the moment
// that file is replaced by rename(), which is exactly what bujo's atomic
// writes do.
BarWidget {
  id: root
  moduleName: "jsc.bujo"

  readonly property string exe: setting("command", "bujo")
  readonly property int refreshSeconds: Math.max(5, setting("refreshSeconds", 30))

  property var rows: []

  readonly property var openToday: rows.filter(function (r) { return r.age === 0 && r.status === " " })
  readonly property var late: rows.filter(function (r) { return r.age > 0 })
  readonly property bool hasDebt: late.length > 0

  // ---- data

  function refresh() {
    if (!listProcess.running) listProcess.running = true
  }

  function ingest(text) {
    try {
      var parsed = JSON.parse(String(text || "[]"))
      root.rows = parsed instanceof Array ? parsed : []
    } catch (e) {
      root.rows = []
    }
  }

  Process {
    id: listProcess
    running: false
    command: [root.exe, "list", "--json"]
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
      onStreamFinished: root.ingest(listOut.text)
    }
  }

  // One timer, two cadences: a slow heartbeat while closed, a live one while
  // the panel is up so a box ticked in Obsidian shows here within the second.
  Timer {
    interval: root.opened ? 1000 : root.refreshSeconds * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // ---- panel plumbing. Bar.findPanelWidget requires open/close/opened here.

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  readonly property real openPanelIndicatorWidth: button.width
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    target: "jsc.bujo"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7
    verticalPadding: 8.75

    // The button measures itself from its label, and ours is empty — without
    // this the slot reports a width the counts don't fit in and they paint
    // over the neighbouring widget.
    fixedWidth: root.vertical
      ? -1
      : Math.round(counts.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical
      ? Math.round(counts.implicitHeight + button.scaledVerticalPadding * 2)
      : -1

    onPressed: function (b) {
      if (b === Qt.RightButton) Util.execArgv([root.exe, "add-interactive"])
      else root.togglePanel()
    }

    Grid {
      id: counts
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 5
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter
      spacing: Style.space(root.vertical ? 2 : 5)

      StatusMark {
        status: "x"
        size: Math.round(button.fontSize * 1.05)
        stroke: button.foreground
      }

      Text {
        text: root.openToday.length
        color: root.openToday.length > 0 ? button.foreground : Util.alpha(button.foreground, 0.45)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      // A separator only makes sense along a row.
      Text {
        visible: root.hasDebt && !root.vertical
        text: "·"
        color: Util.alpha(button.foreground, 0.4)
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }

      // The one colour bujo introduces, and only when there is something to
      // decide about. A clear day never shows red.
      Text {
        visible: root.hasDebt
        text: root.late.length
        color: Color.urgent
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
      }
    }
  }
}
