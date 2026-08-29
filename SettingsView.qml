import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Column {
  id: root

  property color foreground: "white"
  property string fontFamily: ""

  property var calendars: []
  property var hiddenCalendars: []
  property bool showYearProgress: false
  property bool weekStartsMonday: true
  property bool showWorkingLocation: false
  property bool hideDeclined: false
  property int announceLeadMinutes: 15

  property string syncedAt: ""
  property string sourceLabel: ""
  property int eventCount: 0
  property string syncState: "missing"
  property string setupCommand: ""
  property bool setupCommandCopied: false

  // Yuvomi Backend Properties
  property string yuvomiUrl: "http://"
  property string yuvomiApiKey: ""
  property var yuvomiTestResult: null
  property bool isTestingYuvomi: false

  signal calendarToggled(string calendarId)
  signal yearProgressToggled()
  signal weekStartToggled()
  signal workingLocationToggled()
  signal hideDeclinedToggled()
  signal leadMinutesPicked(int minutes)
  signal setupCommandCopyRequested()
  signal yuvomiConfigSaveRequested(string url, string key)
  signal yuvomiTestRequested(string url, string key)

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.9)

  spacing: Style.space(10)

  component SectionTitle: Text {
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    font.bold: true
  }

  component ToggleRow: Rectangle {
    id: toggle

    property string label: ""
    property string hint: ""
    property bool checked: false
    property color swatch: "transparent"

    signal activated()

    width: parent ? parent.width : 0
    height: toggleBody.height + Style.space(6)
    radius: Style.cornerRadius
    color: hovered.hovered
      ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
      : "transparent"

    HoverHandler { id: hovered }
    TapHandler { onTapped: toggle.activated() }

    Row {
      id: toggleBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(14)
        text: toggle.checked ? "✓" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: toggle.swatch != "transparent"
        width: Style.space(4)
        height: width
        radius: width / 2
        color: toggle.checked ? toggle.swatch : "transparent"
        border.width: Style.spacing.hairline
        border.color: toggle.swatch
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: toggleBody.width - Style.space(26)
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: toggle.label
          color: toggle.checked ? root.foreground : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: toggle.hint !== ""
          text: toggle.hint
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // =========================================================================
  // SECTION 1: YUVOMI BACKEND CONFIGURATION
  // =========================================================================
  SectionTitle { text: qsTr("YUVOMI CALENDAR BACKEND") }

  BorderSurface {
    width: parent.width
    implicitHeight: yuvomiCol.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: Style.hoverFillFor(root.foreground, root.foreground)
    borderSpec: Border.controlSpec("normal", root.faint, Color.accent)

    Column {
      id: yuvomiCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(6)

      // Server URL
      Column {
        width: parent.width
        spacing: 2
        Text {
          text: qsTr("Yuvomi Server URL")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          width: parent.width
          implicitHeight: Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: yuvomiUrlInput.activeFocus ? Border.controlSpec("selected", Color.accent, Color.accent) : Border.controlSpec("normal", root.faint, Color.accent)

          TextInput {
            id: yuvomiUrlInput
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.yuvomiUrl
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            selectByMouse: true
            clip: true
          }
        }
      }

      // API Key
      Column {
        width: parent.width
        spacing: 2
        Text {
          text: qsTr("Yuvomi API Key / Bearer Token")
          color: root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        BorderSurface {
          width: parent.width
          implicitHeight: Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"
          borderSpec: yuvomiKeyInput.activeFocus ? Border.controlSpec("selected", Color.accent, Color.accent) : Border.controlSpec("normal", root.faint, Color.accent)

          TextInput {
            id: yuvomiKeyInput
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: root.yuvomiApiKey
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            echoMode: TextInput.Password
            selectByMouse: true
            clip: true
          }
        }
      }

      // Test & Save Buttons Row
      RowLayout {
        width: parent.width
        spacing: Style.space(6)

        // Test Connection Button
        BorderSurface {
          Layout.fillWidth: true
          implicitHeight: Style.space(30)
          radius: Style.cornerRadius
          color: Style.hoverFillFor(root.foreground, root.foreground)
          borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              text: root.isTestingYuvomi ? "" : "󰑐"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              text: root.isTestingYuvomi ? qsTr("Testing...") : qsTr("Test Connection")
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.isTestingYuvomi
            cursorShape: Qt.PointingHandCursor
            onClicked: root.yuvomiTestRequested(yuvomiUrlInput.text.trim(), yuvomiKeyInput.text.trim())
          }
        }

        // Save & Sync Button
        BorderSurface {
          Layout.fillWidth: true
          implicitHeight: Style.space(30)
          radius: Style.cornerRadius
          color: Color.accent
          borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)

          Text {
            anchors.centerIn: parent
            text: qsTr("Save & Sync Now")
            color: "white"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.yuvomiConfigSaveRequested(yuvomiUrlInput.text.trim(), yuvomiKeyInput.text.trim())
          }
        }
      }

      // Test Result Banner
      BorderSurface {
        visible: root.yuvomiTestResult !== null
        width: parent.width
        implicitHeight: Style.space(26)
        radius: Style.cornerRadius
        color: "transparent"
        borderSpec: Border.controlSpec("normal", root.yuvomiTestResult && root.yuvomiTestResult.ok ? "#87c095" : "#e06c75", Color.accent)

        Text {
          anchors.centerIn: parent
          text: root.yuvomiTestResult && root.yuvomiTestResult.ok
            ? ("✓ Connected · Yuvomi v" + (root.yuvomiTestResult.version || "") + " · " + root.yuvomiTestResult.eventCount + " events")
            : ("✕ Connection Failed: " + (root.yuvomiTestResult ? (root.yuvomiTestResult.error || "Unreachable") : ""))
          color: root.yuvomiTestResult && root.yuvomiTestResult.ok ? "#87c095" : "#e06c75"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }
    }
  }

  // =========================================================================
  // SECTION 2: CALENDARS & DISPLAY SETTINGS
  // =========================================================================
  SectionTitle { text: qsTr("CALENDARS") }

  Text {
    width: parent.width
    visible: root.calendars.length === 0
    text: qsTr("Nothing synced yet, so there is nothing to choose from.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Repeater {
    model: root.calendars

    ToggleRow {
      required property var modelData

      label: modelData.name + (modelData.isBirthday ? " (󰎤 Birthdays)" : "")
      swatch: modelData.color
      checked: root.hiddenCalendars.indexOf(modelData.id) === -1
      onActivated: root.calendarToggled(modelData.id)
    }
  }

  // ---- Display
  SectionTitle { text: qsTr("DISPLAY") }

  ToggleRow {
    label: qsTr("Week starts on Monday")
    hint: qsTr("Off starts the week on Sunday")
    checked: root.weekStartsMonday
    onActivated: root.weekStartToggled()
  }

  ToggleRow {
    label: qsTr("Working location events")
    hint: qsTr("Google's work-from-home markers, hidden by default")
    checked: root.showWorkingLocation
    onActivated: root.workingLocationToggled()
  }

  ToggleRow {
    label: qsTr("Declined invitations")
    hint: qsTr("Shown struck through when on")
    checked: !root.hideDeclined
    onActivated: root.hideDeclinedToggled()
  }

  ToggleRow {
    label: qsTr("Year and life progress")
    hint: qsTr("The upstream clock's bars, off by default")
    checked: root.showYearProgress
    onActivated: root.yearProgressToggled()
  }

  // ---- Bar Label Announcement
  SectionTitle { text: qsTr("BAR LABEL & DESKTOP ALERTS") }

  Text {
    width: parent.width
    text: qsTr("How early the bar gives up the clock to announce what is next.")
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(3)

    Repeater {
      model: [0, 5, 15, 30, 60]

      Rectangle {
        required property var modelData

        readonly property bool active: modelData === root.announceLeadMinutes

        width: leadLabel.width + Style.space(8)
        height: leadLabel.height + Style.space(4)
        radius: height / 2
        color: active
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          : "transparent"
        border.width: Style.spacing.hairline
        border.color: active ? root.muted : Qt.darker(root.foreground, 2.4)

        Text {
          id: leadLabel
          anchors.centerIn: parent
          text: modelData === 0 ? qsTr("Never") : modelData + qsTr("min")
          color: active ? root.foreground : root.faint
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        TapHandler { onTapped: root.leadMinutesPicked(modelData) }
      }
    }
  }

  // ---- Sync Status
  SectionTitle { text: qsTr("SYNC STATUS") }

  Text {
    width: parent.width
    color: root.faint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
    text: {
      if (root.syncState === "missing") return qsTr("No calendar synced yet. Configure Yuvomi above and click Save & Sync.")
      if (root.syncState === "version") return qsTr("The events file was written by a newer version of this plugin.")

      var line = root.eventCount + qsTr(" events synced from ") + root.sourceLabel
      if (root.syncState === "stale") {
        return line + qsTr("\nLast sync looks old. Check: journalctl --user -u omarchy-yuvomi-sync")
      }
      return line + qsTr("\nLast sync: ") + root.syncedAt
    }
  }
}
