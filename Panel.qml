import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "kiryuuki.oma-calvomi"
  ipcTarget: "kiryuuki.oma-calvomi"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today & Time
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale().dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, eventIndex)

  // ---- Events
  property var eventDoc: null
  property var eventIndex: ({})
  property bool eventVersionMismatch: false
  readonly property int syncIntervalSeconds: 300

  readonly property string setupCommand: Model.commandPathFromUrl(
    Qt.resolvedUrl("sync/setup"), Quickshell.env("HOME") || "")
  readonly property string syncState: eventVersionMismatch
    ? "version"
    : Model.syncState(eventDoc, Date.now(), syncIntervalSeconds)

  property string selectedDayKey: todayKey
  readonly property var selectedEvents: Model.eventsForDateKey(eventIndex, selectedDayKey)
  readonly property date selectedDate: Model.dateFromKey(selectedDayKey, today)

  function selectDay(key) {
    root.selectedDayKey = String(key)
    var parts = String(key).split("-")
    if (parts.length === 3) {
      var y = parseInt(parts[0], 10)
      var m = parseInt(parts[1], 10) - 1
      if (!isNaN(y) && !isNaN(m) && (y !== root.viewYear || m !== root.viewMonth)) {
        root.viewYear = y
        root.viewMonth = m
      }
    }
  }

  function moveMonth(delta) {
    var d = new Date(root.viewYear, root.viewMonth + delta, 1)
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
  }

  function moveYear(delta) {
    var d = new Date(root.viewYear + delta, root.viewMonth, 1)
    root.viewYear = d.getFullYear()
    root.viewMonth = d.getMonth()
  }

  function goToToday() {
    root.viewYear = root.today.getFullYear()
    root.viewMonth = root.today.getMonth()
    root.selectedDayKey = root.todayKey
  }

  function refresh() {
    root.today = new Date()
    eventsFile.reload()
    yuvomiConfigFile.reload()
  }

  function applyEvents(rawText) {
    var parsed = Model.parseEvents(rawText)
    root.eventVersionMismatch = parsed.versionMismatch
    root.eventDoc = parsed.doc
    root.rebuildIndex()
  }

  function rebuildIndex() {
    var opts = {
      hiddenCalendars: root.hiddenCalendars,
      showWorkingLocation: root.showWorkingLocation,
      hideDeclined: root.hideDeclined
    }
    root.eventIndex = Model.indexEvents(root.eventDoc, opts)
  }

  property date nowTick: new Date()
  readonly property var todaysEvents: Model.eventsForDateKey(eventIndex, todayKey)
  readonly property var upcomingEvent: Model.nextEventToday(
    todaysEvents, nowTick.getTime(), todayKey)
  readonly property string upcomingCountdown: Model.formatCountdown(
    upcomingEvent ? (Date.parse(upcomingEvent.start) - nowTick.getTime()) : null) || ""

  readonly property bool showYearProgress: setting("showYearProgress", false)
  readonly property bool showWorkingLocation: setting("showWorkingLocation", false)
  readonly property bool hideDeclined: setting("hideDeclined", false)

  property var hiddenCalendars: []
  readonly property var knownCalendars: Model.calendarsInDocument(eventDoc)

  function adoptSettings() {
    var stored = setting("hiddenCalendars", [])
    root.hiddenCalendars = Array.isArray(stored) ? stored.slice() : []
  }

  function toggleCalendar(calendarId) {
    root.hiddenCalendars = Model.toggleHiddenCalendar(root.hiddenCalendars, calendarId)
    persistSettings({ hiddenCalendars: root.hiddenCalendars })
  }

  function toggleYearProgress() {
    persistSettings({ showYearProgress: !root.showYearProgress })
  }

  function setAnnounceLeadMinutes(minutes) {
    persistSettings({ announceLeadMinutes: minutes })
  }

  property bool settingsOpen: false
  property bool addEventOpen: false

  function toggleWorkingLocation() {
    persistSettings({ showWorkingLocation: !root.showWorkingLocation })
  }

  function toggleHideDeclined() {
    persistSettings({ hideDeclined: !root.hideDeclined })
  }

  function openExternally(url) {
    if (!url) return
    Qt.openUrlExternally(url)
    root.close()
  }

  function openMeeting(event) {
    root.openExternally(Model.meetingUrlFor(event))
  }

  function openEvent(event) {
    root.openExternally(Model.eventUrlFor(event))
  }

  onHiddenCalendarsChanged: root.rebuildIndex()
  onShowWorkingLocationChanged: root.rebuildIndex()
  onHideDeclinedChanged: root.rebuildIndex()
  onSettingsChanged: root.adoptSettings()
  Component.onCompleted: root.adoptSettings()

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLife) root.cancelEditingLife()
    root.settingsOpen = false
    root.addEventOpen = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function setCenterHoverRevealSuppressed(suppressed) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = suppressed
  }

  function setting(key, fallback) {
    var stored = root.settings && root.settings[key] !== undefined ? root.settings[key] : undefined
    if (stored !== undefined) return stored
    if (root.hostWidget && root.hostWidget.settings && root.hostWidget.settings[key] !== undefined)
      return root.hostWidget.settings[key]
    return fallback
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  // =========================================================================
  // DATA FILES & PROCESSES
  // =========================================================================
  FileView {
    id: eventsFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/calendar-events.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyEvents(text())
    onLoadFailed: root.applyEvents("")
    onFileChanged: reload()
  }

  property var yuvomiConfig: ({ baseUrl: "", apiKey: "" })

  FileView {
    id: yuvomiConfigFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/yuvomi-sync.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && parsed.baseUrl) {
          root.yuvomiConfig = parsed
          return
        }
      } catch (e) {}
      taskvomiFallbackConfigFile.reload()
    }
    onFileChanged: reload()
  }

  FileView {
    id: taskvomiFallbackConfigFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/taskvomi.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      if (!root.yuvomiConfig || !root.yuvomiConfig.baseUrl) {
        try {
          var tcfg = JSON.parse(text())
          if (tcfg && tcfg.baseUrl) {
            root.yuvomiConfig = {
              baseUrl: tcfg.baseUrl || "",
              apiKey: tcfg.apiKey || ""
            }
          }
        } catch (e) {
          root.yuvomiConfig = { baseUrl: "", apiKey: "" }
        }
      }
    }
  }

  // Process: Test Yuvomi Connection
  property var yuvomiTestResult: null
  property bool isTestingYuvomi: false

  Process {
    id: testYuvomiProcess
    stdout: StdioCollector {
      id: testOut
      waitForEnd: true
      onStreamFinished: {
        root.isTestingYuvomi = false
        var out = testOut.text.trim()
        try {
          root.yuvomiTestResult = JSON.parse(out)
        } catch (e) {
          root.yuvomiTestResult = { ok: false, error: "Failed to parse response: " + (out || "No output") }
        }
      }
    }
    onExited: function(code) {
      root.isTestingYuvomi = false
    }
  }

  function testYuvomi(url, key) {
    root.isTestingYuvomi = true
    root.yuvomiTestResult = null
    testYuvomiProcess.command = [
      "/usr/bin/python3",
      (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py",
      "--test",
      "--base-url", (url || "").trim(),
      "--api-key", (key || "").trim()
    ]
    testYuvomiProcess.running = false
    testYuvomiProcess.running = true
  }

  property bool yuvomiSaveSuccess: false

  Timer {
    id: yuvomiSaveTimer
    interval: 4000
    onTriggered: root.yuvomiSaveSuccess = false
  }

  // Process: Save Yuvomi Config (writes 0600 atomically)
  Process {
    id: saveYuvomiConfigProcess
    onExited: function(code) {
      yuvomiConfigFile.reload()
      syncYuvomiProcess.running = false
      syncYuvomiProcess.running = true
    }
  }

  // Process: Sync Yuvomi Events
  Process {
    id: syncYuvomiProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py"]
    onExited: function(code) {
      eventsFile.reload()
      root.yuvomiSaveSuccess = true
      yuvomiSaveTimer.restart()
    }
  }

  function saveYuvomiConfig(url, key) {
    root.yuvomiTestResult = null
    saveYuvomiConfigProcess.command = [
      "/usr/bin/python3",
      (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py",
      "--save-config",
      "--base-url", (url || "").trim(),
      "--api-key", (key || "").trim()
    ]
    saveYuvomiConfigProcess.running = false
    saveYuvomiConfigProcess.running = true
  }

  // Process: Create Event in Yuvomi
  Process {
    id: createEventProcess
    property var createArgs: []
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py", "--create-event"].concat(createArgs)
    onExited: function(code) {
      eventsFile.reload()
      root.addEventOpen = false
    }
  }

  function dispatchCreateEvent(title, dateStr, startTime, endTime, isAllDay, loc, desc, colorHex, recurrenceRule) {
    var startIso = isAllDay ? dateStr : (dateStr + "T" + startTime + ":00")
    var endIso = isAllDay ? null : (dateStr + "T" + endTime + ":00")
    var args = [
      "--title", title,
      "--start", startIso
    ]
    if (endIso) args.push("--end", endIso)
    if (isAllDay) args.push("--all-day")
    if (loc) args.push("--location", loc)
    if (desc) args.push("--desc", desc)
    if (colorHex) args.push("--color", colorHex)
    if (recurrenceRule) args.push("--recurrence", recurrenceRule)

    createEventProcess.createArgs = args
    createEventProcess.running = true
  }

  // Process: Create Birthday in Yuvomi
  Process {
    id: createBirthdayProcess
    property var createArgs: []
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py", "--create-birthday"].concat(createArgs)
    onExited: function(code) {
      eventsFile.reload()
      root.addEventOpen = false
    }
  }

  function dispatchCreateBirthday(name, birthDate, offset, notes) {
    var args = [
      "--name", name,
      "--birth-date", birthDate
    ]
    if (offset) args.push("--reminder-offset", String(offset))
    if (notes) args.push("--desc", notes)

    createBirthdayProcess.createArgs = args
    createBirthdayProcess.running = true
  }

  // Process: Background Alerts & Desktop Notifications Timer
  Process {
    id: alertCheckProcess
    command: ["/usr/bin/python3", (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/kiryuuki.oma-calvomi/sync/yuvomi_sync.py", "--check-alerts"]
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: alertCheckProcess.running = true
  }

  Process {
    id: setupCommandCopier
    command: ["wl-copy", "--", root.setupCommand]
  }

  property bool setupCommandCopied: false

  function copySetupCommand() {
    setupCommandCopier.running = true
    root.setupCommandCopied = true
    copiedReset.restart()
  }

  Timer {
    id: copiedReset
    interval: 2000
    onTriggered: root.setupCommandCopied = false
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.nowTick = clock.date
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "r" || t === "R") root.refresh()
        else if (t === "n" || t === "N" || t === "+") {
          root.addEventOpen = !root.addEventOpen
          if (root.addEventOpen) root.settingsOpen = false
        }
      }

      Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: calendarColumn
          width: scrollArea.width
          spacing: Style.space(12)

          // ------------------ TOP HERO & ACTION BUTTONS ------------------
          Item {
            width: parent.width
            height: heroRow.height

            // Right-aligned actions row: + New Event, Settings
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                iconText: root.addEventOpen ? "✕" : "+"
                tooltipText: root.addEventOpen ? "Close creator" : "Add Event / Birthday to Yuvomi (+ / n)"
                foreground: root.addEventOpen ? Color.accent : root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.addEventOpen = !root.addEventOpen
                  if (root.addEventOpen) root.settingsOpen = false
                }
              }

              PanelActionButton {
                iconText: root.settingsOpen ? "󰅖" : "󰒓"
                tooltipText: root.settingsOpen ? "Back to calendar" : "Settings & Yuvomi Sync"
                foreground: root.settingsOpen ? Color.accent : root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.settingsOpen = !root.settingsOpen
                  if (root.settingsOpen) root.addEventOpen = false
                }
              }
            }

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                textFormat: Text.PlainText
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 48
              }

              Text {
                textFormat: Text.PlainText
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ------------------ YEAR / LIFE PROGRESS (MEMENTO MORI) ------------------
          Item {
            visible: !root.settingsOpen && !root.addEventOpen
            width: parent.width
            implicitHeight: yearBlock.implicitHeight + Style.space(12)

            Column {
              id: yearBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              // 1. INLINE MEMENTO MORI EDITOR (Activated by Double-Clicking Year Progress)
              RowLayout {
                visible: root.editingLife
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  text: qsTr("Memento Mori · Birth Year:")
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                BorderSurface {
                  implicitWidth: Style.space(60)
                  implicitHeight: Style.space(26)
                  radius: Style.cornerRadius
                  color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
                  borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)

                  TextInput {
                    id: bornField
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: TextInput.AlignHCenter
                    selectByMouse: true
                    inputMask: "0000"
                    Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: qsTr("Expectancy:")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                BorderSurface {
                  implicitWidth: Style.space(45)
                  implicitHeight: Style.space(26)
                  radius: Style.cornerRadius
                  color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
                  borderSpec: Border.controlSpec("focus", Color.accent, Color.accent)

                  TextInput {
                    id: expectancyField
                    anchors.fill: parent
                    anchors.margins: Style.space(4)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: TextInput.AlignHCenter
                    selectByMouse: true
                    inputMask: "000"
                    Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                  }
                }

                Item { Layout.fillWidth: true }

                // Save
                BorderSurface {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  radius: Style.cornerRadius
                  color: Color.accent
                  borderSpec: Border.controlSpec("normal", Color.accent, Color.accent)
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "✓"
                    color: "white"
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commitLife()
                  }
                }

                // Clear
                BorderSurface {
                  visible: root.birthYear > 0
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", "#e06c75", Color.accent)
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "󰆴"
                    color: "#e06c75"
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { root.clearLife(); root.cancelEditingLife() }
                  }
                }

                // Cancel
                BorderSurface {
                  implicitWidth: Style.space(26)
                  implicitHeight: Style.space(26)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)
                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "✕"
                    color: root.contentForeground
                    font.pixelSize: Style.font.caption
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelEditingLife()
                  }
                }
              }

              // 2. DEFAULT VIEW: UPCOMING EVENT OR YEAR + LIFE PROGRESS
              Row {
                visible: !root.showYearProgress && !root.editingLife
                width: parent.width
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(4)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.upcomingEvent !== null
                  width: Style.space(4)
                  height: width
                  radius: width / 2
                  color: root.upcomingEvent ? root.upcomingEvent.color : "transparent"
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(70)
                  text: root.upcomingEvent
                    ? (root.upcomingEvent.isBirthday ? ("󰎤 " + root.upcomingEvent.title) : root.upcomingEvent.title)
                    : qsTr("Nothing else today")
                  color: root.upcomingEvent
                    ? root.contentForeground
                    : Qt.darker(root.contentForeground, 1.9)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.upcomingCountdown
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              // Year Progress Bar
              Item {
                visible: root.showYearProgress && !root.editingLife
                width: parent.width
                implicitHeight: Math.max(yearLabel.implicitHeight, Style.space(10))

                TapHandler {
                  enabled: root.showYearProgress && !root.editingLife
                  onDoubleTapped: root.startEditingLife()
                }

                Text {
                  textFormat: Text.PlainText
                  id: yearLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.today.getFullYear()
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  textFormat: Text.PlainText
                  id: yearPercent
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.yearDonePercent + "%"
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Rectangle {
                  id: yearTrack
                  anchors.left: yearLabel.right
                  anchors.right: yearPercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    width: Math.round(parent.width * root.yearDone)
                    height: parent.height
                    radius: parent.radius
                    color: Style.selectedStateColor(root.contentForeground, Color.accent)
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                  }
                }
              }

              // Memento Mori: Life Progress Bar (Shown when birthYear is configured)
              Item {
                visible: root.showYearProgress && !root.editingLife && root.birthYear > 0
                width: parent.width
                implicitHeight: Math.max(lifeLabel.implicitHeight, Style.space(10))

                TapHandler {
                  onDoubleTapped: root.startEditingLife()
                }

                Text {
                  textFormat: Text.PlainText
                  id: lifeLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Age " + root.age
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                Text {
                  textFormat: Text.PlainText
                  id: lifePercent
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.lifeDonePercent + "%"
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }

                Rectangle {
                  id: lifeTrack
                  anchors.left: lifeLabel.right
                  anchors.right: lifePercent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: Style.space(6)
                  radius: Style.cornerRadius > 0 ? height / 2 : 0
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                  Rectangle {
                    width: Math.round(parent.width * root.lifeDone)
                    height: parent.height
                    radius: parent.radius
                    color: Color.accent
                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                  }
                }
              }
            }
          }

          // =========================================================================
          // VIEW 1: QUICK ADD EVENT & BIRTHDAY FORM (YUVOMI)
          // =========================================================================
          BorderSurface {
            id: newEventForm
            visible: root.addEventOpen
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            implicitHeight: formCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.hoverFillFor(root.contentForeground, root.contentForeground)
            borderSpec: Border.controlSpec("focus", newEventForm.formMode === "birthday" ? "#E11D48" : Color.accent, Color.accent)

            property string formMode: "event" // "event" | "birthday"
            property string pickedColor: "#3B82F6"
            property string pickedRecurrence: ""
            property string bdayOffset: "1440"

            Column {
              id: formCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(6)

              // Mode Switcher: Calendar Event vs. Birthday / Anniversary
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: newEventForm.formMode === "event" ? Color.accent : "transparent"
                  border.width: 1
                  border.color: newEventForm.formMode === "event" ? Color.accent : Qt.darker(root.contentForeground, 2.0)

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text { text: "📅"; font.pixelSize: Style.font.caption }
                    Text {
                      textFormat: Text.PlainText
                      text: qsTr("Calendar Event")
                      color: newEventForm.formMode === "event" ? "white" : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: newEventForm.formMode === "event"
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: newEventForm.formMode = "event"
                  }
                }

                Rectangle {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(28)
                  radius: Style.cornerRadius
                  color: newEventForm.formMode === "birthday" ? "#E11D48" : "transparent"
                  border.width: 1
                  border.color: newEventForm.formMode === "birthday" ? "#E11D48" : Qt.darker(root.contentForeground, 2.0)

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(4)
                    Text { text: "🎂"; font.pixelSize: Style.font.caption }
                    Text {
                      textFormat: Text.PlainText
                      text: qsTr("Birthday / Anniversary")
                      color: newEventForm.formMode === "birthday" ? "white" : root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: newEventForm.formMode === "birthday"
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: newEventForm.formMode = "birthday"
                  }
                }
              }

              // ---------------- EVENT MODE FIELDS ----------------
              Column {
                visible: newEventForm.formMode === "event"
                width: parent.width
                spacing: Style.space(6)

                // Title
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Title"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: newTitleInput.activeFocus ? Border.controlSpec("selected", Color.accent, Color.accent) : Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    TextInput {
                      id: newTitleInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: ""
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }

                // Date & Time Row
                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  // Date
                  Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: qsTr("Date (YYYY-MM-DD)"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                    BorderSurface {
                      width: parent.width
                      implicitHeight: Style.space(30)
                      radius: Style.cornerRadius
                      color: "transparent"
                      borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                      TextInput {
                        id: newDateInput
                        anchors.fill: parent
                        anchors.margins: Style.space(6)
                        text: root.selectedDayKey || root.todayKey
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        selectByMouse: true
                        clip: true
                      }
                    }
                  }

                  // Start Time
                  Column {
                    visible: !newAllDayCheck.checked
                    width: Style.space(70)
                    spacing: 2
                    Text { text: qsTr("Start"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                    BorderSurface {
                      width: parent.width
                      implicitHeight: Style.space(30)
                      radius: Style.cornerRadius
                      color: "transparent"
                      borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                      TextInput {
                        id: newStartInput
                        anchors.fill: parent
                        anchors.margins: Style.space(6)
                        text: "10:00"
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        selectByMouse: true
                        clip: true
                      }
                    }
                  }

                  // End Time
                  Column {
                    visible: !newAllDayCheck.checked
                    width: Style.space(70)
                    spacing: 2
                    Text { text: qsTr("End"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                    BorderSurface {
                      width: parent.width
                      implicitHeight: Style.space(30)
                      radius: Style.cornerRadius
                      color: "transparent"
                      borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                      TextInput {
                        id: newEndInput
                        anchors.fill: parent
                        anchors.margins: Style.space(6)
                        text: "11:00"
                        color: root.contentForeground
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        selectByMouse: true
                        clip: true
                      }
                    }
                  }
                }

                // All day & Color Row
                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Row {
                    spacing: Style.space(4)
                    BorderSurface {
                      id: newAllDayCheck
                      property bool checked: false
                      implicitWidth: Style.space(18)
                      implicitHeight: Style.space(18)
                      radius: Style.space(3)
                      color: checked ? Color.accent : "transparent"
                      borderSpec: Border.controlSpec("normal", checked ? Color.accent : Qt.darker(root.contentForeground, 1.8), Color.accent)

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: "✓"
                        color: "white"
                        visible: parent.checked
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: newAllDayCheck.checked = !newAllDayCheck.checked
                      }
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: qsTr("All Day Event")
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Item { Layout.fillWidth: true }

                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: ["#3B82F6", "#E11D48", "#10B981", "#8B5CF6", "#F59E0B"]
                      delegate: Rectangle {
                        width: Style.space(14)
                        height: width
                        radius: width / 2
                        color: modelData
                        border.width: newEventForm.pickedColor === modelData ? 2 : 0
                        border.color: "white"
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: newEventForm.pickedColor = modelData
                        }
                      }
                    }
                  }
                }

                // Recurrence / Repeat Selector
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Repeat / Recurrence"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }

                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: [
                        { label: "None", rule: "" },
                        { label: "Daily", rule: "FREQ=DAILY" },
                        { label: "Weekly", rule: "FREQ=WEEKLY;INTERVAL=1" },
                        { label: "Monthly", rule: "FREQ=MONTHLY;INTERVAL=1" },
                        { label: "Yearly", rule: "FREQ=YEARLY;INTERVAL=1" },
                        { label: "Mon-Fri", rule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" }
                      ]
                      delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: newEventForm.pickedRecurrence === modelData.rule
                        width: rLabel.implicitWidth + Style.space(10)
                        height: Style.space(24)
                        radius: height / 2
                        color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : "transparent"
                        border.width: 1
                        border.color: active ? Color.accent : Qt.darker(root.contentForeground, 2.2)

                        Text {
                          textFormat: Text.PlainText
                          id: rLabel
                          anchors.centerIn: parent
                          text: parent.modelData.label
                          color: parent.active ? Color.accent : Qt.darker(root.contentForeground, 1.6)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: parent.active
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: newEventForm.pickedRecurrence = parent.modelData.rule
                        }
                      }
                    }
                  }
                }

                // Location / Link
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Location / Video Meeting Link (Google Meet / Zoom)"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    TextInput {
                      id: newLocInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: ""
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }

                // Description
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Description / Notes (optional)"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                    TextInput {
                      id: newDescInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: ""
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }
              }

              // ---------------- BIRTHDAY MODE FIELDS ----------------
              Column {
                visible: newEventForm.formMode === "birthday"
                width: parent.width
                spacing: Style.space(6)

                // Person Name
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Person / Celebration Name"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: bdayNameInput.activeFocus ? Border.controlSpec("selected", "#E11D48", "#E11D48") : Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), "#E11D48")

                    TextInput {
                      id: bdayNameInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: ""
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }

                // Birth Date
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Birth Date / Event Date (YYYY-MM-DD)"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), "#E11D48")

                    TextInput {
                      id: bdayDateInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: root.selectedDayKey || root.todayKey
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }

                // Reminder Offset Selector
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Reminder Notification"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }

                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: [
                        { label: "On the day", offset: "0" },
                        { label: "1 day before", offset: "1440" },
                        { label: "3 days before", offset: "4320" },
                        { label: "1 week before", offset: "10080" }
                      ]
                      delegate: Rectangle {
                        required property var modelData
                        readonly property bool active: newEventForm.bdayOffset === modelData.offset
                        width: bLabel.implicitWidth + Style.space(10)
                        height: Style.space(24)
                        radius: height / 2
                        color: active ? Qt.rgba(0.88, 0.11, 0.28, 0.2) : "transparent"
                        border.width: 1
                        border.color: active ? "#E11D48" : Qt.darker(root.contentForeground, 2.2)

                        Text {
                          textFormat: Text.PlainText
                          id: bLabel
                          anchors.centerIn: parent
                          text: parent.modelData.label
                          color: parent.active ? "#E11D48" : Qt.darker(root.contentForeground, 1.6)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.caption
                          font.bold: parent.active
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: newEventForm.bdayOffset = parent.modelData.offset
                        }
                      }
                    }
                  }
                }

                // Notes / Gift Ideas
                Column {
                  width: parent.width
                  spacing: 2
                  Text { text: qsTr("Notes / Gift Ideas (optional)"); color: Qt.darker(root.contentForeground, 1.8); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption }
                  BorderSurface {
                    width: parent.width
                    implicitHeight: Style.space(30)
                    radius: Style.cornerRadius
                    color: "transparent"
                    borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), "#E11D48")

                    TextInput {
                      id: bdayNotesInput
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      text: ""
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      selectByMouse: true
                      clip: true
                    }
                  }
                }
              }

              // Action Buttons
              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                BorderSurface {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(30)
                  radius: Style.cornerRadius
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", Qt.darker(root.contentForeground, 2.0), Color.accent)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: qsTr("Cancel")
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addEventOpen = false
                  }
                }

                BorderSurface {
                  Layout.fillWidth: true
                  implicitHeight: Style.space(30)
                  radius: Style.cornerRadius
                  color: newEventForm.formMode === "birthday" ? "#E11D48" : Color.accent
                  borderSpec: Border.controlSpec("normal", newEventForm.formMode === "birthday" ? "#E11D48" : Color.accent, Color.accent)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: newEventForm.formMode === "birthday" ? qsTr("Save Birthday to Yuvomi") : qsTr("Save Event to Yuvomi")
                    color: "white"
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (newEventForm.formMode === "birthday") {
                        var bName = bdayNameInput.text.trim()
                        if (!bName) return
                        root.dispatchCreateBirthday(
                          bName,
                          bdayDateInput.text.trim() || root.todayKey,
                          newEventForm.bdayOffset,
                          bdayNotesInput.text.trim()
                        )
                      } else {
                        var t = newTitleInput.text.trim()
                        if (!t) return
                        root.dispatchCreateEvent(
                          t,
                          newDateInput.text.trim() || root.todayKey,
                          newStartInput.text.trim(),
                          newEndInput.text.trim(),
                          newAllDayCheck.checked,
                          newLocInput.text.trim(),
                          newDescInput.text.trim(),
                          newEventForm.pickedColor,
                          newEventForm.pickedRecurrence
                        )
                      }
                    }
                  }
                }
              }
            }
          }

          // =========================================================================
          // VIEW 2: MONTH GRID & AGENDA
          // =========================================================================
          Item {
            visible: !root.settingsOpen && !root.addEventOpen
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  id: weekRow
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: Model.pad2(weekRow.modelData.week)
                    color: Qt.darker(root.contentForeground, 2.3)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: weekRow.modelData.days

                    Rectangle {
                      id: cell
                      required property var modelData

                      readonly property bool currentMonth: Boolean(modelData && modelData.currentMonth)
                      readonly property bool isToday: Boolean(modelData && modelData.isToday)
                      readonly property bool isSelected: Boolean(modelData && root.selectedDayKey === modelData.key)
                      readonly property var dots: (modelData && modelData.dots) ? modelData.dots : []

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius

                      color: isSelected
                        ? (isToday ? Style.selectedStateColor(root.contentForeground, Color.accent) : Style.hoverFillFor(root.contentForeground, Color.accent))
                        : (cellHover.hovered ? Style.hoverFillFor(root.contentForeground, Color.accent) : "transparent")

                      border.width: isToday && !isSelected ? 1 : 0
                      border.color: isToday ? Color.accent : "transparent"

                      HoverHandler { id: cellHover }
                      TapHandler { onTapped: root.selectDay(cell.modelData.key) }

                      Column {
                        anchors.centerIn: parent
                        spacing: Style.space(2)

                        Text {
                          textFormat: Text.PlainText
                          anchors.horizontalCenter: parent.horizontalCenter
                          text: cell.modelData.day
                          color: cell.isSelected && cell.isToday
                            ? Color.background
                            : (cell.currentMonth ? root.contentForeground : Qt.darker(root.contentForeground, 2.4))
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: cell.isToday || cell.isSelected
                        }

                        // Event Color Dots
                        Row {
                          anchors.horizontalCenter: parent.horizontalCenter
                          spacing: Style.space(2)
                          visible: cell.dots.length > 0

                          Repeater {
                            model: cell.dots.slice(0, 4)
                            Rectangle {
                              required property var modelData
                              width: Style.space(3)
                              height: width
                              radius: width / 2
                              color: modelData
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // Month Stepping
          Item {
            visible: !root.settingsOpen && !root.addEventOpen
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                textFormat: Text.PlainText
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ------------------ SELECTED DAY AGENDA ------------------
          Column {
            visible: !root.settingsOpen && !root.addEventOpen
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Qt.formatDate(root.selectedDate, "dddd d MMMM").toUpperCase()
              color: Qt.darker(root.contentForeground, 1.4)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Repeater {
              model: root.selectedEvents

              Rectangle {
                id: eventRow
                required property var modelData

                readonly property string meetingUrl: Model.meetingUrlFor(modelData)
                readonly property bool declined: Model.isDeclined(modelData)
                readonly property bool joinable: Model.isJoinableNow(modelData, root.nowTick.getTime(), root.todayKey)
                readonly property string eventUrl: Model.eventUrlFor(modelData)
                readonly property bool openable: eventUrl !== ""
                readonly property bool isBday: Boolean(modelData.isBirthday || modelData.calendarId === "yuvomi:birthdays" || (modelData.title && modelData.title.indexOf("Birthday:") === 0))

                width: gridColumn.width
                height: eventBody.height + Style.space(4)
                radius: Style.cornerRadius
                color: eventHover.hovered
                  ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
                  : "transparent"

                HoverHandler {
                  id: eventHover
                  enabled: eventRow.openable || eventRow.joinable
                  cursorShape: Qt.PointingHandCursor
                }

                Rectangle {
                  id: joinButton
                  visible: eventRow.joinable
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: joinLabel.implicitWidth + Style.space(8)
                  height: joinLabel.implicitHeight + Style.space(3)
                  radius: height / 2
                  color: joinHover.hovered
                    ? Style.selectedStateColor(root.contentForeground, Color.accent)
                    : "transparent"
                  border.width: Style.spacing.hairline
                  border.color: joinHover.hovered ? "transparent" : Qt.darker(root.contentForeground, 2.0)

                  HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.openMeeting(eventRow.modelData)
                  }

                  Text {
                    textFormat: Text.PlainText
                    id: joinLabel
                    anchors.centerIn: parent
                    text: qsTr("Join")
                    color: joinHover.hovered ? Color.background : Qt.darker(root.contentForeground, 1.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: eventBody
                  anchors.left: parent.left
                  anchors.right: eventRow.joinable ? joinButton.left : parent.right
                  anchors.rightMargin: eventRow.joinable ? Style.space(3) : 0
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  TapHandler {
                    enabled: eventRow.openable
                    onTapped: root.openEvent(eventRow.modelData)
                  }

                  Rectangle {
                    width: Style.space(2)
                    height: eventLines.height
                    radius: width / 2
                    color: eventRow.isBday ? "#E11D48" : (eventRow.declined ? Qt.darker(eventRow.modelData.color, 2.2) : eventRow.modelData.color)
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: Style.space(44)
                    text: eventRow.isBday ? "󰎤" : (eventRow.modelData.allDay ? qsTr("All day") : Qt.formatDateTime(new Date(eventRow.modelData.start), "HH:mm"))
                    color: eventRow.isBday ? "#E11D48" : Qt.darker(root.contentForeground, eventRow.declined ? 2.2 : 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: eventRow.isBday
                  }

                  Column {
                    id: eventLines
                    width: eventBody.width - Style.space(54)
                    spacing: Style.space(1)

                    Row {
                      width: parent.width
                      spacing: Style.space(4)

                      Text {
                        width: parent.width - (recurrenceBadge.visible ? Style.space(18) : 0)
                        text: eventRow.modelData.title
                        textFormat: Text.PlainText
                        color: eventRow.declined
                          ? Qt.darker(root.contentForeground, 2.0)
                          : (eventRow.isBday ? "#E11D48" : root.contentForeground)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: eventRow.isBday
                        elide: Text.ElideRight
                      }

                      Text {
                        id: recurrenceBadge
                        visible: Boolean(eventRow.modelData.recurrence)
                        text: "󰑖"
                        textFormat: Text.PlainText
                        color: Qt.darker(root.contentForeground, 2.0)
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      visible: text !== ""
                      textFormat: Text.PlainText
                      text: {
                        if (eventRow.declined) return qsTr("Declined")
                        if (eventRow.modelData.description) return eventRow.modelData.description
                        if (eventRow.modelData.location) return eventRow.modelData.location
                        return ""
                      }
                      color: Qt.darker(root.contentForeground, 1.9)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.selectedEvents.length === 0
              width: parent.width
              color: Qt.darker(root.contentForeground, 1.9)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              text: qsTr("Nothing scheduled")
            }
          }

          // =========================================================================
          // VIEW 3: SETTINGS VIEW (YUVOMI CONFIG & FILTERS)
          // =========================================================================
          SettingsView {
            visible: root.settingsOpen
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter

            foreground: root.contentForeground
            fontFamily: root.contentFontFamily

            yuvomiUrl: root.yuvomiConfig ? (root.yuvomiConfig.baseUrl || "http://") : "http://"
            yuvomiApiKey: root.yuvomiConfig ? (root.yuvomiConfig.apiKey || "") : ""
            yuvomiTestResult: root.yuvomiTestResult
            isTestingYuvomi: root.isTestingYuvomi
            saveSuccess: root.yuvomiSaveSuccess
            onYuvomiTestRequested: function(url, key) { root.testYuvomi(url, key) }
            onYuvomiConfigSaveRequested: function(url, key) { root.saveYuvomiConfig(url, key) }

            calendars: root.knownCalendars
            hiddenCalendars: root.hiddenCalendars
            showYearProgress: root.showYearProgress
            showWorkingLocation: root.showWorkingLocation
            hideDeclined: root.hideDeclined
            weekStartsMonday: root.weekStart === 1
            announceLeadMinutes: root.setting("announceLeadMinutes", 15)

            syncState: root.syncState
            setupCommand: root.setupCommand
            setupCommandCopied: root.setupCommandCopied
            onSetupCommandCopyRequested: root.copySetupCommand()
            eventCount: root.eventDoc && root.eventDoc.occurrences ? root.eventDoc.occurrences.length : 0
            sourceLabel: root.eventDoc ? String(root.eventDoc.source || "") : ""
            syncedAt: root.eventDoc && root.eventDoc.syncedAt
              ? Qt.formatDateTime(new Date(root.eventDoc.syncedAt), "d MMM HH:mm")
              : ""

            onCalendarToggled: function(calendarId) { root.toggleCalendar(calendarId) }
            onYearProgressToggled: root.toggleYearProgress()
            onWorkingLocationToggled: root.toggleWorkingLocation()
            onHideDeclinedToggled: root.toggleHideDeclined()
            onWeekStartToggled: root.toggleWeekStart()
            onLeadMinutesPicked: function(minutes) { root.setAnnounceLeadMinutes(minutes) }
          }
        }
      }
    }
  }
}
