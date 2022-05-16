
import std/[os, times, httpclient, asyncdispatch, options, tables, terminal, json, strformat]
import config


const apiHost = "public-holiday.p.rapidapi.com"


type
  Holiday = ref object
    date: DateTime
    localName: string
    name: string
    countryCode: string
    fixed: bool
    global: bool
    counties: Option[seq[string]]
    launchYear: Option[int]


var holidays = initTable[int, seq[Holiday]]()


proc isHoliday*(d: DateTime): bool =
  result = false
  # This will occur if API key was not provided
  if not holidays.hasKey(d.year):
    return result
  for y, h in holidays[d.year]:
    # TODO: Maybe include an option to specify a "county" as well
    # global indicates that the holiday applies to the whole country
    if h.global:
      if h.date.yearday == d.yearday:
        result = true
        break


proc parseHolidays(j: JsonNode): seq[Holiday] =
  result = @[]

  for jh in j:
    result.add Holiday(
      date: parse(jh["date"].getStr, "yyyy-MM-dd"),
      localName: jh["localName"].getStr,
      name: jh["name"].getStr,
      countryCode: jh["countryCode"].getStr,
      fixed: jh["fixed"].getBool,
      global: jh["global"].getBool
    )


proc retrieveHolidaysFromApi(year: int, country: string): Future[string] {.async.} =
  ## Retrieve holiday data from the API
  var client = newAsyncHttpClient()
  client.headers["X-RapidAPI-Host"] = apiHost
  client.headers["X-RapidAPI-Key"] = apiKey
  return await client.getContent &"https://{apiHost}/{year}/{country}"


proc cache(result: string, cachePath: string) =
  var f: File
  if open(f, cachePath, fmWrite):
    try:
      f.write(result)
    finally:
      f.close


template erasePrevious() =
  cursorUp(1)
  eraseLine()


proc getDisplayProgressClosure(): proc(x: bool) =
  var lastTime = now()
  var phase = 0
  const phases = ["🮪", "🮫", "🮭", "🮬"]

  proc displayProgress(initial: bool = false) =
    let elapsed = now() - lastTime
    if elapsed.inMilliseconds > 100 or initial:
      lastTime = now()
      if not initial:
        erasePrevious
      styledEcho fgGreen, &"{phases[phase]}", fgCyan, " Retrieving holidays..."
      inc(phase)
      if phase > phases.high: phase = 0

  result = displayProgress


proc retrieveHolidays(year: int, country: string): JsonNode =
  let countryCachePath = joinPath(holidaysCacheLocation, country)
  let cachePath = countryCachePath.joinPath(&"{year}.json")
  if fileExists(cachePath):
    return parseJson readFile(cachePath)

  discard existsOrCreateDir cacheLocation
  discard existsOrCreateDir holidaysCacheLocation
  discard existsOrCreateDir countryCachePath
  
  let displayProgress = getDisplayProgressClosure()
  hideCursor()
  displayProgress true
  var holidaysFuture = retrieveHolidaysFromApi(year, country)
  while not holidaysFuture.finished:
    poll()
    displayProgress false
  erasePrevious
  showCursor()

  let holidaysResult = holidaysFuture.read
  holidaysResult.cache cachePath
  result = parseJson holidaysResult


proc loadHolidays*() =
  ## Loads holidays for this year and the next, either from the cache, if
  ## available, or from the API.
  let dt = now()

  for year in dt.year..dt.year + 1:
    holidays[year] = year.retrieveHolidays(country).parseHolidays
