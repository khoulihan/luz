
import std/os
import parsetoml


const DEFAULT_BANDS = readFile "./config/bands.json"
const DEFAULT_CONFIG = readFile "./config/luz.toml"


let configLocation* = getEnv("LUZ_CONFIG_HOME", getConfigDir() & "luz" & DirSep)
let cacheLocation* = getEnv("LUZ_CACHE_HOME", getCacheDir() & DirSep & "luz" & DirSep)
let bandsFileLocation* = joinPath(configLocation, "bands.json")
let configFileLocation* = joinPath(configLocation, "luz.toml")
let holidaysCacheLocation* = joinPath(cacheLocation, "holidays") & DirSep

var country*: string
var apiKey*: string


template saveToFile(fileName, data) =
  var f: File
  if open(f, fileName, fmWrite):
    try:
      f.write(data)
    finally:
      f.close


template checkFileExists(fileName, defaultData) =
  if not fileExists(fileName):
    saveToFile(fileName, defaultData)


proc ensureConfigExists*() =
  discard existsOrCreateDir configLocation
  checkFileExists(bandsFileLocation, DEFAULT_BANDS)
  checkFileExists(configFileLocation, DEFAULT_CONFIG)


proc loadConfig*() =
  let conf = parsetoml.parseFile(configFileLocation)
  country = conf["holidays"]["country"].getStr
  apiKey = conf["holidays"]["api_key"].getStr


proc saveApiKey*(key: string) =
  let conf = parsetoml.parseFile(configFileLocation)
  apiKey = key
  conf["holidays"]["api_key"] = newTString(key)
  saveToFile(configFileLocation, conf.toTomlString())
