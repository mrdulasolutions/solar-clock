// Solar clock: four-beat day rather than civil hours.
//
//   sunrise  → count up from sunrise
//   mid day  → count down to sunset
//   sunset   → count up from sunset
//   midnight → count down to sunrise
//
// Location is Omarchy's weather location (weather.json, else the same
// wttr.in auto-detect the weather widget uses). Sunrise and sunset come
// from Open-Meteo, the same forecast API the weather panel already hits.
// Midday and midnight are the midpoints of those published times.
//
// HTTPS bodies are fetched by ./fetch-https, which caps the stream at
// HTTPS_MAX_BYTES in the child process and refuses overflow.

var HTTPS_MAX_BYTES = 262144

function httpsGetCommand(scriptPath, url) {
  var script = String(scriptPath || "")
  var href = String(url || "")
  if (!script || href.indexOf("https://") !== 0) return []
  return ["bash", script, href]
}

function acceptHttpsBody(raw) {
  var text = String(raw || "")
  if (!text || text.length > HTTPS_MAX_BYTES) return ""
  return text
}

function isValidDate(date) {
  return date instanceof Date && !isNaN(date.getTime())
}

function sameMinute(a, b) {
  if (!isValidDate(a) || !isValidDate(b)) return false
  return Math.floor(a.getTime() / 60000) === Math.floor(b.getTime() / 60000)
}

function pad2(n) {
  n = Math.floor(Math.abs(n))
  return (n < 10 ? "0" : "") + n
}

function formatDuration(ms, roundUp) {
  var minutes = roundUp
    ? Math.max(0, Math.ceil(ms / 60000))
    : Math.max(0, Math.floor(ms / 60000))
  var hours = Math.floor(minutes / 60)
  var mins = minutes % 60
  return pad2(hours) + ":" + pad2(mins)
}

function formatClock(date) {
  if (!isValidDate(date)) return "—"
  return pad2(date.getHours()) + ":" + pad2(date.getMinutes())
}

function localDateKey(date) {
  if (!isValidDate(date)) return ""
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days, 12, 0, 0, 0)
}

function midpoint(a, b) {
  if (!isValidDate(a) || !isValidDate(b)) return null
  return new Date(Math.floor((a.getTime() + b.getTime()) / 2))
}

function parseIsoLocal(value) {
  if (value === undefined || value === null || value === "") return null
  var text = String(value)
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(text)) text += ":00"
  var date = new Date(text)
  return isValidDate(date) ? date : null
}

function parseWttrClock(dateStr, clockStr) {
  var match = String(clockStr || "").match(/^(\d{1,2}):(\d{2})\s*([AP]M)$/i)
  if (!match) return null
  var hour = parseInt(match[1], 10)
  var minute = parseInt(match[2], 10)
  var ampm = match[3].toUpperCase()
  if (ampm === "AM") {
    if (hour === 12) hour = 0
  } else if (hour !== 12) {
    hour += 12
  }
  var parts = String(dateStr || "").split("-")
  if (parts.length !== 3) return null
  var date = new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10), hour, minute, 0, 0)
  return isValidDate(date) ? date : null
}

function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset
    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

function hasCoordinates(location) {
  return !!(location && !isNaN(parseFloat(location.latitude)) && !isNaN(parseFloat(location.longitude)))
}

function parseWttrLocation(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var area = data && data.nearest_area && data.nearest_area[0] ? data.nearest_area[0] : null
    if (!area) return null
    var latitude = parseFloat(area.latitude)
    var longitude = parseFloat(area.longitude)
    if (isNaN(latitude) || isNaN(longitude)) return null
    var name = area.areaName && area.areaName[0] ? String(area.areaName[0].value || "") : ""
    var region = area.region && area.region[0] ? String(area.region[0].value || "") : ""
    return {
      name: name.replace(/^\s+|\s+$/g, ""),
      region: region.replace(/^\s+|\s+$/g, ""),
      latitude: latitude,
      longitude: longitude
    }
  } catch (e) {
    return null
  }
}

function parseWttrSunDays(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var weather = data && data.weather ? data.weather : []
    var days = []
    for (var i = 0; i < weather.length; i++) {
      var ast = weather[i] && weather[i].astronomy ? weather[i].astronomy[0] : null
      if (!ast) continue
      days.push({
        date: String(weather[i].date || ""),
        sunrise: parseWttrClock(weather[i].date, ast.sunrise),
        sunset: parseWttrClock(weather[i].date, ast.sunset)
      })
    }
    return days
  } catch (e) {
    return []
  }
}

function parseOpenMeteoSunDays(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    var daily = data && data.daily ? data.daily : null
    if (!daily || !daily.time) return { days: [], latitude: null, longitude: null, timezone: "" }
    var days = []
    for (var i = 0; i < daily.time.length; i++) {
      days.push({
        date: String(daily.time[i] || ""),
        sunrise: parseIsoLocal(daily.sunrise ? daily.sunrise[i] : null),
        sunset: parseIsoLocal(daily.sunset ? daily.sunset[i] : null)
      })
    }
    return {
      days: days,
      latitude: data.latitude,
      longitude: data.longitude,
      timezone: String(data.timezone || "")
    }
  } catch (e) {
    return { days: [], latitude: null, longitude: null, timezone: "" }
  }
}

function wttrLocationUrl(configured) {
  var name = configured && configured.name ? String(configured.name).replace(/^\s+|\s+$/g, "") : ""
  if (name) return "https://wttr.in/" + encodeURIComponent(name) + "?format=j1"
  return "https://wttr.in/?format=j1"
}

function openMeteoSunUrl(latitude, longitude) {
  return "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + encodeURIComponent(String(latitude))
    + "&longitude=" + encodeURIComponent(String(longitude))
    + "&daily=sunrise,sunset"
    + "&timezone=auto"
    + "&forecast_days=2"
    + "&past_days=1"
}

function findDay(days, date) {
  var key = typeof date === "string" ? date : localDateKey(date)
  for (var i = 0; i < (days || []).length; i++) {
    if (days[i] && days[i].date === key) return days[i]
  }
  return null
}

function emptyState(now, reason) {
  return {
    label: "—",
    tooltip: reason || "Waiting for location",
    detail: reason || "Waiting for location",
    phase: "unknown",
    sunrise: null,
    sunset: null,
    midday: null,
    midnight: null,
    wallClock: now,
    polar: null,
    daytime: false,
    source: ""
  }
}

function solarState(now, days, source) {
  if (!isValidDate(now)) now = new Date()
  var today = findDay(days, now)
  var yesterday = findDay(days, addDays(now, -1))
  var tomorrow = findDay(days, addDays(now, 1))
  if (!today) return emptyState(now, "Waiting for sunrise data")

  var sunrise = today.sunrise
  var sunset = today.sunset
  if (!isValidDate(sunrise) && !isValidDate(sunset)) {
    return {
      label: "polar day",
      tooltip: "Sun stays up",
      detail: "No sunrise or sunset in today's forecast.",
      phase: "polar-day",
      sunrise: null,
      sunset: null,
      midday: null,
      midnight: null,
      wallClock: now,
      polar: "day",
      daytime: true,
      source: source || ""
    }
  }
  if (!isValidDate(sunrise) || !isValidDate(sunset))
    return emptyState(now, "Incomplete sunrise data")

  var midday = midpoint(sunrise, sunset)
  var prevSunset = yesterday && yesterday.sunset ? yesterday.sunset : null
  var nextSunrise = tomorrow && tomorrow.sunrise ? tomorrow.sunrise : null
  var midnightLast = prevSunset ? midpoint(prevSunset, sunrise) : null
  var midnightNext = nextSunrise ? midpoint(sunset, nextSunrise) : null

  var event = null
  var phase = ""

  if (now < sunrise) {
    if (sameMinute(now, midnightLast)) event = "midnight"
    else if (isValidDate(midnightLast) && now < midnightLast) phase = "since-sunset"
    else phase = "until-sunrise"
  } else if (now < sunset) {
    if (sameMinute(now, sunrise)) event = "sunrise"
    else if (sameMinute(now, midday)) event = "mid day"
    else if (now < midday) phase = "since-sunrise"
    else phase = "until-sunset"
  } else {
    if (sameMinute(now, sunset)) event = "sunset"
    else if (sameMinute(now, midnightNext)) event = "midnight"
    else if (isValidDate(midnightNext) && now < midnightNext) phase = "since-sunset"
    else phase = "until-sunrise"
  }

  if (event) phase = event === "mid day" ? "midday" : event

  var label = "—"
  var tooltip = ""
  var detail = ""
  var duration = ""

  if (event === "sunrise") {
    label = "sunrise"
    tooltip = "Sunrise · " + formatClock(sunrise)
    detail = "Sun is up."
  } else if (event === "mid day") {
    label = "mid day"
    tooltip = "Midday · " + formatClock(midday)
    detail = "Halfway from sunrise to sunset."
  } else if (event === "sunset") {
    label = "sunset"
    tooltip = "Sunset · " + formatClock(sunset)
    detail = "Sun is down."
  } else if (event === "midnight") {
    var shownMidnight = now < sunrise ? midnightLast : midnightNext
    label = "midnight"
    tooltip = "Midnight · " + formatClock(shownMidnight)
    detail = "Halfway from sunset to sunrise."
  } else if (phase === "since-sunrise") {
    duration = formatDuration(now.getTime() - sunrise.getTime(), false)
    label = duration
    tooltip = duration + " since sunrise"
    detail = "Counting up from sunrise to midday."
  } else if (phase === "until-sunset") {
    duration = formatDuration(sunset.getTime() - now.getTime(), true)
    label = duration
    tooltip = duration + " until sunset"
    detail = "Counting down from midday to sunset."
  } else if (phase === "since-sunset") {
    var fromSunset = now < sunrise ? prevSunset : sunset
    duration = formatDuration(now.getTime() - fromSunset.getTime(), false)
    label = duration
    tooltip = duration + " since sunset"
    detail = "Counting up from sunset to midnight."
  } else if (phase === "until-sunrise") {
    var toSunrise = now < sunrise ? sunrise : nextSunrise
    duration = formatDuration(toSunrise.getTime() - now.getTime(), true)
    label = duration
    tooltip = duration + " until sunrise"
    detail = "Counting down from midnight to sunrise."
  }

  return {
    label: label,
    tooltip: tooltip,
    detail: detail,
    phase: phase,
    sunrise: sunrise,
    sunset: sunset,
    midday: midday,
    midnight: now < sunrise ? midnightLast : midnightNext,
    prevSunset: prevSunset,
    nextSunrise: nextSunrise,
    wallClock: now,
    polar: null,
    daytime: now >= sunrise && now < sunset,
    source: source || ""
  }
}

function spanLabel(ms) {
  if (!(ms > 0)) return "—"
  var minutes = Math.round(ms / 60000)
  var hours = Math.floor(minutes / 60)
  var mins = minutes % 60
  if (hours <= 0) return mins + "m"
  return hours + "h " + pad2(mins) + "m"
}

function clamp01(value) {
  if (!(value > 0)) return 0
  if (value > 1) return 1
  return value
}

// Where the marker sits on the day arc (sunrise → sunset) and the night arc
// (sunset → next sunrise, or last sunset → this sunrise before dawn).
function arcState(solar) {
  var now = solar && solar.wallClock
  var sunrise = solar && solar.sunrise
  var sunset = solar && solar.sunset
  var empty = { ready: false, daytime: false, day: 0, night: 0, daylight: "—", nightLength: "—" }
  if (!isValidDate(now) || !isValidDate(sunrise) || !isValidDate(sunset) || (solar && solar.polar))
    return empty

  var dayMs = sunset.getTime() - sunrise.getTime()
  var day = dayMs > 0 ? (now.getTime() - sunrise.getTime()) / dayMs : 0
  var nightStart = now < sunrise ? solar.prevSunset : sunset
  var nightEnd = now < sunrise ? sunrise : solar.nextSunrise
  var nightMs = isValidDate(nightStart) && isValidDate(nightEnd) ? nightEnd.getTime() - nightStart.getTime() : 0
  var night = nightMs > 0 ? (now.getTime() - nightStart.getTime()) / nightMs : 0

  return {
    ready: true,
    daytime: solar.daytime === true,
    day: clamp01(day),
    night: clamp01(night),
    daylight: spanLabel(dayMs),
    nightLength: spanLabel(nightMs)
  }
}

function activeEvent(phase) {
  if (phase === "sunrise" || phase === "since-sunrise" || phase === "until-sunrise") return "sunrise"
  if (phase === "midday") return "midday"
  if (phase === "sunset" || phase === "since-sunset" || phase === "until-sunset") return "sunset"
  if (phase === "midnight") return "midnight"
  return ""
}

function verticalLines(label) {
  var text = String(label || "")
  if (text.indexOf(":") !== -1) return text.split(":")
  if (text.indexOf(" ") !== -1) return text.split(" ")
  return [text]
}
