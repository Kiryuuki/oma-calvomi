// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node.

var MS_PER_DAY = 86400000

var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  return null
}

function normalizedWeekStart(value, fallback) {
  var coerced = coerceWeekStart(value)
  if (coerced !== null) return coerced
  var fallbackCoerced = coerceWeekStart(fallback)
  return fallbackCoerced !== null ? fallbackCoerced : 1
}

function weekStartSettingName(index) {
  var normalized = ((Math.round(Number(index)) % 7) + 7) % 7
  return WEEKDAY_NAMES[normalized] || "monday"
}

function toggledWeekStart(index) {
  return index === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var order = []
  for (var i = 0; i < 7; i++) order.push((start + i) % 7)
  return order
}

function isoWeek(year, month, day) {
  var target = new Date(year, month, day)
  var dayNr = (target.getDay() + 6) % 7
  target.setDate(target.getDate() - dayNr + 3)
  var firstThursday = target.valueOf()
  target.setMonth(0, 1)
  if (target.getDay() !== 4) target.setMonth(0, 1 + ((4 - target.getDay() + 7) % 7))
  return 1 + Math.ceil((firstThursday - target) / 604800000)
}

function dayOfYear(year, month, day) {
  return Math.round((new Date(year, month, day) - new Date(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  var leap = (year % 4 === 0 && year % 100 !== 0) || (year % 400 === 0)
  return leap ? 366 : 365
}

function yearProgress(year, month, day) {
  var total = daysInYear(year)
  var done = dayOfYear(year, month, day) - 1
  return Math.max(0, Math.min(1, done / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

var DEFAULT_LIFE_EXPECTANCY = 80
var MIN_BIRTH_YEAR = 1900
var MAX_LIFE_EXPECTANCY = 120

function parseBirthYear(value, currentYear) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  var rounded = Math.round(n)
  if (rounded < MIN_BIRTH_YEAR || rounded > (currentYear || new Date().getFullYear())) return 0
  return rounded
}

function ageFromBirthYear(birthYear, currentYear) {
  if (birthYear <= 0) return 0
  var nowYear = currentYear || new Date().getFullYear()
  var diff = nowYear - birthYear
  return diff >= 0 ? diff : 0
}

function parseAge(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  var rounded = Math.round(n)
  return rounded > 0 && rounded <= MAX_LIFE_EXPECTANCY ? rounded : 0
}

function parseLifeExpectancy(value) {
  var n = Number(value)
  if (!isFinite(n)) return DEFAULT_LIFE_EXPECTANCY
  var rounded = Math.round(n)
  return rounded > 0 && rounded <= MAX_LIFE_EXPECTANCY ? rounded : DEFAULT_LIFE_EXPECTANCY
}

function lifeProgress(age, expectancy) {
  var max = parseLifeExpectancy(expectancy)
  if (age <= 0 || max <= 0) return 0
  return Math.max(0, Math.min(1, age / max))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

function monthGrid(year, month, weekStart, todayKey, eventIndex) {
  var firstDay = new Date(year, month, 1)
  var totalDays = new Date(year, month + 1, 0).getDate()
  var prevMonthDays = new Date(year, month, 0).getDate()

  var firstWeekday = firstDay.getDay()
  var offset = (firstWeekday - weekStart + 7) % 7

  var weeks = []
  var dayCounter = 1
  var nextMonthCounter = 1

  for (var w = 0; w < 6; w++) {
    var days = []
    var weekNum = 0
    for (var d = 0; d < 7; d++) {
      var cellIndex = w * 7 + d
      var dayNumber = 0
      var inCurrentMonth = false
      var cellYear = year
      var cellMonth = month

      if (cellIndex < offset) {
        dayNumber = prevMonthDays - offset + cellIndex + 1
        cellMonth = month - 1
        if (cellMonth < 0) { cellMonth = 11; cellYear-- }
      } else if (dayCounter <= totalDays) {
        dayNumber = dayCounter++
        inCurrentMonth = true
      } else {
        dayNumber = nextMonthCounter++
        cellMonth = month + 1
        if (cellMonth > 11) { cellMonth = 0; cellYear++ }
      }

      var key = dateKey(cellYear, cellMonth, dayNumber)
      if (d === 0 || weekNum === 0) weekNum = isoWeek(cellYear, cellMonth, dayNumber)

      var dots = eventIndex ? eventColors(eventIndex, key, 4) : []

      days.push({
        day: dayNumber,
        key: key,
        currentMonth: inCurrentMonth,
        isToday: key === todayKey,
        dots: dots
      })
    }
    weeks.push({ week: weekNum, days: days })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var d = new Date(year, month + delta, 1)
  return { year: d.getFullYear(), month: d.getMonth() }
}

var STALE_INTERVAL_MULTIPLIER = 4

function parseEvents(rawText) {
  if (!rawText || String(rawText).trim().length === 0) {
    return { doc: null, versionMismatch: false }
  }
  try {
    var doc = JSON.parse(rawText)
    var mismatch = doc && doc.version && doc.version > 1
    return { doc: doc, versionMismatch: Boolean(mismatch) }
  } catch (e) {
    return { doc: null, versionMismatch: false }
  }
}

function indexEventsByDate(events) {
  var index = {}
  if (!events || !events.length) return index
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var key = event && (event.dateKey || (event.start ? String(event.start).substr(0, 10) : ""))
    if (!key) continue
    if (!index[key]) index[key] = []
    index[key].push(event)
  }
  return index
}

function indexEvents(doc, options) {
  var events = (doc && (doc.occurrences || doc.events)) || []
  var visible = visibleEvents(events, (options && options.hiddenCalendars) || [], options)
  return indexEventsByDate(visible)
}

function eventsForDateKey(index, dateKey) {
  if (!index || !dateKey) return []
  return index[dateKey] || []
}

function calendarsInDocument(doc) {
  if (doc && doc.calendars && Array.isArray(doc.calendars) && doc.calendars.length > 0) {
    return doc.calendars.slice().sort(function(a, b) {
      return (a.name || "").localeCompare(b.name || "")
    })
  }

  var events = (doc && (doc.occurrences || doc.events)) || []
  var byId = {}
  var ordered = []

  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var id = event && event.calendarId
    if (!id || byId[id]) continue
    byId[id] = true
    ordered.push({
      id: id,
      name: event.calendarName || id,
      color: event.color || "",
      isBirthday: Boolean(event.isBirthday)
    })
  }

  ordered.sort(function(a, b) {
    return (a.name || "").localeCompare(b.name || "")
  })
  return ordered
}

function isCalendarHidden(hidden, calendarId) {
  if (!hidden || !hidden.length) return false
  return hidden.indexOf(String(calendarId)) !== -1
}

function toggleHiddenCalendar(hidden, calendarId) {
  var id = String(calendarId)
  var next = []
  var found = false

  for (var i = 0; i < (hidden || []).length; i++) {
    if (String(hidden[i]) === id) { found = true; continue }
    next.push(hidden[i])
  }

  if (!found) next.push(id)
  return next
}

function isNoisyEventType(event) {
  var t = event && event.eventType
  return t === "workingLocation" || t === "outOfOffice"
}

function isDeclined(event) {
  return Boolean(event && event.responseStatus === "declined")
}

function isOutOfOffice(event) {
  return Boolean(event && event.eventType === "outOfOffice")
}

function safeUrl(url) {
  var text = String(url || "").trim()
  if (/^https?:\/\//i.test(text)) return text
  return ""
}

function commandPathFromUrl(fileUrl, home) {
  var p = String(fileUrl || "").replace(/^file:\/\//, "")
  return p.replace(home, "~")
}

function meetingUrlFor(event) {
  return (event && event.meetingUrl) ? safeUrl(event.meetingUrl) : ""
}

function eventUrlFor(event) {
  return (event && event.htmlLink) ? safeUrl(event.htmlLink) : ""
}

function isJoinableNow(event, nowMs, todayKey) {
  if (!event || !event.meetingUrl || event.allDay || event.dateKey !== todayKey) return false
  var startMs = Date.parse(event.start)
  var endMs = Date.parse(event.end)
  if (isNaN(startMs) || isNaN(endMs)) return false

  var lead = 15 * 60 * 1000
  return nowMs >= (startMs - lead) && nowMs <= (endMs + lead)
}

function visibleEvents(events, hidden, options) {
  if (!events || !events.length) return []

  var opts = options || {}
  var dropNoisy = opts.showWorkingLocation === false
  var dropDeclined = opts.hideDeclined === true

  var visible = []
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    if (isCalendarHidden(hidden, event.calendarId)) continue
    if (dropNoisy && isNoisyEventType(event)) continue
    if (dropDeclined && isDeclined(event)) continue
    visible.push(event)
  }
  return visible
}

var MINUTE_MS = 60 * 1000
var HOUR_MS = 60 * MINUTE_MS
var DAY_MS = 24 * HOUR_MS

function nextEvent(events, nowMs) {
  var best = null
  var bestMs = null

  for (var i = 0; i < (events || []).length; i++) {
    var event = events[i]
    if (!event || event.allDay) continue

    var startMs = Date.parse(event.start)
    if (isNaN(startMs) || startMs < nowMs) continue

    if (bestMs === null || startMs < bestMs) {
      bestMs = startMs
      best = event
    }
  }

  return best
}

function nextEventToday(events, nowMs, todayKey) {
  var todays = []
  for (var i = 0; i < (events || []).length; i++) {
    if (events[i] && events[i].dateKey === todayKey) todays.push(events[i])
  }
  return nextEvent(todays, nowMs)
}

function formatCountdown(deltaMs) {
  if (deltaMs === null || isNaN(deltaMs) || deltaMs < 0 || deltaMs >= DAY_MS) return null
  if (deltaMs < MINUTE_MS) return "now"

  var minutes = Math.floor(deltaMs / MINUTE_MS)
  if (minutes < 60) return "in " + minutes + "min"

  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return rest === 0 ? "in " + hours + "h" : "in " + hours + "h " + rest + "min"
}

var MAX_ANNOUNCE_TITLE = 28

function truncateTitle(title, limit) {
  var s = String(title || "").trim()
  var max = limit || MAX_ANNOUNCE_TITLE
  return s.length > max ? s.substr(0, max - 1) + "…" : s
}

function announceLabel(clockText, title, countdown, limit) {
  if (!title || !countdown) return clockText
  var shortTitle = truncateTitle(title, limit)
  return shortTitle + " (" + countdown + ")"
}

function millisUntil(event, nowMs) {
  if (!event || !event.start) return -1
  var startMs = Date.parse(event.start)
  return isNaN(startMs) ? -1 : startMs - nowMs
}

function shouldAnnounce(event, nowMs, leadMinutes) {
  if (!event || leadMinutes <= 0) return false
  var delta = millisUntil(event, nowMs)
  return delta >= 0 && delta <= leadMinutes * 60 * 1000
}

function dateFromKey(dateKeyStr, fallback) {
  if (!dateKeyStr) return fallback || new Date()
  var parts = String(dateKeyStr).split("-")
  if (parts.length !== 3) return fallback || new Date()
  return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10))
}

function eventColors(index, dateKeyStr, limit) {
  var events = eventsForDateKey(index, dateKeyStr)
  var colors = []
  for (var i = 0; i < events.length; i++) {
    var color = events[i].color
    if (!color || colors.indexOf(color) !== -1) continue
    colors.push(color)
    if (limit > 0 && colors.length >= limit) break
  }
  return colors
}

function syncState(doc, nowMs, intervalSeconds) {
  if (!doc || !doc.syncedAt) return "missing"

  var syncedMs = Date.parse(doc.syncedAt)
  if (isNaN(syncedMs)) return "missing"

  var thresholdMs = intervalSeconds * STALE_INTERVAL_MULTIPLIER * 1000
  return (nowMs - syncedMs) > thresholdMs ? "stale" : "ok"
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    parseEvents: parseEvents,
    indexEvents: indexEvents,
    indexEventsByDate: indexEventsByDate,
    dateFromKey: dateFromKey,
    calendarsInDocument: calendarsInDocument,
    nextEvent: nextEvent,
    nextEventToday: nextEventToday,
    formatCountdown: formatCountdown,
    truncateTitle: truncateTitle,
    announceLabel: announceLabel,
    millisUntil: millisUntil,
    shouldAnnounce: shouldAnnounce,
    isCalendarHidden: isCalendarHidden,
    toggleHiddenCalendar: toggleHiddenCalendar,
    visibleEvents: visibleEvents,
    isNoisyEventType: isNoisyEventType,
    isDeclined: isDeclined,
    isOutOfOffice: isOutOfOffice,
    safeUrl: safeUrl,
    commandPathFromUrl: commandPathFromUrl,
    meetingUrlFor: meetingUrlFor,
    eventUrlFor: eventUrlFor,
    isJoinableNow: isJoinableNow,
    eventsForDateKey: eventsForDateKey,
    eventColors: eventColors,
    syncState: syncState
  }
}
