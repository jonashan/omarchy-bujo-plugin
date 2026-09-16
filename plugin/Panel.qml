import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Today, then everything still dangling — and a decision for each.
//
// The panel renders one section of a daily note and nothing else; the whole
// note stays Obsidian's job. BarWidget.qml owns the data and the refresh —
// and `bujo` pings the shell over IPC after every write, so a capture from
// the palette lands here without waiting for a poll.
Panel {
  id: root
  moduleName: "io.github.jonashan.bujo"
  ipcTarget: "io.github.jonashan.bujo"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string exe: hostWidget ? hostWidget.exe : "bujo"
  readonly property var rows: hostWidget ? hostWidget.rows : []

  readonly property var todayRows: rows.filter(function (r) { return r.age === 0 })
  readonly property var lateRows: rows.filter(function (r) { return r.age > 0 })
  readonly property var actionable: todayRows.concat(lateRows)
  readonly property int openToday: todayRows.filter(function (r) { return r.status === " " }).length

  property int cursor: 0
  readonly property var current: cursor >= 0 && cursor < actionable.length ? actionable[cursor] : null

  property date today: new Date()

  property bool settingsOpen: false

  // A live rescan can shorten the list under the cursor between keystrokes.
  onActionableChanged: if (cursor >= actionable.length) cursor = Math.max(0, actionable.length - 1)
  onOpenedChanged: if (opened) { today = new Date(); cursor = 0; if (hostWidget) hostWidget.refresh() }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (settingsOpen) loadConfig()
    else keyCatcher.forceActiveFocus()
  }

  // ---- settings. Three commands, no file: `bujo config get` fills the page,
  //      `bujo config check` judges the draft on it, `bujo config set` is the
  //      only way anything is written. QML never opens config.toml, so the
  //      rules about vaults, path patterns and Templater have exactly one
  //      home and it is the CLI.

  property var cfg: ({})
  property var cfgChecks: ({})

  function parseJson(text) {
    try {
      return JSON.parse(String(text || "{}"))
    } catch (e) {
      return {}
    }
  }

  function loadConfig() {
    if (!cfgGet.running) cfgGet.running = true
  }

  function runCheck() {
    if (cfgCheck.running) { checkDebounce.restart(); return }
    cfgCheck.command = [root.exe, "config", "check", "--json"].concat(settingsView.draft)
    cfgCheck.running = true
  }

  Process {
    id: cfgGet
    running: false
    command: [root.exe, "config", "get", "--json"]
    stdout: StdioCollector {
      id: cfgGetOut
      waitForEnd: true
      onStreamFinished: root.cfg = root.parseJson(cfgGetOut.text)
    }
  }

  Process {
    id: cfgCheck
    running: false
    command: []
    stdout: StdioCollector {
      id: cfgCheckOut
      waitForEnd: true
      onStreamFinished: root.cfgChecks = root.parseJson(cfgCheckOut.text)
    }
  }

  // A keystroke is not a reason to fork a process; a pause in typing is.
  Timer {
    id: checkDebounce
    interval: 200
    onTriggered: root.runCheck()
  }

  // Saves are queued rather than fired in parallel: `config set` is a read,
  // one change, and a whole-file write, so two in flight would lose one.
  property var pendingSets: []

  function saveSetting(key, value) {
    pendingSets = pendingSets.concat([[key, value]])
    pumpSets()
  }

  function pumpSets() {
    if (cfgSet.running || pendingSets.length === 0) return
    var next = pendingSets[0]
    pendingSets = pendingSets.slice(1)
    cfgSet.command = [root.exe, "config", "set", next[0], next[1]]
    cfgSet.running = true
  }

  // The desktop chooser is another window, so the layer-shell panel loses
  // focus and closes the moment it appears. Reopening afterwards is why this
  // runs as a Process rather than going out through Util.execArgv like the
  // capture verbs: settingsOpen survives the close, so the page comes back
  // exactly where it was, with the picked value in it.
  function pickSetting(key) {
    if (cfgPick.running) return
    cfgPick.command = [root.exe, "config", "pick", key]
    cfgPick.running = true
  }

  Process {
    id: cfgPick
    running: false
    command: []
    onExited: {
      root.loadConfig()
      root.open()
    }
  }

  Process {
    id: cfgSet
    running: false
    command: []
    onExited: {
      if (root.pendingSets.length > 0) {
        root.pumpSets()
      } else {
        root.loadConfig()
        if (root.hostWidget) root.hostWidget.refresh()
      }
    }
  }

  // ---- colours, all palette roles

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.38)
  readonly property color sectionColor: Qt.darker(Color.popups.text, 1.4)
  readonly property color selBackground: Util.alpha(Color.popups.text, 0.08)
  readonly property color sepColor: Util.alpha(Color.popups.text, 0.12)

  function moveCursor(delta) {
    if (actionable.length === 0) return
    cursor = Math.max(0, Math.min(actionable.length - 1, cursor + delta))
  }

  // ---- actions. Every one of them is `bujo <verb> <ref>`; the ref carries a
  //      content hash, so a task Obsidian moved under us is refused rather
  //      than acted on at the wrong line.

  Process {
    id: action
    running: false
    command: []
    onExited: if (root.hostWidget) root.hostWidget.refresh()
  }

  function act(verb) {
    if (!current || action.running) return
    action.command = [root.exe, verb, current.ref]
    action.running = true
  }

  // Interactive verbs summon their own Quickshell prompt, so this panel gets
  // out of the way first rather than fighting it for keyboard focus.
  //
  // execArgv, not bar.run: run() hands the string to `bash -lc`, and a ref
  // carries the note path — "05. Journals/…" splits at the space and the verb
  // gets two arguments it cannot use.
  function actInteractive(verb) {
    var refless = verb === "add-interactive" || verb === "note-interactive"
    if (!refless && !current) return
    var argv = refless ? [root.exe, verb] : [root.exe, verb, current.ref]
    root.close()
    Util.execArgv(argv)
  }

  function label(row) {
    return row.clean && row.clean.length > 0 ? row.clean : row.text
  }

  function ageLabel(row) {
    if (row.status === ">") {
      var m = /→ \[\[([0-9-]+)\]\]/.exec(row.text)
      return m ? "→ " + Qt.formatDate(Date.fromLocaleDateString(Qt.locale(), m[1], "yyyy-MM-dd"), "d MMM") : ""
    }
    return row.age > 0 ? row.age + "d" : ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.settingsOpen ? 420 : 360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      // This catcher sees keys before the focused child does, so a settings
      // field would otherwise never receive a letter — every one of them is
      // already a verb down in the list.
      blocked: root.settingsOpen && settingsView.editing

      onMoveRequested: function (dx, dy) { if (!root.settingsOpen && dy !== 0) root.moveCursor(dy) }
      // The kit's "activate the row under the cursor", which is Enter and
      // Space. Ticking the box is the only thing activating a todo can mean.
      onActivateRequested: if (!root.settingsOpen) root.act("done")
      // x is the kit's own key — it is matched before onTextKey is reached and
      // arrives here instead. Which suits: `- [x]` is what done looks like in
      // the file, so "delete the row under the cursor" is "tick it".
      onDeleteRequested: if (!root.settingsOpen) root.act("done")
      onCloseRequested: if (root.settingsOpen) root.toggleSettings(); else root.close()
      // Tab is how the bar switches panels, which is the wrong move while a
      // form is up: hand it the first field instead.
      onTabRequested: function (direction) {
        if (root.settingsOpen) settingsView.focusFirst()
        else root.switchPanel(direction)
      }
      onTextKey: function (t) {
        if (t === "s") { root.toggleSettings(); return }
        if (root.settingsOpen) return
        if (t === "d") root.act("drop")
        else if (t === "m") root.actInteractive("move-interactive")
        else if (t === "a") root.actInteractive("add-interactive")
        else if (t === "n") root.actInteractive("note-interactive")
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(8)

        // ---- header

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, settingsButton.height)

          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: root.settingsOpen ? "Settings" : "Todo"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "󰅖" : "󰒓"
            tooltipText: root.settingsOpen ? "Back to the list" : "Settings"
            foreground: root.fg
            fontFamily: Style.font.family
            onClicked: root.toggleSettings()
          }

          Text {
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            anchors.baseline: title.baseline
            visible: !root.settingsOpen
            text: Qt.formatDate(root.today, "ddd d MMM")
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { width: parent.width }

        // ---- settings, shown in place of the list rather than over it, so
        //      there is never a question about which one the keys belong to.

        SettingsView {
          id: settingsView
          width: parent.width
          visible: root.settingsOpen

          config: root.cfg
          checks: root.cfgChecks

          onEdited: checkDebounce.restart()
          onCommitted: function (key, value) { root.saveSetting(key, value) }
          onPickRequested: function (key) { root.pickSetting(key) }
          onDoneEditing: keyCatcher.forceActiveFocus()
        }

        // ---- today

        Item {
          width: parent.width
          height: todayHeader.implicitHeight
          visible: root.todayRows.length > 0 && !root.settingsOpen

          PanelSectionHeader { id: todayHeader; text: "TODAY" }

          Text {
            anchors.right: parent.right
            anchors.baseline: todayHeader.baseline
            text: root.openToday
            color: root.sectionColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          width: parent.width
          visible: root.todayRows.length > 0 && !root.settingsOpen

          Repeater {
            model: root.todayRows
            delegate: taskRow
          }
        }

        // ---- dangling

        Item {
          width: parent.width
          height: lateHeader.implicitHeight
          visible: root.lateRows.length > 0 && !root.settingsOpen

          PanelSectionHeader { id: lateHeader; text: "DANGLING" }

          Text {
            anchors.right: parent.right
            anchors.baseline: lateHeader.baseline
            text: root.lateRows.length
            color: root.sectionColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          width: parent.width
          visible: root.lateRows.length > 0 && !root.settingsOpen

          Repeater {
            model: root.lateRows
            delegate: taskRow
          }
        }

        // ---- the reward state. No illustration, no congratulation: the
        //      absence of a DANGLING section is the whole message.

        Text {
          width: parent.width
          visible: root.actionable.length === 0 && !root.settingsOpen
          text: "Nothing dangling."
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        PanelSeparator { width: parent.width }

        // There is no Save button, so the legend has to say when a change
        // lands. It lands when you leave the field.
        Text {
          width: parent.width
          visible: root.settingsOpen
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: "<font color='" + root.sectionColor + "'>esc</font> back · "
            + "saved when you leave a field"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        // Flow, not Row: seven verbs already reach the right edge at the
        // default font, and a Row would clip the last one rather than wrap.
        Flow {
          width: parent.width
          spacing: Style.space(11)
          visible: !root.settingsOpen

          Repeater {
            model: [
              { key: "j/k", what: "move" },
              { key: "m", what: "migrate" },
              { key: "x/⏎", what: "done" },
              { key: "d", what: "drop" },
              { key: "a", what: "add" },
              { key: "n", what: "note" },
              { key: "s", what: "settings" }
            ]

            Text {
              required property var modelData
              textFormat: Text.StyledText
              text: "<font color='" + root.sectionColor + "'>" + modelData.key + "</font> " + modelData.what
              color: root.dim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  // ---- one row, four states

  Component {
    id: taskRow

    Item {
      id: rowItem
      required property var modelData
      required property int index

      readonly property bool isToday: modelData.age === 0
      readonly property int globalIndex: isToday ? index : root.todayRows.length + index
      readonly property bool hasCursor: root.opened && globalIndex === root.cursor
      readonly property bool dropped: modelData.status === "-"
      readonly property bool receded: modelData.status !== " "

      width: parent ? parent.width : 0
      height: rowContent.implicitHeight + Style.space(8)

      Rectangle {
        anchors.fill: parent
        color: rowItem.hasCursor ? root.selBackground : "transparent"
      }

      Row {
        id: rowContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(9)

        StatusMark {
          anchors.verticalCenter: parent.verticalCenter
          status: rowItem.modelData.status
          size: Math.round(Style.font.body * 1.15)
          stroke: rowItem.hasCursor
            ? Color.accent
            : (rowItem.modelData.status === ">" ? Color.accent : root.dim)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - parent.spacing * 2 - Style.space(20) - ageText.width
          elide: Text.ElideRight
          text: root.label(rowItem.modelData)
          color: rowItem.hasCursor ? Color.accent : (rowItem.receded ? root.dim : root.fg)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          // Struck through as well as dimmed: dropped is the one state worth
          // reading as dead without parsing the mark.
          font.strikeout: rowItem.dropped
        }

        Text {
          id: ageText
          anchors.verticalCenter: parent.verticalCenter
          text: root.ageLabel(rowItem.modelData)
          color: rowItem.hasCursor
            ? Color.accent
            : (rowItem.modelData.overdue ? Color.urgent : root.dim)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.cursor = rowItem.globalIndex
      }
    }
  }
}
