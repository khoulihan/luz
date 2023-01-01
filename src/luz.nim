import std/[strformat, strutils, times, json, colors, tables, terminal]
import docopt
import config
import holidays


const doc = """
Luz.

Usage:
  luz [--chart] [--conky] [--add-hours=<hours>] [--bands=<file>]
  luz edit [--bands=<file>]
  luz (-h | --help)
  luz --version

Options:
  -h --help             Show this screen.
  --version             Show version.
  --chart               Show a chart of today's rate bands.
  --conky               Produce output for display in conky
  --add-hours=<hours>   Add the specified number of hours to the current time
  --bands=<file>        Read the band information from a file other than the default
"""

const version = "0.1.0"


type
  Hour = range[0..24]


type
  ScheduleType = enum
    weekday, weekend


type
  Rate = ref object
    name: string
    colour: Color
    energyRate: float


type
  Band = ref object
    start: Hour
    `end`: Hour
    rate: Rate


type
  Schedule = ref object
    `type`: ScheduleType
    bands: seq[Band]


proc parseBands(bandsFile: string): Table[ScheduleType, Schedule] =
  let parsed = parseJson(readFile(bandsFile))
  var rates = initTable[string, Rate]()

  for k, v in parsed["rates"]:
    rates[k] = Rate(
      name: v["name"].getStr,
      colour: parseColor v["colour"].getStr,
      energyRate: v["energy_rate"].getFloat
    )

  var schedules = initTable[ScheduleType, Schedule]()

  for k, v in parsed["schedules"]:

    let t = parseEnum[ScheduleType](k)
    schedules[t] = Schedule(
      `type`: t,
      bands: @[]
    )

    for b in v:
      schedules[t].bands.add Band(
        start: b["start"].getInt,
        `end`: b["end"].getInt,
        rate: rates[b["rate"].getStr]
      )

  result = schedules


template isWeekend(t: DateTime): bool =
  (t.weekDay == dSat or t.weekDay == dSun or t.isHoliday)


template getScheduleType(forTime: DateTime): ScheduleType =
  if forTime.isWeekend:
    ScheduleType.weekend
  else:
    ScheduleType.weekday


proc getBand(schedule: Schedule, forTime: DateTime): Band =
  for b in schedule.bands:
    if forTime.hour >= b.start and forTime.hour < b.`end`:
      result = b
      break


template getSchedule(
    schedules: Table[ScheduleType, Schedule],
    forTime: DateTime
  ): Schedule =

  schedules[forTime.getScheduleType]


template getBand(schedules: Table[ScheduleType, Schedule], forTime: DateTime): Band =
  schedules.getSchedule(forTime).getBand(forTime)


proc getBandEnd(band: Band, date: DateTime): DateTime =
  var endDay = dateTime(
    hour = 0,
    year = date.year,
    month = date.month,
    monthday = date.monthday,
    zone = date.timezone
  )
  if band.`end` == 24:
    endDay = endDay + 1.days
  result = dateTime(
    hour = if band.`end` == 24: 0 else: band.`end`,
    year = endDay.year,
    month = endDay.month,
    monthday = endDay.monthday,
    zone = endDay.timezone
  )


proc getEndOfRate(
    schedules: Table[ScheduleType, Schedule],
    currentBand: Band,
    forTime: DateTime
  ): DateTime =

  if currentBand.`end` != 24:
    # This assumes that we won't have two consecutive bands with the same
    # rate in our config - so better enforce that in the editing or
    # normalise the bands as they are imported.
    return dateTime(
      hour = currentBand.`end`,
      year = forTime.year,
      month = forTime.month,
      monthday = forTime.monthday,
      zone = forTime.timezone
    )

  var endDay: DateTime
  var currentRate = currentBand.rate.name
  var currentBand = currentBand
  var currentBandEnd = getBandEnd(currentBand, forTime)
  var currentSchedule: Schedule

  while true:
    currentBand = schedules.getSchedule(currentBandEnd).getBand(currentBandEnd)

    if currentBand.rate.name != currentRate:
      result = currentBandEnd
      break

    currentBandEnd = getBandEnd(currentBand, currentBandEnd)


template getEndOfRate(
    schedules: Table[ScheduleType, Schedule],
    forTime: DateTime
  ): DateTime =
  getEndOfRate(
    schedules,
    schedules.getBand(forTime),
    forTime
  )


proc DisplayCurrentStatusOnTerminal(
    currentBand: Band,
    currentBandEnd: DateTime,
    remaining: Duration,
    remainingMinutes: int64
  ) =
  styledEcho "Current rate: ", ansiForegroundColorCode(currentBand.rate.colour), &"{currentBand.rate.name}"
  styledEcho "Ends at ", fgCyan, &"{currentBandEnd:HH:mm} on {currentBandEnd:dddd dd/MM}"
  styledEcho "Time remaining: ", fgCyan, &"{remaining.inHours} hours, {remainingMinutes} minutes"


proc OutputCurrentStatusConky(
    currentBand: Band,
    currentBandEnd: DateTime,
    remaining: Duration,
    remainingMinutes: int64
  ) =
  # TODO: This should accept some sort of template or something!
  stdout.writeLine &"${{color {currentBand.rate.colour}}}${{font FiraCode Nerd Font:size= 12}}    ${{color #abb2bf}}${{font DejaVu Sans:size= 12}}{remaining.inHours}:{remainingMinutes:02} remaining"


proc displayCurrentStatus(
    currentBand: Band,
    currentBandEnd: DateTime,
    currentTime: DateTime,
    conky: bool
  ) =

  let remaining = currentBandEnd - currentTime
  let remainingMinutes = remaining.inMinutes - (remaining.inHours * 60)

  if not conky:
    DisplayCurrentStatusOnTerminal(
      currentBand,
      currentBandEnd,
      remaining,
      remainingMinutes
    )
  else:
    OutputCurrentStatusConky(
      currentBand,
      currentBandEnd,
      remaining,
      remainingMinutes
    )

proc displayChart(schedule: Schedule, currentBand: Band, currentTime: DateTime) =
  echo()
  var hourIndicator, currentIndicator: string
  for band in schedule.bands:
    for q in band.start..band.`end`-1:
      hourIndicator = if q == band.start: &"    {q:02} " else: "       "
      currentIndicator = if q == currentTime.hour: &" ⇦ {currentTime:HH:mm}" else: ""
      styledEcho ansiForegroundColorCode(band.rate.colour), &"{hourIndicator}████", currentIndicator


proc handleDisplayCurrentCommand(
  bandsFile: string,
  add: int = 0,
  chart: bool = false,
  conky: bool = false
) =
  ## Handle the default command, which is to display the current status
  ## (and maybe a chart of the current day as well)

  var schedules = parseBands(bandsFile)

  let currentTime = now() + add.hours
  let currentBand = schedules.getBand(currentTime)
  let currentBandEnd = schedules.getEndOfRate(currentTime)

  displayCurrentStatus(
    currentBand,
    currentBandEnd,
    currentTime,
    conky
  )

  if chart and not conky:
    displayChart(schedules.getSchedule(currentTime), currentBand, currentTime)


when isMainModule:

  let args = docopt(doc, version = &"Luz {version}")

  let bandsArg = if args["--bands"]: $args["--bands"] else: ""

  if bandsArg == "":
    try:
      ensureConfigExists()
    except:
      quit "Config does not exist and could not be created"

  let bandsFile = if bandsArg == "": bandsFileLocation else: bandsArg

  if args["edit"]:
    quit "Not implemented yet"
  else:
    block handleConfig:
      loadConfig()
      if apiKey == "":
        styledEcho fgRed, "Holidays API key is not set.", fgDefault, " Please provide a key or press enter to skip holiday inclusion:"
        let key = readLine(stdin)
        if key != "":
          saveApiKey key
      if apiKey != "":
        try:
          loadHolidays()
        except:
          styledEcho fgRed, "Failed to retrieve holiday data. Holidays will not be accounted for."

    handleDisplayCurrentCommand(
      bandsFile,
      if args["--add-hours"]: parseInt($args["--add-hours"]) else: 0,
      args["--chart"],
      args["--conky"]
    )
