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
  // One plain list on a past day: every verb still acts on the cursor row, so
  // the cursor model does not change shape just because the date did.
  readonly property var actionable: dayMode ? dayTodos : todayRows.concat(lateRows)
  readonly property int openToday: todayRows.filter(function (r) { return r.status === " " }).length

  property int cursor: 0
  readonly property var current: cursor >= 0 && cursor < actionable.length ? actionable[cursor] : null

  property date today: new Date()

  property bool settingsOpen: false

  // ---- which day the panel is pointed at. 0 is today and keeps the
  //      TODAY/DANGLING split; anything earlier is one plain day, because
  //      "dangling" is a relationship to today that a past day has not got.
  //      Clamped at 0: this navigates history, not the future.
  property int dayOffset: 0
  property bool calendarOpen: false

  readonly property bool dayMode: dayOffset < 0
  readonly property date viewDay: {
    var d = new Date(root.today)
    d.setDate(d.getDate() + root.dayOffset)
    return d
  }

  function iso(d) { return Qt.formatDate(d, "yyyy-MM-dd") }

  function stepDay(delta) {
    var next = Math.min(0, root.dayOffset + delta)
    if (next === root.dayOffset) return
    root.dayOffset = next
    root.cursor = 0
    root.reloadView()
  }

  function goToday() {
    root.dayOffset = 0
    root.cursor = 0
    root.reloadView()
  }

  // A live rescan can shorten the list under the cursor between keystrokes.
  onActionableChanged: if (cursor >= actionable.length) cursor = Math.max(0, actionable.length - 1)
  onOpenedChanged: if (opened) {
    today = new Date()
    cursor = 0
    dayOffset = 0
    calendarOpen = false
    if (hostWidget) hostWidget.refresh()
    reloadView()
  }

  function toggleSettings() {
    settingsOpen = !settingsOpen
    if (settingsOpen) loadConfig()
    else keyCatcher.forceActiveFocus()
  }

  // ---- the day's own data. The bar widget owns today's rows because the
  //      counts must be right whether or not anyone opened the panel; a past
  //      day is nobody's business but this panel's, so it loads its own.

  property var dayTodos: []
  property var dayNotes: []
  property var monthDays: []

  readonly property var todayRowsWithLog: rows   // named for the reader's sake

  function reloadView() {
    if (!opened || settingsOpen) return
    if (calendarOpen) { loadMonth(); return }
    if (!dayLoad.running && dayMode) {
      dayLoad.command = [root.exe, "list", "--day", iso(viewDay), "--json"]
      dayLoad.running = true
    }
    if (!logLoad.running) {
      logLoad.command = [root.exe, "log", "--day", iso(viewDay), "--json"]
      logLoad.running = true
    }
  }

  Process {
    id: dayLoad
    running: false
    command: []
    stdout: StdioCollector {
      id: dayOut
      waitForEnd: true
      onStreamFinished: root.dayTodos = root.parseList(dayOut.text)
    }
  }

  Process {
    id: logLoad
    running: false
    command: []
    stdout: StdioCollector {
      id: logOut
      waitForEnd: true
      onStreamFinished: root.dayNotes = root.parseList(logOut.text)
    }
  }

  // ---- the calendar. A month of counts in one call, because the grid cannot
  //      afford a process per cell.

  property date calMonth: new Date()
  property int calCursor: 1          // day of month under the cursor

  function loadMonth() {
    if (monthLoad.running) return
    monthLoad.command = [root.exe, "days", Qt.formatDate(root.calMonth, "yyyy-MM"), "--json"]
    monthLoad.running = true
  }

  function toggleCalendar() {
    calendarOpen = !calendarOpen
    if (!calendarOpen) { keyCatcher.forceActiveFocus(); reloadView(); return }
    calMonth = new Date(root.viewDay)
    calCursor = root.viewDay.getDate()
    monthDays = []
    loadMonth()
  }

  function stepMonth(delta) {
    var d = new Date(root.calMonth)
    d.setDate(1)
    d.setMonth(d.getMonth() + delta)
    root.calMonth = d
    root.calCursor = Math.min(root.calCursor, new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate())
    root.monthDays = []
    loadMonth()
  }

  function moveCalCursor(days) {
    var d = new Date(root.calMonth.getFullYear(), root.calMonth.getMonth(), root.calCursor)
    d.setDate(d.getDate() + days)
    // Walking off the edge of the month turns the page rather than stopping.
    if (d.getMonth() !== root.calMonth.getMonth() || d.getFullYear() !== root.calMonth.getFullYear()) {
      var m = new Date(d)
      m.setDate(1)
      root.calMonth = m
      root.monthDays = []
      loadMonth()
    }
    root.calCursor = d.getDate()
  }

  // Enter on a cell leaves the calendar pointed at that day.
  function openCalendarDay() {
    var picked = new Date(root.calMonth.getFullYear(), root.calMonth.getMonth(), root.calCursor)
    var start = new Date(root.today)
    start.setHours(0, 0, 0, 0)
    picked.setHours(0, 0, 0, 0)
    root.dayOffset = Math.min(0, Math.round((picked - start) / 86400000))
    root.cursor = 0
    root.calendarOpen = false
    keyCatcher.forceActiveFocus()
    root.reloadView()
  }

  Process {
    id: monthLoad
    running: false
    command: []
    stdout: StdioCollector {
      id: monthOut
      waitForEnd: true
      onStreamFinished: root.monthDays = root.parseList(monthOut.text)
    }
  }

  function parseList(text) {
    try {
      var parsed = JSON.parse(String(text || "[]"))
      return parsed instanceof Array ? parsed : []
    } catch (e) {
      return []
    }
  }

  // A box ticked in Obsidian should show up here too, so the day view keeps
  // the same one-second heartbeat the bar uses while the panel is open.
  Timer {
    interval: 1000
    running: root.opened && !root.settingsOpen && !root.calendarOpen
    repeat: true
    onTriggered: root.reloadView()
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
    if (root.dayMode) return ""
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

      // Two axes, and the kit already delivers both: dy walks the list, dx
      // walks the days. dx was being thrown away until now.
      onMoveRequested: function (dx, dy) {
        if (root.settingsOpen) return
        if (root.calendarOpen) {
          if (dx !== 0) root.moveCalCursor(dx)
          if (dy !== 0) root.moveCalCursor(dy * 7)
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.stepDay(dx)
      }
      // The kit's "activate the row under the cursor", which is Enter and
      // Space. Ticking the box is the only thing activating a todo can mean —
      // in the calendar the only thing it can mean is "open that day".
      onActivateRequested: {
        if (root.settingsOpen) return
        if (root.calendarOpen) root.openCalendarDay()
        else root.act("done")
      }
      // x is the kit's own key — it is matched before onTextKey is reached and
      // arrives here instead. Which suits: `- [x]` is what done looks like in
      // the file, so "delete the row under the cursor" is "tick it".
      onDeleteRequested: if (!root.settingsOpen && !root.calendarOpen) root.act("done")
      // Escape unwinds one level at a time rather than always closing.
      onCloseRequested: {
        if (root.settingsOpen) root.toggleSettings()
        else if (root.calendarOpen) root.toggleCalendar()
        else if (root.dayMode) root.goToday()
        else root.close()
      }
      // Tab is how the bar switches panels, which is the wrong move while a
      // form is up: hand it the first field instead.
      onTabRequested: function (direction) {
        if (root.settingsOpen) settingsView.focusFirst()
        else root.switchPanel(direction)
      }
      onTextKey: function (t) {
        if (t === "s") { root.toggleSettings(); return }
        if (root.settingsOpen) return
        if (t === "c") { root.toggleCalendar(); return }
        if (t === "t") { if (root.calendarOpen) root.toggleCalendar(); root.goToday(); return }
        if (root.calendarOpen) {
          if (t === "[") root.stepMonth(-1)
          else if (t === "]") root.stepMonth(1)
          return
        }
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
            text: {
              if (root.settingsOpen) return "Settings"
              if (root.calendarOpen) return Qt.formatDate(root.calMonth, "MMMM yyyy")
              if (root.dayMode) return Qt.formatDate(root.viewDay, "ddd d MMM")
              return "Todo"
            }
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          // How far back you are, in the words you would use for it.
          Text {
            id: sinceLabel
            anchors.left: title.right
            anchors.leftMargin: Style.space(8)
            anchors.baseline: title.baseline
            visible: root.dayMode && !root.settingsOpen && !root.calendarOpen
            text: root.dayOffset === -1 ? "yesterday" : (-root.dayOffset) + " days ago"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          // The keyboard is the point, but a date you can step with a pointer
          // costs two glyphs. Drawn flanking the title, as the design has it.
          Text {
            id: backChevron
            anchors.right: title.left
            anchors.rightMargin: Style.space(7)
            anchors.baseline: title.baseline
            visible: (root.dayMode || root.calendarOpen) && !root.settingsOpen
            text: "‹"
            color: backMouse.containsMouse ? Color.accent : root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.title

            MouseArea {
              id: backMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.calendarOpen ? root.stepMonth(-1) : root.stepDay(-1)
            }
          }

          Text {
            id: forwardChevron
            // Nothing to see past today on a day view; a month may step on.
            readonly property bool live: root.calendarOpen || root.dayOffset < 0

            anchors.left: root.calendarOpen ? title.right : sinceLabel.right
            anchors.leftMargin: Style.space(7)
            anchors.baseline: title.baseline
            visible: (root.dayMode || root.calendarOpen) && !root.settingsOpen
            text: "›"
            color: !forwardChevron.live
              ? Util.alpha(Color.popups.text, 0.18)
              : (forwardMouse.containsMouse ? Color.accent : root.fg)
            font.family: Style.font.family
            font.pixelSize: Style.font.title

            MouseArea {
              id: forwardMouse
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              hoverEnabled: forwardChevron.live
              enabled: forwardChevron.live
              cursorShape: Qt.PointingHandCursor
              onClicked: root.calendarOpen ? root.stepMonth(1) : root.stepDay(1)
            }
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
            visible: !root.settingsOpen && !root.calendarOpen && !root.dayMode
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
          visible: root.todayRows.length > 0 && !root.settingsOpen && !root.calendarOpen && !root.dayMode

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
          visible: root.todayRows.length > 0 && !root.settingsOpen && !root.calendarOpen && !root.dayMode

          Repeater {
            model: root.todayRows
            delegate: taskRow
          }
        }

        // ---- dangling

        Item {
          width: parent.width
          height: lateHeader.implicitHeight
          visible: root.lateRows.length > 0 && !root.settingsOpen && !root.calendarOpen && !root.dayMode

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
          visible: root.lateRows.length > 0 && !root.settingsOpen && !root.calendarOpen && !root.dayMode

          Repeater {
            model: root.lateRows
            delegate: taskRow
          }
        }

        // ---- a past day: one list, no TODAY/DANGLING split.

        Item {
          width: parent.width
          height: dayHeader.implicitHeight
          visible: root.dayMode && root.dayTodos.length > 0 && !root.settingsOpen && !root.calendarOpen

          PanelSectionHeader { id: dayHeader; text: "TODO" }

          Text {
            anchors.right: parent.right
            anchors.baseline: dayHeader.baseline
            text: root.dayTodos.length
            color: root.sectionColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          width: parent.width
          visible: root.dayMode && root.dayTodos.length > 0 && !root.settingsOpen && !root.calendarOpen

          Repeater {
            model: root.dayTodos
            delegate: taskRow
          }
        }

        // ---- the log. Record, not decision: no status mark, no cursor, and
        //      the mark column left empty is what says so.

        Item {
          width: parent.width
          height: logHeader.implicitHeight
          visible: root.dayNotes.length > 0 && !root.settingsOpen && !root.calendarOpen

          PanelSectionHeader { id: logHeader; text: "LOG" }

          Text {
            anchors.right: parent.right
            anchors.baseline: logHeader.baseline
            text: root.dayNotes.length
            color: root.sectionColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Column {
          width: parent.width
          visible: root.dayNotes.length > 0 && !root.settingsOpen && !root.calendarOpen

          Repeater {
            model: root.dayNotes

            Item {
              required property var modelData

              width: parent ? parent.width : 0
              height: noteText.implicitHeight + Style.space(8)

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(9)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.round(Style.font.body * 1.15)
                  horizontalAlignment: Text.AlignHCenter
                  text: "·"
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  id: noteText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - parent.spacing - Math.round(Style.font.body * 1.15)
                  elide: Text.ElideRight
                  text: modelData.text
                  color: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }
        }

        // ---- the calendar, in place of the list.

        CalendarView {
          id: calendarView
          width: parent.width
          visible: root.calendarOpen

          month: root.calMonth
          cursorDay: root.calCursor
          today: root.today
          days: root.monthDays

          onDayPicked: function (day) {
            root.calCursor = day
            root.openCalendarDay()
          }
        }

        // ---- the reward state. No illustration, no congratulation: the
        //      absence of a DANGLING section is the whole message.

        Text {
          width: parent.width
          visible: root.actionable.length === 0 && root.dayNotes.length === 0
            && !root.settingsOpen && !root.calendarOpen
          text: root.dayMode ? "Nothing on this day." : "Nothing dangling."
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
            model: root.calendarOpen
              ? [
                  { key: "h/j/k/l", what: "move" },
                  { key: "[ ]", what: "month" },
                  { key: "⏎", what: "open" },
                  { key: "t", what: "today" },
                  { key: "esc", what: "back" }
                ]
              : (root.dayMode
                ? [
                    { key: "h/l", what: "day" },
                    { key: "c", what: "calendar" },
                    { key: "esc", what: "today" },
                    { key: "j/k", what: "move" },
                    { key: "x/⏎", what: "done" },
                    { key: "d", what: "drop" },
                    { key: "m", what: "migrate" }
                  ]
                : [
                    { key: "j/k", what: "move" },
                    { key: "h", what: "yesterday" },
                    { key: "c", what: "calendar" },
                    { key: "m", what: "migrate" },
                    { key: "x/⏎", what: "done" },
                    { key: "d", what: "drop" },
                    { key: "a", what: "add" },
                    { key: "n", what: "note" },
                    { key: "s", what: "settings" }
                  ])

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
      readonly property int globalIndex: root.dayMode
        ? index
        : (isToday ? index : root.todayRows.length + index)
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
