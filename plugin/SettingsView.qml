import QtQuick
// Qualified: QtQuick.Controls has a TextField of its own, and the one this
// panel wants is the kit's. Only the multi-line editor comes from here.
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// Where the daily notes live, and what a new one is made from.
//
// A view and nothing else. It renders the values `bujo config get` handed
// over and the verdicts `bujo config check` reached, and emits the change it
// wants; Panel.qml runs the commands. No TOML is parsed or written here —
// what counts as a usable vault, path pattern or template is decided once, in
// the CLI, so there is never a second opinion between the two.
Column {
  id: root

  property var config: ({})
  property var checks: ({})

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(Color.popups.text, 0.38)
  readonly property color labelColor: Qt.darker(Color.popups.text, 1.4)

  // Panel.qml sets PanelKeyCatcher.blocked from this. Without it the catcher
  // sees keys first and typing a path fires the list's single-letter verbs.
  readonly property bool editing: vaultField.editing || pathField.editing
    || sectionField.editing || logField.editing || templateFileField.editing
    || templateArea.activeFocus

  // The whole page as `key=value` pairs. Checking all six together is what
  // makes the template/template_file precedence judgeable — which one wins is
  // a fact about the pair, not about either field.
  readonly property var draft: [
    "vault=" + vaultField.text,
    "path=" + pathField.text,
    "section=" + sectionField.text,
    "log_section=" + logField.text,
    "template_file=" + templateFileField.text,
    "template=" + templateArea.text
  ]

  signal edited()
  signal committed(string key, string value)
  signal doneEditing()
  signal pickRequested(string key)

  spacing: Style.space(9)

  function stored(key) {
    return root.config && root.config[key] !== undefined ? String(root.config[key]) : ""
  }

  function verdict(key) {
    return root.checks && root.checks.fields ? root.checks.fields[key] : null
  }

  // A saved value arriving is the only thing that moves a field under the
  // user; every other direction is field -> CLI.
  function reset() {
    vaultField.text = stored("vault")
    pathField.text = stored("path")
    sectionField.text = stored("section")
    logField.text = stored("log_section")
    templateFileField.text = stored("template_file")
    templateArea.text = stored("template")
  }

  function focusFirst() {
    vaultField.focusInput()
  }

  onConfigChanged: reset()

  component FieldLabel: Text {
    color: root.labelColor
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  // The line under a field: the CLI's note when it has one, dim when it is
  // feedback and urgent when it is a refusal.
  component Verdict: Text {
    // Not named `field`: that would shadow the enclosing Field's id in the
    // very binding that has to reach it.
    property var result: null

    width: parent ? parent.width : 0
    wrapMode: Text.Wrap
    visible: text !== ""
    text: result ? String(result.note || "") : ""
    color: result && result.ok === false ? Color.urgent : root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  component Field: Column {
    id: field

    property string key: ""
    property string label: ""
    property string hint: ""
    property string preview: ""
    property string pick: ""          // setting name, "" for no browse button
    property alias text: input.text
    readonly property bool editing: input.activeFocus
    readonly property var check: root.verdict(field.key)

    function focusInput() { input.forceActiveFocus() }

    width: parent ? parent.width : 0
    spacing: Style.space(3)

    FieldLabel { text: field.label }

    Item {
      width: parent.width
      height: Math.max(input.implicitHeight, browse.visible ? browse.height : 0)

      TextField {
        id: input
        anchors.left: parent.left
        anchors.right: browse.visible ? browse.left : parent.right
        anchors.rightMargin: browse.visible ? Style.space(6) : 0
        anchors.verticalCenter: parent.verticalCenter
        foreground: root.fg
        placeholderText: field.hint
        font.pixelSize: Style.font.bodySmall

        onTextChanged: root.edited()
        // Leaving the field is the save. Nothing is written when the value came
        // back unchanged, so tabbing through the page rewrites nothing.
        onEditingFinished: if (text !== root.stored(field.key)) root.committed(field.key, text)
        Keys.onEscapePressed: {
          input.text = root.stored(field.key)
          root.doneEditing()
        }
      }

      // Beside the field, not on it: clicking a text field has to keep meaning
      // "put the caret here".
      PanelActionButton {
        id: browse
        visible: field.pick !== ""
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰝰"
        tooltipText: "Browse"
        foreground: root.fg
        fontFamily: Style.font.family
        onClicked: root.pickRequested(field.pick)
      }
    }

    // Always on, not just when wrong: seeing today's note resolve is how you
    // tell a pattern that works from one that merely parses.
    Text {
      width: parent.width
      visible: field.preview !== ""
      text: field.preview
      elide: Text.ElideMiddle
      color: root.dim
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Verdict { result: field.check }
  }

  Field {
    id: vaultField
    key: "vault"
    label: "VAULT"
    hint: "~/Documents/Obsidian"
    pick: "vault"
  }

  Field {
    id: pathField
    key: "path"
    label: "DAILY NOTE"
    hint: "Journal/{{date:YYYY-MM-DD}}.md"
    preview: check && check.preview ? "today → " + check.preview : ""
  }

  Field {
    id: sectionField
    key: "section"
    label: "TODO SECTION"
    hint: "## Todo"
  }

  Field {
    id: logField
    key: "log_section"
    label: "LOG SECTION"
    hint: "## Log"
  }

  Field {
    id: templateFileField
    key: "template_file"
    label: "TEMPLATE FILE"
    hint: "Templates/Daily.md — optional, vault-relative"
    pick: "template_file"
  }

  // The inline template. Dimmed rather than hidden when a template file is
  // set: two fields that silently shadow each other is the failure mode, and
  // hiding this one would only move the surprise to the file being removed.
  Column {
    id: templateBlock

    readonly property bool shadowed: root.checks && root.checks.source === "file"
    readonly property var check: root.verdict("template")

    width: parent.width
    spacing: Style.space(3)
    opacity: shadowed ? 0.45 : 1

    FieldLabel { text: "TEMPLATE" }

    Item {
      width: parent.width
      height: Style.space(104)

      BorderSurface {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Style.controlFill(templateArea.activeFocus, templateArea.activeFocus, root.fg, Color.accent)
        borderSpec: Border.controlSpec(templateArea.activeFocus ? "focus" : "normal", root.fg, Color.accent)
      }

      // Scrolls rather than grows: a daily-note template runs to thirty lines
      // in plenty of vaults, and a panel that tall loses its own bottom off
      // the screen.
      Flickable {
        id: templateFlick
        anchors.fill: parent
        anchors.margins: Style.spacing.controlPaddingY
        clip: true
        contentWidth: width
        contentHeight: templateArea.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Controls.TextArea {
          id: templateArea
          width: templateFlick.width
          background: null
          padding: 0
          wrapMode: TextEdit.Wrap
          color: root.fg
          selectionColor: Style.selectionFillFor(root.fg, Color.accent)
          selectedTextColor: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall

          onTextChanged: root.edited()
          // No editingFinished on a TextArea — Enter is a newline here, so
          // leaving the field is the only save.
          onActiveFocusChanged: {
            if (!activeFocus && text !== root.stored("template")) root.committed("template", text)
          }
          Keys.onEscapePressed: {
            templateArea.text = root.stored("template")
            root.doneEditing()
          }

          // Keep the caret in view; the Flickable has no idea where it is.
          onCursorRectangleChanged: {
            var top = cursorRectangle.y
            var bottom = top + cursorRectangle.height
            if (top < templateFlick.contentY)
              templateFlick.contentY = top
            else if (bottom > templateFlick.contentY + templateFlick.height)
              templateFlick.contentY = bottom - templateFlick.height
          }
        }
      }
    }

    Verdict { result: templateBlock.check }
  }
}
