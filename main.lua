require "import"
import "com.androlua.Http"
import "cjson"
import "android.widget.*"
import "android.view.*"
import "android.view.KeyEvent"
import "android.graphics.Color"
import "android.content.DialogInterface"
import "android.content.Intent"
import "android.content.Context"
import "android.content.ClipData"
import "android.location.LocationManager"
import "android.location.LocationListener"
import "android.media.MediaPlayer"
import "android.media.PlaybackParams"
import "android.util.Base64"
import "android.os.Handler"
import "android.os.Looper"
import "android.os.Build"
import "java.io.File"
import "java.io.FileOutputStream"
import "java.util.HashMap"

-- The updater is optional: do not crash if the module is missing
local okUpdater, updater = pcall(require, "updater")
if not okUpdater then updater = nil end

local context = service or activity
local mainHandler = Handler(Looper.getMainLooper())

local windows = {}
local dlg = nil
local navStack = {}
local userData = { username = "" }
local activeEditTexts = {}
local savedUsername = ""
local savedGeminiApiKey = ""
local showInlineWeather = false

local fetchedRealLocation = "Something went wrong"
local isFetchingData = false
local currentWeatherData = nil

local autoReportRunnable = nil

-- Notifications
local NOTIFICATION_URL = "https://raw.githubusercontent.com/Mahadeesh18/Excellent-Weather-Checker/main/notifications.txt"
local currentNotificationText = ""
local hasNewNotification = false
local notificationCount = 0

-- Open-Meteo (no API key needed)
local WEATHER_URL = "https://api.open-meteo.com/v1/forecast"
local AIR_QUALITY_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"

-- TTS (Gemini)
local CURRENT_MODEL = "gemini-2.5-flash-preview-tts"

-- committed TTS settings
local currentVoice = "Puck"
local currentRate = "1.0x"
local currentPitch = "50"
local currentInflection = "50"
-- working (unsaved) TTS settings
local selectedVoice = "Puck"
local selectedRate = "1.0x"
local selectedPitch = "50"
local selectedInflection = "50"

local mediaPlayer = nil
local isPlaying = false
local previewAudioPath = nil

local colorMap = {
  ["Black"]   = "#121212",
  ["Blue"]    = "#0D47A1",
  ["Brown"]   = "#3E2723",
  ["Cyan"]    = "#006064",
  ["Green"]   = "#1B5E20",
  ["Magenta"] = "#880E4F",
  ["Orange"]  = "#E65100",
  ["Pink"]    = "#C2185B",
  ["Purple"]  = "#4A148C",
  ["Red"]     = "#B71C1C",
  ["White"]   = "#E0E0E0",
  ["Yellow"]  = "#F57F17"
}

local colorNames = {
  "Black", "Blue", "Brown", "Cyan", "Green", "Magenta",
  "Orange", "Pink", "Purple", "Red", "White", "Yellow"
}

local currentThemeColor = "#0D47A1"
local currentSelectedColorName = "Blue"
local currentSoundEnabled = true
local currentSoundVolume = 100
local currentDetectLocationEnabled = true
local currentAutoReportEnabled = false
local currentAutoReportInterval = "5 minutes"
local currentForecastType = "Hourly forecast"
local currentTimeFormat = "24 Hours"

local tempSelectedColorName = "Blue"
local tempSoundEnabled = true
local tempSoundVolume = 100
local tempDetectLocationEnabled = true
local tempAutoReportEnabled = false
local tempAutoReportInterval = "5 minutes"
local tempForecastType = "Hourly forecast"
local tempTimeFormat = "24 Hours"

local currentPressUnit = "Hectopascals (hPa)"
local currentPrecipUnit = "Millimeters (mm)"
local currentTempUnit = "Celsius (°C)"
local currentVisUnit = "Kilometers"
local currentWindUnit = "Kilometers per hour (km/h)"

local tempPressUnit = currentPressUnit
local tempPrecipUnit = currentPrecipUnit
local tempTempUnit = currentTempUnit
local tempVisUnit = currentVisUnit
local tempWindUnit = currentWindUnit

local alertSettings = {
  severe = true, thunderstorm = true, heavy_rain = true, flood = true,
  snow = true, heat = true, cold = true, wind = true, cyclone = true,
  tornado = true, air_quality = true, fog = true
}
local tempAlertSettings = {}
for k, v in pairs(alertSettings) do tempAlertSettings[k] = v end

local currentWeatherReport = {
  air_quality = false, atmospheric_pressure = false, cloud_coverage = false,
  conditions = true, date = true, dew_point = false, feels_like_temperature = true,
  humidity = true, location = true, moonrise_time = false, moonset_time = false,
  precipitation = false, rain_percentage = false, sunrise_time = false,
  sunset_time = false, temperature = true, time = true, uv_index = false,
  visibility = false, wind_direction = false, wind_speed = true
}
local tempWeatherReport = {}
for k, v in pairs(currentWeatherReport) do tempWeatherReport[k] = v end

local showScreen
local setupAutoReportTimer

local prefs = context.getSharedPreferences("weather_app_prefs", Context.MODE_PRIVATE)

local function savePreferences()
  local editor = prefs.edit()
  editor.putString("username", savedUsername)
  editor.putString("gemini_api_key", savedGeminiApiKey)
  editor.putString("selectedColorName", currentSelectedColorName)
  editor.putString("themeColor", currentThemeColor)
  editor.putBoolean("soundEnabled", currentSoundEnabled)
  editor.putInt("soundVolume", currentSoundVolume)
  editor.putBoolean("detectLocationEnabled", currentDetectLocationEnabled)
  editor.putBoolean("autoReportEnabled", currentAutoReportEnabled)
  editor.putString("autoReportInterval", currentAutoReportInterval)
  editor.putString("forecastType", currentForecastType)
  editor.putString("timeFormat", currentTimeFormat)

  editor.putString("pressUnit", currentPressUnit)
  editor.putString("precipUnit", currentPrecipUnit)
  editor.putString("tempUnit", currentTempUnit)
  editor.putString("visUnit", currentVisUnit)
  editor.putString("windUnit", currentWindUnit)

  editor.putString("ttsVoice", currentVoice)
  editor.putString("ttsRate", currentRate)
  editor.putString("ttsPitch", currentPitch)
  editor.putString("ttsInflection", currentInflection)

  for k, v in pairs(currentWeatherReport) do editor.putBoolean("report_" .. k, v) end
  for k, v in pairs(alertSettings) do editor.putBoolean("alert_" .. k, v) end

  editor.apply()
end

local function loadPreferences()
  savedUsername = prefs.getString("username", "")
  userData.username = savedUsername
  savedGeminiApiKey = prefs.getString("gemini_api_key", "")

  currentSelectedColorName = prefs.getString("selectedColorName", "Blue")
  tempSelectedColorName = currentSelectedColorName
  currentThemeColor = colorMap[currentSelectedColorName] or "#0D47A1"

  currentSoundEnabled = prefs.getBoolean("soundEnabled", true)
  tempSoundEnabled = currentSoundEnabled
  currentSoundVolume = prefs.getInt("soundVolume", 100)
  tempSoundVolume = currentSoundVolume
  currentDetectLocationEnabled = prefs.getBoolean("detectLocationEnabled", true)
  tempDetectLocationEnabled = currentDetectLocationEnabled
  currentAutoReportEnabled = prefs.getBoolean("autoReportEnabled", false)
  tempAutoReportEnabled = currentAutoReportEnabled
  currentAutoReportInterval = prefs.getString("autoReportInterval", "5 minutes")
  tempAutoReportInterval = currentAutoReportInterval
  currentForecastType = prefs.getString("forecastType", "Hourly forecast")
  tempForecastType = currentForecastType
  currentTimeFormat = prefs.getString("timeFormat", "24 Hours")
  tempTimeFormat = currentTimeFormat

  currentPressUnit = prefs.getString("pressUnit", "Hectopascals (hPa)")
  tempPressUnit = currentPressUnit
  currentPrecipUnit = prefs.getString("precipUnit", "Millimeters (mm)")
  tempPrecipUnit = currentPrecipUnit
  currentTempUnit = prefs.getString("tempUnit", "Celsius (°C)")
  tempTempUnit = currentTempUnit
  currentVisUnit = prefs.getString("visUnit", "Kilometers")
  tempVisUnit = currentVisUnit
  currentWindUnit = prefs.getString("windUnit", "Kilometers per hour (km/h)")
  tempWindUnit = currentWindUnit

  currentVoice = prefs.getString("ttsVoice", "Puck")
  currentRate = prefs.getString("ttsRate", "1.0x")
  currentPitch = prefs.getString("ttsPitch", "50")
  currentInflection = prefs.getString("ttsInflection", "50")
  selectedVoice, selectedRate, selectedPitch, selectedInflection =
    currentVoice, currentRate, currentPitch, currentInflection

  for k, v in pairs(currentWeatherReport) do
    local savedVal = prefs.getBoolean("report_" .. k, v)
    currentWeatherReport[k] = savedVal
    tempWeatherReport[k] = savedVal
  end

  for k, _ in pairs(alertSettings) do
    local val = prefs.getBoolean("alert_" .. k, true)
    alertSettings[k] = val
    tempAlertSettings[k] = val
  end
end

loadPreferences()

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function runOnUi(callback)
  mainHandler.post(Runnable({ run = callback }))
end

local function showToast(msg)
  runOnUi(function()
    Toast.makeText(context, tostring(msg), Toast.LENGTH_SHORT).show()
  end)
end

-- Safe accessors for numeric & string JSON elements
local function num(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

local function str(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function isValidEnglishName(name)
  if not name or name == "" then return false end
  return name:match("^[A-Za-z%s]+$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------
local function fetchNotifications(callback)
  local dynamicUrl = NOTIFICATION_URL .. "?t=" .. os.time()
  Http.get(dynamicUrl, nil, "UTF-8", {}, function(code, content)
    if code == 200 and content and content:match("%S") then
      currentNotificationText = content:match("^%s*(.-)%s*$")
      local lastSeenNotif = prefs.getString("last_seen_notification", "")
      if currentNotificationText == lastSeenNotif then
        hasNewNotification = false
        notificationCount = 0
      else
        local count = 0
        for line in currentNotificationText:gmatch("[^\r\n]+") do
          if line:match("%S") then count = count + 1 end
        end
        if count > 0 then
          notificationCount = count
          hasNewNotification = true
        else
          currentNotificationText = "No new notifications at this time."
          notificationCount = 0
          hasNewNotification = false
        end
      end
    else
      currentNotificationText = "No new notifications at this time."
      notificationCount = 0
      hasNewNotification = false
    end
    if callback then callback() end
  end)
end

local function dialogTextColor()
  return Color.parseColor(currentThemeColor == "#E0E0E0" and "#000000" or "#FFFFFF")
end

local function showNotificationDialog()
  local notifDlg = LuaDialog(context)
  notifDlg.setTitle("Notifications")

  local txtView = TextView(context)
  txtView.setText(currentNotificationText)
  txtView.setTextSize(16)
  txtView.setPadding(30, 20, 30, 20)
  txtView.setTextColor(dialogTextColor())
  txtView.setFocusable(true)

  notifDlg.setView(txtView)
  notifDlg.setButton("OK", DialogInterface.OnClickListener{
    onClick = function(dialog, which)
      hasNewNotification = false
      notificationCount = 0
      local editor = prefs.edit()
      editor.putString("last_seen_notification", currentNotificationText)
      editor.apply()
      dialog.dismiss()
      showScreen(4, true)
    end
  })
  notifDlg.show()
end

-- ---------------------------------------------------------------------------
-- Gemini key validation and TTS preview
-- ---------------------------------------------------------------------------
local function validateGeminiApiKey(apiKey, callback)
  local testUrl = "https://generativelanguage.googleapis.com/v1beta/models?key=" .. apiKey
  Http.get(testUrl, nil, "UTF-8", {}, function(code, body)
    if code == 200 and body and not body:find('"error"') then
      callback(true, "Valid Key")
    else
      callback(false, "Your API Key is not valid. Please check your API Key.")
    end
  end)
end

local function writeWavHeader(outStream, totalAudioLen)
  local sampleRate = 24000
  local channels = 1
  local bitsPerSample = 16
  local byteRate = sampleRate * channels * (bitsPerSample // 8)
  local blockAlign = channels * (bitsPerSample // 8)
  local totalSize = totalAudioLen + 36

  local function getBytes(val)
    return { val & 0xff, (val >> 8) & 0xff, (val >> 16) & 0xff, (val >> 24) & 0xff }
  end

  local totalSizeB = getBytes(totalSize)
  local sampleRateB = getBytes(sampleRate)
  local byteRateB = getBytes(byteRate)
  local dataLenB = getBytes(totalAudioLen)

  local header = {
    0x52, 0x49, 0x46, 0x46,
    totalSizeB[1], totalSizeB[2], totalSizeB[3], totalSizeB[4],
    0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20,
    0x10, 0x00, 0x00, 0x00, 0x01, 0x00,
    channels & 0xff, (channels >> 8) & 0xff,
    sampleRateB[1], sampleRateB[2], sampleRateB[3], sampleRateB[4],
    byteRateB[1], byteRateB[2], byteRateB[3], byteRateB[4],
    blockAlign & 0xff, (blockAlign >> 8) & 0xff,
    bitsPerSample & 0xff, (bitsPerSample >> 8) & 0xff,
    0x64, 0x61, 0x74, 0x61,
    dataLenB[1], dataLenB[2], dataLenB[3], dataLenB[4]
  }

  for i = 1, #header do outStream.write(header[i]) end
end

local function stopPreviewAudio(playBtn)
  if mediaPlayer ~= nil then
    pcall(function()
      if isPlaying then mediaPlayer.stop() end
      mediaPlayer.release()
    end)
    mediaPlayer = nil
    isPlaying = false
    if playBtn then runOnUi(function() playBtn.setText("Test Speech") end) end
  end
end

local function playPreviewAudio(path, playBtn)
  stopPreviewAudio(nil)
  mediaPlayer = MediaPlayer()
  local ok = pcall(function()
    mediaPlayer.setDataSource(path)
    mediaPlayer.prepare()

    if Build.VERSION.SDK_INT >= 23 then
      local speedVal = tonumber(selectedRate:match("([%d%.]+)")) or 1.0
      local rawPitch = tonumber(selectedPitch) or 50
      local pitchVal = 0.5 + (rawPitch / 100.0)

      local params = PlaybackParams()
      params.setSpeed(speedVal)
      params.setPitch(pitchVal)
      mediaPlayer.setPlaybackParams(params)
    end

    mediaPlayer.start()
    isPlaying = true
    runOnUi(function() if playBtn then playBtn.setText("STOP PREVIEW") end end)

    mediaPlayer.setOnCompletionListener({
      onCompletion = function(mp)
        isPlaying = false
        runOnUi(function() if playBtn then playBtn.setText("Test Speech") end end)
        pcall(function() mp.release() end)
        mediaPlayer = nil
      end
    })
  end)
  if not ok then
    showToast("Could not play the preview audio.")
    stopPreviewAudio(playBtn)
  end
end

local function generateTTSPreview(playBtn)
  if isPlaying then
    stopPreviewAudio(playBtn)
    return
  end

  if savedGeminiApiKey == "" then
    showToast("Please enter your Gemini API Key first!")
    return
  end

  local previewText = "Thank you for using Excellent Weather Checker."
  local apiUrl = "https://generativelanguage.googleapis.com/v1beta/models/" .. CURRENT_MODEL .. ":generateContent?key=" .. savedGeminiApiKey

  local requestBody = {
    contents = { { parts = { { text = previewText } } } },
    generationConfig = {
      responseModalities = {"AUDIO"},
      speechConfig = { voiceConfig = { prebuiltVoiceConfig = { voiceName = selectedVoice } } }
    }
  }

  runOnUi(function()
    playBtn.setEnabled(false)
    playBtn.setText("LOADING...")
  end)

  Http.post(apiUrl, cjson.encode(requestBody), nil, "UTF-8", {["Content-Type"] = "application/json"}, function(code, content)
    runOnUi(function() playBtn.setEnabled(true) end)
    if code == 200 and content then
      local ok, data = pcall(cjson.decode, content)
      if ok and type(data) == "table" and data.candidates and #data.candidates > 0 then
        local candidate = data.candidates[1]
        local base64Audio = nil
        if candidate.content and candidate.content.parts then
          for i = 1, #candidate.content.parts do
            local part = candidate.content.parts[i]
            if part.inlineData and part.inlineData.data then
              base64Audio = part.inlineData.data
              break
            end
          end
        end
        if base64Audio then
          local audioBytes = Base64.decode(base64Audio, Base64.NO_WRAP)
          local tempPath = context.getCacheDir().getPath() .. "/tts_preview.wav"
          local fos = FileOutputStream(File(tempPath))
          writeWavHeader(fos, #audioBytes)
          fos.write(audioBytes)
          fos.close()
          previewAudioPath = tempPath
          playPreviewAudio(previewAudioPath, playBtn)
          return
        end
      end
      showToast("Error processing audio response.")
      runOnUi(function() playBtn.setText("Test Speech") end)
    else
      showToast("API Error Code: " .. tostring(code))
      runOnUi(function() playBtn.setText("Test Speech") end)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Unit conversions
-- ---------------------------------------------------------------------------
local function convertTemperature(celsius, unit)
  if not celsius then return "N/A" end
  if unit == "Fahrenheit (°F)" then
    return string.format("%.1f °F", (celsius * 9 / 5) + 32)
  elseif unit == "Kelvin (K)" then
    return string.format("%.1f K", celsius + 273.15)
  else
    return string.format("%.1f °C", celsius)
  end
end

local beaufortLimits = { 0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7 }
local beaufortNames = {
  "Calm", "Light air", "Light breeze", "Gentle breeze", "Moderate breeze",
  "Fresh breeze", "Strong breeze", "Near gale", "Gale", "Strong gale",
  "Storm", "Violent storm", "Hurricane force"
}

local function toBeaufort(ms)
  local force = 0
  for i, limit in ipairs(beaufortLimits) do
    if ms >= limit then force = i end
  end
  return string.format("Force %d, %s", force, beaufortNames[force + 1])
end

local function convertWindSpeed(ms, unit)
  if not ms then return "N/A" end
  if unit == "Kilometers per hour (km/h)" then
    return string.format("%.1f km/h", ms * 3.6)
  elseif unit == "Miles per hour (mph)" then
    return string.format("%.1f mph", ms * 2.23694)
  elseif unit == "Knots" then
    return string.format("%.1f knots", ms * 1.94384)
  elseif unit == "Beaufort" then
    return toBeaufort(ms)
  else
    return string.format("%.1f m/s", ms)
  end
end

local function convertPressure(hpa, unit)
  if not hpa then return "N/A" end
  if unit == "Atmosphere (atm)" then
    return string.format("%.3f atm", hpa / 1013.25)
  elseif unit == "Inches of Mercury (inHg)" then
    return string.format("%.2f inHg", hpa * 0.02953)
  elseif unit == "Millimeters of Mercury (mmHg)" then
    return string.format("%.1f mmHg", hpa * 0.750062)
  elseif unit == "Millibars (mbar)" or unit == "mbar" then
    return string.format("%.0f mbar", hpa)
  else
    return string.format("%.0f hPa", hpa)
  end
end

local function convertVisibility(meters, unit)
  if not meters then return "N/A" end
  if unit == "Kilometers" then
    return string.format("%.1f km", meters / 1000)
  elseif unit == "Miles" then
    return string.format("%.1f miles", meters / 1609.34)
  else
    return string.format("%.0f meters", meters)
  end
end

local function convertPrecipitation(mm, unit)
  if not mm then return "N/A" end
  if unit == "Centimeters (cm)" then
    return string.format("%.2f cm", mm / 10)
  elseif unit == "Inches (in)" then
    return string.format("%.2f in", mm / 25.4)
  else
    return string.format("%.1f mm", mm)
  end
end

local compassNames = {
  "North", "North-Northeast", "Northeast", "East-Northeast",
  "East", "East-Southeast", "Southeast", "South-Southeast",
  "South", "South-Southwest", "Southwest", "West-Southwest",
  "West", "West-Northwest", "Northwest", "North-Northwest"
}

local function degreesToCompass(deg)
  if not deg then return "N/A" end
  local idx = math.floor(((deg % 360) / 22.5) + 0.5) % 16
  return compassNames[idx + 1]
end

local wmoCodes = {
  [0] = "Clear sky", [1] = "Mainly clear", [2] = "Partly cloudy", [3] = "Overcast",
  [45] = "Fog", [48] = "Freezing fog",
  [51] = "Light drizzle", [53] = "Moderate drizzle", [55] = "Dense drizzle",
  [56] = "Light freezing drizzle", [57] = "Dense freezing drizzle",
  [61] = "Slight rain", [63] = "Moderate rain", [65] = "Heavy rain",
  [66] = "Light freezing rain", [67] = "Heavy freezing rain",
  [71] = "Slight snowfall", [73] = "Moderate snowfall", [75] = "Heavy snowfall",
  [77] = "Snow grains",
  [80] = "Slight rain showers", [81] = "Moderate rain showers", [82] = "Violent rain showers",
  [85] = "Slight snow showers", [86] = "Heavy snow showers",
  [95] = "Thunderstorm", [96] = "Thunderstorm with slight hail", [99] = "Thunderstorm with heavy hail"
}

local function describeWeatherCode(code)
  code = num(code)
  if not code then return nil end
  return wmoCodes[math.floor(code)] or "Unknown conditions"
end

local function describeUv(uv)
  if not uv then return "N/A" end
  if uv < 3 then return "Low"
  elseif uv < 6 then return "Moderate"
  elseif uv < 8 then return "High"
  elseif uv < 11 then return "Very high"
  else return "Extreme" end
end

local function describeAqi(aqi)
  if not aqi then return "N/A" end
  if aqi <= 50 then return "Good"
  elseif aqi <= 100 then return "Moderate"
  elseif aqi <= 150 then return "Unhealthy for sensitive groups"
  elseif aqi <= 200 then return "Unhealthy"
  elseif aqi <= 300 then return "Very unhealthy"
  else return "Hazardous" end
end

-- ---------------------------------------------------------------------------
-- Time formatting (UPDATED FOR FIXED FORMATTING)
-- ---------------------------------------------------------------------------
local function formatClock(h, m, formatType)
  if not h or not m then return "" end
  if formatType == "12 Hours" then
    local period = h >= 12 and "PM" or "AM"
    local h12 = h % 12
    if h12 == 0 then h12 = 12 end
    return string.format("%02d:%02d %s", h12, m, period)
  elseif formatType == "Military Time" then
    return string.format("%02d%02d", h, m)
  elseif formatType == "ISO Format" then
    return string.format("%02d:%02d:00", h, m)
  else -- 24 Hours
    return string.format("%02d:%02d", h, m)
  end
end

local function getFormattedTime(formatType)
  if formatType == "ISO Format" then
    return os.date("%Y-%m-%dT%H:%M:%S")
  end
  return formatClock(tonumber(os.date("%H")), tonumber(os.date("%M")), formatType)
end

local function formatIsoClock(isoString, formatType)
  local s = str(isoString)
  if not s then return nil end
  local h, m = s:match("T(%d+):(%d+)")
  if not h or not m then return nil end
  return formatClock(tonumber(h), tonumber(m), formatType)
end

-- ---------------------------------------------------------------------------
-- Location + Open-Meteo
-- ---------------------------------------------------------------------------
local function needsAirQuality()
  return currentWeatherReport.air_quality or alertSettings.air_quality
end

local function fetchLocationAndWeather(callback)
  local locationManager = context.getSystemService(Context.LOCATION_SERVICE)
  local isGpsEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
  local isNetworkEnabled = locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)

  if not isGpsEnabled and not isNetworkEnabled then
    fetchedRealLocation = "Something went wrong"
    currentWeatherData = nil
    if callback then callback() end
    return
  end

  isFetchingData = true
  local isCompleted = false
  local gotLocation = false
  local listener = nil
  local timeoutRunnable = nil

  local function cancelTimeout()
    if timeoutRunnable then
      mainHandler.removeCallbacks(timeoutRunnable)
      timeoutRunnable = nil
    end
  end

  local function armTimeout(ms, fn)
    cancelTimeout()
    timeoutRunnable = Runnable{ run = fn }
    mainHandler.postDelayed(timeoutRunnable, ms)
  end

  local function stopUpdates()
    if listener then
      pcall(function() locationManager.removeUpdates(listener) end)
    end
  end

  local function finishProcess(success)
    if isCompleted then return end
    isCompleted = true
    cancelTimeout()
    stopUpdates()
    isFetchingData = false
    if not success then
      fetchedRealLocation = "Something went wrong"
      currentWeatherData = nil
    end
    if callback then callback() end
  end

  local function fetchAirQuality(lat, lng)
    local url = string.format("%s?latitude=%.4f&longitude=%.4f&current=us_aqi,pm10,pm2_5&timezone=auto", AIR_QUALITY_URL, lat, lng)
    Http.get(url, nil, "UTF-8", {}, function(code, content)
      if isCompleted then return end
      if code == 200 and content then
        local ok, d = pcall(cjson.decode, content)
        if ok and type(d) == "table" and type(d.current) == "table" and currentWeatherData then
          currentWeatherData.aqi = {
            us_aqi = num(d.current.us_aqi),
            pm25 = num(d.current.pm2_5),
            pm10 = num(d.current.pm10)
          }
        end
      end
      finishProcess(true)
    end)
  end

  local function fetchWeather(lat, lng)
    local url = string.format(
      "%s?latitude=%.4f&longitude=%.4f" ..
      "&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day" ..
      "&hourly=temperature_2m,weather_code,precipitation_probability,dew_point_2m,visibility,uv_index" ..
      "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max" ..
      "&timezone=auto&wind_speed_unit=ms&temperature_unit=celsius&precipitation_unit=mm&forecast_days=10",
      WEATHER_URL, lat, lng)

    Http.get(url, nil, "UTF-8", {}, function(code, content)
      if isCompleted then return end
      if code == 200 and content then
        local ok, d = pcall(cjson.decode, content)
        if ok and type(d) == "table" and type(d.current) == "table" then
          local hour = tonumber(tostring(d.current.time or ""):match("T(%d+)")) or tonumber(os.date("%H"))
          currentWeatherData = {
            cur = d.current,
            hourly = type(d.hourly) == "table" and d.hourly or {},
            daily = type(d.daily) == "table" and d.daily or {},
            hourIdx = hour + 1,
            aqi = nil
          }
          if needsAirQuality() then
            fetchAirQuality(lat, lng)
          else
            finishProcess(true)
          end
          return
        end
      end
      finishProcess(false)
    end)
  end

  local function fetchAddressThenWeather(lat, lng)
    armTimeout(25000, function() finishProcess(false) end)
    local mapUrl = string.format("https://nominatim.openstreetmap.org/reverse?format=json&accept-language=en&lat=%.6f&lon=%.6f", lat, lng)
    Http.get(mapUrl, nil, "UTF-8", {["User-Agent"] = "ExcellentWeatherChecker/1.0"}, function(code, content)
      if isCompleted then return end

      local resolved = nil
      if code == 200 and content then
        local ok, d = pcall(cjson.decode, content)
        if ok and type(d) == "table" and type(d.address) == "table" then
          local a = d.address
          local street = str(a.road) or str(a.suburb) or str(a.neighbourhood) or str(a.village)
          local town = str(a.city) or str(a.town) or str(a.village) or str(a.county)
          if street and town and street ~= town then
            resolved = street .. ", " .. town
          elseif town then
            resolved = town
          elseif street then
            resolved = street
          end
        end
      end
      fetchedRealLocation = resolved or string.format("%.4f, %.4f", lat, lng)
      fetchWeather(lat, lng)
    end)
  end

  local function onLocation(loc)
    if isCompleted or gotLocation or not loc then return end

    if type(loc) == "userdata" and pcall(function() return loc.get(0) end) then
      local ok, firstLoc = pcall(function() return loc.get(0) end)
      if ok and firstLoc then
        loc = firstLoc
      end
    end

    local okLat, lat = pcall(function() return loc.getLatitude() end)
    local okLng, lng = pcall(function() return loc.getLongitude() end)

    if okLat and okLng and lat and lng then
      gotLocation = true
      stopUpdates()
      fetchAddressThenWeather(lat, lng)
    else
      finishProcess(false)
    end
  end

  local function getLastKnown()
    local best = nil
    for _, provider in ipairs({ LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER }) do
      local ok, l = pcall(function() return locationManager.getLastKnownLocation(provider) end)
      if ok and l and (not best or l.getTime() > best.getTime()) then best = l end
    end
    return best
  end

  armTimeout(10000, function()
    if gotLocation then return end
    local last = getLastKnown()
    if last then
      onLocation(last)
    else
      finishProcess(false)
    end
  end)

  listener = LocationListener{
    onLocationChanged = function(location)
      if location then
        if pcall(function() return location.size() end) and location.size() > 0 then
          onLocation(location.get(0))
        else
          onLocation(location)
        end
      end
    end,
    onStatusChanged = function(provider, status, extras) end,
    onProviderEnabled = function(provider) end,
    onProviderDisabled = function(provider) end
  }

  local okReq = pcall(function()
    if isGpsEnabled then locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000, 0, listener) end
    if isNetworkEnabled then locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000, 0, listener) end
  end)
  if not okReq then
    local last = getLastKnown()
    if last then onLocation(last) else finishProcess(false) end
  end
end

-- ---------------------------------------------------------------------------
-- Settings Revert Helpers
-- ---------------------------------------------------------------------------
local function hasGeneralSettingsChanged()
  return tempSelectedColorName ~= currentSelectedColorName or
         tempSoundEnabled ~= currentSoundEnabled or
         tempSoundVolume ~= currentSoundVolume or
         tempDetectLocationEnabled ~= currentDetectLocationEnabled or
         tempAutoReportEnabled ~= currentAutoReportEnabled or
         tempAutoReportInterval ~= currentAutoReportInterval or
         tempForecastType ~= currentForecastType or
         tempTimeFormat ~= currentTimeFormat
end

local function hasUnitSettingsChanged()
  return tempTempUnit ~= currentTempUnit or
         tempVisUnit ~= currentVisUnit or
         tempWindUnit ~= currentWindUnit or
         tempPressUnit ~= currentPressUnit or
         tempPrecipUnit ~= currentPrecipUnit
end

local function hasReportSettingsChanged()
  for k, v in pairs(tempWeatherReport) do
    if v ~= currentWeatherReport[k] then return true end
  end
  return false
end

local function hasTtsSettingsChanged()
  return selectedVoice ~= currentVoice or selectedRate ~= currentRate or
         selectedPitch ~= currentPitch or selectedInflection ~= currentInflection
end

local function hasAlertSettingsChanged()
  for k, v in pairs(tempAlertSettings) do
    if v ~= alertSettings[k] then return true end
  end
  return false
end

local function revertGeneral()
  tempSelectedColorName = currentSelectedColorName
  tempSoundEnabled = currentSoundEnabled
  tempSoundVolume = currentSoundVolume
  tempDetectLocationEnabled = currentDetectLocationEnabled
  tempAutoReportEnabled = currentAutoReportEnabled
  tempAutoReportInterval = currentAutoReportInterval
  tempForecastType = currentForecastType
  tempTimeFormat = currentTimeFormat
end

local function revertUnits()
  tempTempUnit = currentTempUnit
  tempVisUnit = currentVisUnit
  tempWindUnit = currentWindUnit
  tempPressUnit = currentPressUnit
  tempPrecipUnit = currentPrecipUnit
end

local function revertReport()
  for k, v in pairs(currentWeatherReport) do tempWeatherReport[k] = v end
end

local function revertTts()
  selectedVoice, selectedRate, selectedPitch, selectedInflection =
    currentVoice, currentRate, currentPitch, currentInflection
end

local function revertAlerts()
  for k, v in pairs(alertSettings) do tempAlertSettings[k] = v end
end

local revertByScreen = {
  [9] = revertGeneral, [11] = revertUnits, [12] = revertReport,
  [13] = revertTts, [14] = revertAlerts
}

-- ---------------------------------------------------------------------------
-- Report building
-- ---------------------------------------------------------------------------
local function hourly(wd, name, idx)
  if type(wd) ~= "table" or type(wd.hourly) ~= "table" then return nil end
  local arr = wd.hourly[name]
  if type(arr) ~= "table" then return nil end
  return num(arr[idx])
end

local function daily(wd, name, idx)
  if type(wd) ~= "table" or type(wd.daily) ~= "table" then return nil end
  local arr = wd.daily[name]
  if type(arr) ~= "table" then return nil end
  return arr[idx]
end

local function getAlertLines(wd)
  local alerts = {}
  if not wd or not wd.cur then return alerts end
  local c = wd.cur
  local code = num(c.weather_code)
  local temp = num(c.temperature_2m)
  local feels = num(c.apparent_temperature)
  local gust = num(c.wind_gusts_10m) or num(c.wind_speed_10m)
  local precip = num(c.precipitation)

  local function add(text) table.insert(alerts, "Alert: " .. text) end

  if alertSettings.thunderstorm and code and code >= 95 then
    add("Thunderstorm conditions in your area.")
  end
  if alertSettings.severe and ((code and (code == 96 or code == 99)) or (gust and gust >= 24.5)) then
    add("Severe weather conditions in your area.")
  end
  if alertSettings.heavy_rain and ((code and (code == 65 or code == 67 or code == 82)) or (precip and precip >= 7.5)) then
    add("Heavy rain in your area.")
  end
  if alertSettings.snow and code and (code == 71 or code == 73 or code == 75 or code == 77 or code == 85 or code == 86) then
    add("Snowfall in your area.")
  end
  if alertSettings.heat and ((temp and temp >= 40) or (feels and feels >= 41)) then
    add("Extreme heat warning.")
  end
  if alertSettings.cold and ((temp and temp <= -10) or (feels and feels <= -15)) then
    add("Extreme cold warning.")
  end
  if alertSettings.wind and gust and gust >= 17.5 then
    add("High wind warning.")
  end
  if alertSettings.cyclone and gust and gust >= 32.7 then
    add("Hurricane force winds detected, possible cyclone conditions.")
  end
  if alertSettings.fog and code and (code == 45 or code == 48) then
    add("Fog reducing visibility.")
  end
  if alertSettings.air_quality and wd.aqi and wd.aqi.us_aqi and wd.aqi.us_aqi >= 151 then
    add("Unhealthy air quality.")
  end
  return alerts
end

local function getForecastLines(wd)
  local lines = {}
  if not wd then return lines end
  local ftype = currentForecastType
  local hoursMap = { ["Hourly forecast"] = 1, ["12 hours forecast"] = 12, ["24 hours forecast"] = 24 }
  local daysMap = { ["3 days forecast"] = 3, ["7 days forecast"] = 7, ["10 days forecast"] = 10 }

  if hoursMap[ftype] and wd.hourly then
    table.insert(lines, ftype .. ":")
    for i = 1, hoursMap[ftype] do
      local idx = (wd.hourIdx or 1) + i
      local t = hourly(wd, "temperature_2m", idx)
      if not t then break end
      local timeArr = wd.hourly.time
      local label = timeArr and formatIsoClock(timeArr[idx], currentTimeFormat) or ("+" .. i .. "h")
      local parts = { convertTemperature(t, currentTempUnit) }
      local cond = describeWeatherCode(hourly(wd, "weather_code", idx))
      if cond then table.insert(parts, cond) end
      local pp = hourly(wd, "precipitation_probability", idx)
      if pp then table.insert(parts, string.format("rain chance %.0f%%", pp)) end
      table.insert(lines, label .. ": " .. table.concat(parts, ", "))
    end
  elseif daysMap[ftype] and wd.daily then
    table.insert(lines, ftype .. ":")
    local dates = wd.daily.time
    for i = 1, daysMap[ftype] do
      local hi = num(daily(wd, "temperature_2m_max", i))
      local lo = num(daily(wd, "temperature_2m_min", i))
      if not hi or not lo then break end
      local label = "Day " .. i
      if dates and str(dates[i]) then
        local y, m, d = dates[i]:match("(%d+)-(%d+)-(%d+)")
        if y and m and d then
          label = os.date("%A", os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })) .. " " .. string.format("%02d-%02d-%04d", tonumber(d), tonumber(m), tonumber(y))
        end
      end
      local parts = {}
      local cond = describeWeatherCode(daily(wd, "weather_code", i))
      if cond then table.insert(parts, cond) end
      table.insert(parts, "high " .. convertTemperature(hi, currentTempUnit))
      table.insert(parts, "low " .. convertTemperature(lo, currentTempUnit))
      local pp = num(daily(wd, "precipitation_probability_max", i))
      if pp then table.insert(parts, string.format("rain chance %.0f%%", pp)) end
      table.insert(lines, label .. ": " .. table.concat(parts, ", "))
    end
  end
  return lines
end

local function getWeatherLines()
  if not currentDetectLocationEnabled then
    return { "Location detection is turned off. Turn on Detect My Location in General Settings." }, true
  end
  if not currentWeatherData or not currentWeatherData.cur then
    return { "Something went wrong" }, true
  end

  local wd = currentWeatherData
  local c = wd.cur
  local r = currentWeatherReport
  local idx = wd.hourIdx or 1
  local lines = {}
  local function add(text) table.insert(lines, text) end

  if r.date then add("Date: " .. os.date("%d-%m-%Y")) end
  if r.time then add("Time: " .. getFormattedTime(currentTimeFormat)) end
  if r.location then add("Location: " .. fetchedRealLocation) end

  if r.conditions then
    local cond = describeWeatherCode(c.weather_code)
    if cond then add("Conditions: " .. cond) end
  end
  if r.temperature and num(c.temperature_2m) then
    add("Temperature: " .. convertTemperature(num(c.temperature_2m), currentTempUnit))
  end
  if r.feels_like_temperature and num(c.apparent_temperature) then
    add("Feels Like: " .. convertTemperature(num(c.apparent_temperature), currentTempUnit))
  end
  if r.humidity and num(c.relative_humidity_2m) then
    add(string.format("Humidity: %.0f%%", num(c.relative_humidity_2m)))
  end
  if r.dew_point then
    local dp = hourly(wd, "dew_point_2m", idx)
    if dp then add("Dew Point: " .. convertTemperature(dp, currentTempUnit)) end
  end
  if r.wind_speed and num(c.wind_speed_10m) then
    add("Wind Speed: " .. convertWindSpeed(num(c.wind_speed_10m), currentWindUnit))
  end
  if r.wind_direction and num(c.wind_direction_10m) then
    local wdDeg = num(c.wind_direction_10m)
    add(string.format("Wind Direction: %s (%.0f°)", degreesToCompass(wdDeg), wdDeg))
  end
  if r.atmospheric_pressure and num(c.pressure_msl) then
    add("Atmospheric Pressure: " .. convertPressure(num(c.pressure_msl), currentPressUnit))
  end
  if r.visibility then
    local vis = hourly(wd, "visibility", idx)
    if vis then add("Visibility: " .. convertVisibility(vis, currentVisUnit)) end
  end
  if r.cloud_coverage and num(c.cloud_cover) then
    add(string.format("Cloud Coverage: %.0f%%", num(c.cloud_cover)))
  end
  if r.rain_percentage then
    local pp = hourly(wd, "precipitation_probability", idx)
    if pp then add(string.format("Rain Percentage: %.0f%%", pp)) end
  end
  if r.precipitation and num(c.precipitation) then
    add("Precipitation: " .. convertPrecipitation(num(c.precipitation), currentPrecipUnit))
  end
  if r.uv_index then
    local uv = hourly(wd, "uv_index", idx)
    if uv then add(string.format("UV Index: %.1f (%s)", uv, describeUv(uv))) end
  end
  if r.air_quality then
    if wd.aqi and wd.aqi.us_aqi then
      add(string.format("Air Quality: %.0f (%s)", wd.aqi.us_aqi, describeAqi(wd.aqi.us_aqi)))
    else
      add("Air Quality: Not available for this location")
    end
  end
  if r.sunrise_time then
    local s = formatIsoClock(daily(wd, "sunrise", 1), currentTimeFormat)
    if s then add("Sunrise: " .. s) end
  end
  if r.sunset_time then
    local s = formatIsoClock(daily(wd, "sunset", 1), currentTimeFormat)
    if s then add("Sunset: " .. s) end
  end

  if r.moonrise_time then add("Moonrise: Not available") end
  if r.moonset_time then add("Moonset: Not available") end

  if #lines == 0 then add("No details selected in settings.") end

  local alerts = getAlertLines(wd)
  if #alerts > 0 then
    for i = #alerts, 1, -1 do table.insert(lines, 1, alerts[i]) end
  end

  for _, l in ipairs(getForecastLines(wd)) do add(l) end

  return lines, false
end

-- ---------------------------------------------------------------------------
-- Auto report + share
-- ---------------------------------------------------------------------------
local function showAutoWeatherReportDialog()
  runOnUi(function()
    local autoDlg = LuaDialog(context)
    autoDlg.setTitle("Automatic Weather Update")

    local lines = getWeatherLines()
    local reportText = table.concat(lines, "\n")

    local scroll = ScrollView(context)
    local txtView = TextView(context)
    txtView.setText(reportText)
    txtView.setTextSize(16)
    txtView.setPadding(30, 20, 30, 20)
    txtView.setTextColor(dialogTextColor())
    txtView.setFocusable(true)
    scroll.addView(txtView)

    autoDlg.setView(scroll)
    autoDlg.setButton("OK", DialogInterface.OnClickListener{
      onClick = function(dialog, which) dialog.dismiss() end
    })
    autoDlg.setButton2("Copy Weather Report", DialogInterface.OnClickListener{
      onClick = function(dialog, which)
        local clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
        clipboard.setPrimaryClip(ClipData.newPlainText("Weather Report", reportText))
        showToast("Weather report copied to clipboard!")
        dialog.dismiss()
      end
    })
    autoDlg.show()
  end)
end

setupAutoReportTimer = function()
  if autoReportRunnable then
    mainHandler.removeCallbacks(autoReportRunnable)
    autoReportRunnable = nil
  end

  if currentAutoReportEnabled then
    local amount = tonumber(currentAutoReportInterval:match("(%d+)")) or 5
    local minutes = currentAutoReportInterval:find("hour") and (amount * 60) or amount
    local intervalMs = minutes * 60 * 1000

    autoReportRunnable = Runnable({
      run = function()
        if not currentAutoReportEnabled then return end
        if isFetchingData then
          setupAutoReportTimer()
          return
        end
        fetchLocationAndWeather(function()
          showAutoWeatherReportDialog()
          setupAutoReportTimer()
        end)
      end
    })
    mainHandler.postDelayed(autoReportRunnable, intervalMs)
  end
end

local function shareWeatherReport()
  local lines = getWeatherLines()
  local intent = Intent(Intent.ACTION_SEND)
  intent.setType("text/plain")
  intent.putExtra(Intent.EXTRA_TEXT, table.concat(lines, "\n"))

  local chooser = Intent.createChooser(intent, "Share Weather Report via")
  chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

  if dlg then
    stopPreviewAudio(nil)
    dlg.dismiss()
    dlg = nil
  end
  navStack = {}
  showInlineWeather = false

  context.startActivity(chooser)
end

-- ---------------------------------------------------------------------------
-- UI definitions
-- ---------------------------------------------------------------------------
windows[1] = {
  title = "Welcome To Excellent Weather Checker",
  elements = {
    { type = "title" },
    { type = "textview", text = "Welcome to the ultimate Weather experience!" },
    { type = "textview", text = "This extension is your ultimate weather companion." },
    { type = "textview", text = "This extension brings you live, hyper-accurate weather forecasts." },
    { type = "textview", text = "We have integrated advanced features to ensure seamless navigation for visually challenged persons." },
    { type = "textview", text = "Optimize your daily schedule seamlessly with the Excellent Weather Checker extension." },
    { type = "button", label = "Exit", targetId = 0 },
    { type = "button", label = "Log In", targetId = 2 }
  }
}

windows[2] = {
  title = "Registration",
  elements = {
    { type = "title" },
    { type = "textview", text = "Remember only english alphabets are allowed" },
    { type = "edittext", hint = "Enter your name (required)", id = "username_input" },
    { type = "button", label = "Back To Previous Page", goBackBtn = true },
    { type = "button", label = "Next", isRegistrationContinueBtn = true }
  }
}

windows[15] = {
  title = "Enter Google Gemini API Key",
  elements = {
    { type = "title" },
    { type = "textview", text = "Please enter your Google Gemini API Key for TTS feature." },
    { type = "edittext", hint = "Enter your Google Gemini API Key", id = "gemini_api_key_input" },
    { type = "button", label = "Back", goBackBtn = true },
    { type = "button", label = "Continue", isApiKeyContinueBtn = true }
  }
}

windows[3] = {
  title = "Setup Complete",
  elements = {
    { type = "title" },
    { type = "textview", isWelcome = true, text = "" },
    { type = "button", label = "Finish", targetId = 4 }
  }
}

windows[4] = {
  title = "Excellent Weather Checker",
  elements = {
    { type = "title" },
    { type = "textview", text = "Created By Mahadeesh" },
    { type = "greeting" },
    { type = "button", label = "User Guide", targetId = 5 },
    { type = "button", label = "About & Credits", targetId = 6 },
    { type = "button", label = "Settings", targetId = 7 },
    { type = "button", isNotificationBtn = true },
    { type = "button", isDynamicWeatherBtn = true },
    { type = "button", isRefreshBtn = true },
    { type = "weather_report" },
    { type = "textview", isModeLabel = true, text = "" },
    { type = "button", label = "Exit", targetId = 0 }
  }
}

windows[5] = {
  title = "User Guide",
  elements = {
    { type = "title" },
    { type = "textview", text = "Welcome to the Complete Step-by-Step User Guide! Let us walk you through every room and feature of this app:" },
    { type = "textview", text = "--- STEP 1: INITIAL SETUP & USERNAME ---" },
    { type = "textview", text = "When you open this extension for the first time, Page 1 gives you a quick introduction. Tap 'Log In' to reach Page 2, where you type your username into the edit box. Pressing 'Next' saves your name and takes you to the Gemini API key page. After the key is validated you reach Page 3 (Setup Complete). Tap 'Finish' to jump right onto the Main Dashboard." },
    { type = "textview", text = "--- STEP 2: MAIN DASHBOARD & GREETINGS ---" },
    { type = "textview", text = "At the top of the Main Dashboard, you will hear a time-sensitive greeting (Good Morning, Good Afternoon, or Good Evening) followed by your saved username. Below the greeting, you have these options: User Guide, About & Credits, Settings, Notifications and Check Weather." },
    { type = "textview", text = "--- STEP 3: CHECKING LIVE WEATHER ---" },
    { type = "textview", text = "Tap the 'Check Weather' button on the dashboard. A quick toast message 'Please wait...' will pop up while the app accesses your device GPS location, fetches address details from OpenStreetMap and live weather data from Open-Meteo. Once fetched, all selected weather parameters (Temperature, Humidity, Wind, Location, etc.) appear on your screen line by line, perfectly formatted for screen readers, followed by your chosen forecast." },
    { type = "textview", text = "--- STEP 4: SHARING AND REFRESHING YOUR WEATHER REPORT ---" },
    { type = "textview", text = "After fetching the weather, the 'Check Weather' button changes into 'Share Weather Report'. Tapping it opens your Android sharing menu so you can send the full text report via WhatsApp, SMS, Email, or social apps. Use 'Refresh Weather' to fetch fresh data." },
    { type = "textview", text = "--- STEP 5: EXPLORING GENERAL SETTINGS ---" },
    { type = "textview", text = "In Main Dashboard -> Settings -> General Settings, you can configure overall app behavior:" },
    { type = "textview", text = "• Change Username: Tap this button to update your profile name anytime." },
    { type = "textview", text = "• Automatic Weather Report Interval: Check this box to enable recurring automatic updates, then pick your interval (from 5 minutes up to 1 hour)." },
    { type = "textview", text = "• Sound Effects & Volume: Enable or disable sound effects and adjust volume with the slider." },
    { type = "textview", text = "• Detect My Location: Keep this checked to auto-detect location via GPS. Unchecking it turns off location fetching." },
    { type = "textview", text = "• Select Colour: Change the entire screen background color (Blue, Green, Red, Black, White, etc.)." },
    { type = "textview", text = "• Time Format & Forecast Type: Choose between 12-Hour, 24-Hour, Military, or ISO time formats, and set your desired forecast period (next hour, 12 or 24 hours, or 3, 7 or 10 days)." },
    { type = "textview", text = "--- STEP 6: CUSTOMIZING UNIT SETTINGS ---" },
    { type = "textview", text = "In Main Dashboard -> Settings -> Unit Settings, tailor all scientific units to your preference:" },
    { type = "textview", text = "• Temperature: Switch between Celsius (°C), Fahrenheit (°F), and Kelvin (K)." },
    { type = "textview", text = "• Wind Speed: Select km/h, m/s, mph, Knots, or Beaufort scale." },
    { type = "textview", text = "• Atmospheric Pressure: Select hPa, atm, inHg, mmHg, or mbar." },
    { type = "textview", text = "• Visibility & Precipitation: Choose between Kilometers, Miles, Meters, Millimeters, Inches, or Centimeters." },
    { type = "textview", text = "--- STEP 7: WEATHER REPORT CONTENTS SETTINGS ---" },
    { type = "textview", text = "In Main Dashboard -> Settings -> Weather Report Contents Settings, you have full control over what goes into your weather report! Simply check or uncheck individual items (Air Quality, Atmospheric Pressure, Cloud Coverage, Conditions, Date, Dew Point, Feels Like, Humidity, Location, Precipitation, Sunrise/Sunset, Rain %, Temperature, Time, UV Index, Visibility, Wind Speed & Direction). Only the parameters you select will be displayed. Moonrise and moonset are not provided by the weather service and will show as not available." },
    { type = "textview", text = "--- STEP 8: TTS AND ALERT SETTINGS ---" },
    { type = "textview", text = "TTS Settings lets you choose the Gemini voice, speech rate, pitch and inflection, and test them. Alerts And Announcement Settings lets you pick which weather alerts appear at the top of your report." },
    { type = "textview", text = "--- STEP 9: SAVING OR CANCELING CHANGES ---" },
    { type = "textview", text = "In every settings screen, tap the 'Save' button at the bottom to store your choices. If you change your mind, tap 'Cancel' to restore your previous settings without saving." },
    { type = "button", label = "Got It", goBackBtn = true }
  }
}

windows[6] = {
  title = "About & Credits",
  elements = {
    { type = "title" },
    { type = "textview", text = "Here are the names of all those who helped make this project a success" },
    { type = "textview", text = "Developed By:" },
    { type = "textview", text = "Mahadeesh" },
    { type = "textview", text = "Helped By:" },
    { type = "textview", text = "Moosa Zaib" },
    { type = "textview", text = "Special Thanks To:" },
    { type = "textview", text = "Sujan Rai" },
    { type = "button", label = "Okay", goBackBtn = true }
  }
}

windows[7] = {
  title = "Settings",
  elements = {
    { type = "title" },
    { type = "button", label = "General Settings", targetId = 9 },
    { type = "button", label = "Unit Settings", targetId = 11 },
    { type = "button", label = "Weather Report Contents Settings", targetId = 12 },
    { type = "button", label = "TTS Settings", targetId = 13 },
    { type = "button", label = "Alerts And Announcement Settings", targetId = 14 },
    { type = "button", label = "Back", goBackBtn = true }
  }
}

windows[9] = {
  title = "General Settings",
  elements = {
    { type = "title" },
    { type = "button", label = "Change Username", targetId = 10 },
    { type = "checkbox", label = "Automatic weather report interval", field = "auto_report" },
    { type = "combobox", label = "Select interval", options = "5 minutes, 10 minutes, 15 minutes, 20 minutes, 25 minutes, 30 minutes, 35 minutes, 40 minutes, 45 minutes, 50 minutes, 55 minutes, 1 hour", unitType = "interval" },
    { type = "checkbox", label = "Enable Sound Effects", field = "sound" },
    { type = "slider", label = "Sound Effects Volume" },
    { type = "checkbox", label = "Detect My Location", field = "detect_location" },
    { type = "combobox", label = "Select Colour" },
    { type = "combobox", label = "Select Time Format", options = "12 Hours, 24 Hours, Military Time, ISO Format", unitType = "timeformat" },
    { type = "combobox", label = "Select forecast type", options = "Hourly forecast, 12 hours forecast, 24 hours forecast, 3 days forecast, 7 days forecast, 10 days forecast", unitType = "forecast" },
    { type = "button", label = "Cancel", isCancelBtn = true },
    { type = "button", label = "Save", isSaveBtn = true }
  }
}

windows[10] = {
  title = "Enter your new user name",
  elements = {
    { type = "title" },
    { type = "edittext", hint = "Enter your new user name here", id = "new_username_input" },
    { type = "button", label = "Cancel", goBackBtn = true },
    { type = "button", label = "Update Username", isUpdateUserBtn = true }
  }
}

windows[11] = {
  title = "Unit Settings",
  elements = {
    { type = "title" },
    { type = "combobox", label = "Select Atmospheric Pressure Unit", options = "Atmosphere (atm), Hectopascals (hPa), Inches of Mercury (inHg), Millimeters of Mercury (mmHg), Millibars (mbar)", unitType = "press" },
    { type = "combobox", label = "Select Precipitation Unit", options = "Centimeters (cm), Inches (in), Millimeters (mm)", unitType = "precip" },
    { type = "combobox", label = "Select Temperature Unit", options = "Celsius (°C), Fahrenheit (°F), Kelvin (K)", unitType = "temp" },
    { type = "combobox", label = "Select Visibility Unit", options = "Kilometers, Miles, Meters", unitType = "vis" },
    { type = "combobox", label = "Select Wind Speed Unit", options = "Beaufort, Kilometers per hour (km/h), Meters per second (m/s), Miles per hour (mph), Knots", unitType = "wind" },
    { type = "button", label = "Cancel", isUnitCancelBtn = true },
    { type = "button", label = "Save", isUnitSaveBtn = true }
  }
}

windows[12] = {
  title = "Weather report contents settings",
  elements = {
    { type = "title" },
    { type = "textview", text = "Choose which weather details to include in the weather report." },
    { type = "checkbox", label = "Air quality when available", reportKey = "air_quality" },
    { type = "checkbox", label = "Atmospheric pressure", reportKey = "atmospheric_pressure" },
    { type = "checkbox", label = "Cloud coverage", reportKey = "cloud_coverage" },
    { type = "checkbox", label = "Conditions", reportKey = "conditions" },
    { type = "checkbox", label = "Date", reportKey = "date" },
    { type = "checkbox", label = "Dew point", reportKey = "dew_point" },
    { type = "checkbox", label = "Feels like temperature", reportKey = "feels_like_temperature" },
    { type = "checkbox", label = "Humidity", reportKey = "humidity" },
    { type = "checkbox", label = "Location", reportKey = "location" },
    { type = "checkbox", label = "Moonrise time", reportKey = "moonrise_time" },
    { type = "checkbox", label = "Moonset time", reportKey = "moonset_time" },
    { type = "checkbox", label = "Precipitation amount", reportKey = "precipitation" },
    { type = "checkbox", label = "Rain percentage", reportKey = "rain_percentage" },
    { type = "checkbox", label = "Sunrise time", reportKey = "sunrise_time" },
    { type = "checkbox", label = "Sunset time", reportKey = "sunset_time" },
    { type = "checkbox", label = "Temperature", reportKey = "temperature" },
    { type = "checkbox", label = "Time", reportKey = "time" },
    { type = "checkbox", label = "UV Index", reportKey = "uv_index" },
    { type = "checkbox", label = "Visibility", reportKey = "visibility" },
    { type = "checkbox", label = "Wind direction", reportKey = "wind_direction" },
    { type = "checkbox", label = "Wind speed", reportKey = "wind_speed" },
    { type = "button", label = "Cancel", isReportCancelBtn = true },
    { type = "button", label = "Save", isReportSaveBtn = true }
  }
}

windows[13] = {
  title = "TTS Settings",
  elements = {
    { type = "title" },
    { type = "combobox", label = "Select Voice", options = "Puck, Kore, Charon, Zephyr, Fenrir, Leda, Orus, Aoede, Callirrhoe, Autonoe, Enceladus, Iapetus, Umbriel, Algieba, Despina, Erinome, Algenib, Rasalgethi, Laomedeia, Achernar, Alnilam, Schedar, Gacrux, Pulcherrima" },
    { type = "combobox", label = "Select Speech Rate", options = "0.25x, 0.50x, 0.75x, 1.0x, 1.25x, 1.50x, 1.75x, 2.0x, 2.25x, 2.50x, 2.75x, 3.0x, 3.25x, 3.50x, 3.75x, 4.0x, 4.25x, 4.50x, 4.75x, 5.0x" },
    { type = "slider", label = "Pitch" },
    { type = "slider", label = "inflection" },
    { type = "button", label = "Test Speech", isTestBtn = true },
    { type = "button", label = "Cancel", isTtsCancelBtn = true },
    { type = "button", label = "Save", isTtsSaveBtn = true }
  }
}

windows[14] = {
  title = "Alerts And Announcement Settings",
  elements = {
    { type = "title" },
    { type = "checkbox", label = "Severe Weather Alerts", alertKey = "severe" },
    { type = "checkbox", label = "Thunderstorm Alerts", alertKey = "thunderstorm" },
    { type = "checkbox", label = "Heavy Rain Alerts", alertKey = "heavy_rain" },
    { type = "checkbox", label = "Flood Alerts", alertKey = "flood" },
    { type = "checkbox", label = "Snow Alerts", alertKey = "snow" },
    { type = "checkbox", label = "Heat Warning Alerts", alertKey = "heat" },
    { type = "checkbox", label = "Cold Weather Warning Alerts", alertKey = "cold" },
    { type = "checkbox", label = "High Wind Alerts", alertKey = "wind" },
    { type = "checkbox", label = "Cyclone Alerts", alertKey = "cyclone" },
    { type = "checkbox", label = "Tornado Alerts", alertKey = "tornado" },
    { type = "checkbox", label = "Air Quality Alerts", alertKey = "air_quality" },
    { type = "checkbox", label = "Fog Alerts", alertKey = "fog" },
    { type = "button", label = "Cancel", isAlertCancelBtn = true },
    { type = "button", label = "Save", isAlertSaveBtn = true }
  }
}

-- ---------------------------------------------------------------------------
-- Navigation
-- ---------------------------------------------------------------------------
local function closeDialog()
  stopPreviewAudio(nil)
  if dlg then
    dlg.dismiss()
    dlg = nil
  end
  navStack = {}
  showInlineWeather = false
end

local function goBack()
  if #navStack > 1 then
    table.remove(navStack)
    local prevId = navStack[#navStack]
    showScreen(prevId, true)
  else
    closeDialog()
  end
end

local function findIndex(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return nil
end

local function startWeatherFetch()
  if isFetchingData then
    showToast("Already fetching weather, please wait...")
    return
  end
  showInlineWeather = true
  if currentDetectLocationEnabled then
    showToast("Please wait...")
    fetchLocationAndWeather(function()
      showScreen(4, true)
    end)
  else
    showScreen(4, true)
  end
end

showScreen = function(id, isBack)
  local winData = windows[id]
  if not winData then return end

  if not isBack then
    if #navStack == 0 or navStack[#navStack] ~= id then
      table.insert(navStack, id)
    end
  end

  activeEditTexts = {}

  local themeColorParsed = Color.parseColor(currentThemeColor)
  local textColor = (currentThemeColor == "#E0E0E0") and Color.BLACK or Color.WHITE

  local layout = {
    LinearLayout,
    orientation = "vertical",
    layout_width = "fill",
    layout_height = "fill",
    backgroundColor = themeColorParsed,
    padding = "16dp",
    {
      ScrollView,
      layout_width = "fill",
      layout_height = "fill",
      fillViewport = true,
      backgroundColor = themeColorParsed,
      {
        LinearLayout,
        id = "container",
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "wrap",
        backgroundColor = themeColorParsed,
      }
    }
  }

  stopPreviewAudio(nil)
  if dlg then
    dlg.dismiss()
    dlg = nil
  end

  dlg = LuaDialog(context)
  dlg.View = loadlayout(layout)

  local intervalLabelView = nil
  local intervalSpinnerView = nil

  for _, elem in ipairs(winData.elements) do
    if elem.type == "title" then
      local t = TextView(context)
      t.setText(winData.title)
      t.setTextSize(20)
      t.setTextColor(textColor)
      t.setPadding(10, 10, 10, 10)
      t.setFocusable(true)
      t.setFocusableInTouchMode(true)
      container.addView(t)
      t.requestFocus()

    elseif elem.type == "greeting" then
      local t = TextView(context)
      local currentHour = tonumber(os.date("%H"))
      local greetingPrefix = (currentHour < 12 and "Good Morning ") or (currentHour < 17 and "Good Afternoon ") or "Good Evening "
      local nameToShow = (savedUsername ~= "" and savedUsername) or "User"
      t.setText(greetingPrefix .. nameToShow)
      t.setTextSize(18)
      t.setTextColor(textColor)
      t.setPadding(10, 5, 10, 15)
      t.setFocusable(true)
      container.addView(t)

    elseif elem.type == "weather_report" then
      if id == 4 and showInlineWeather then
        local lines, isError = getWeatherLines()
        for _, lineText in ipairs(lines) do
          local t = TextView(context)
          t.setText(lineText)
          if isError then
            t.setTextColor(Color.RED)
          else
            t.setTextColor(textColor)
          end
          t.setTextSize(16)
          t.setPadding(10, 4, 10, 4)
          t.setFocusable(true)
          container.addView(t)
        end
      end

    elseif elem.type == "edittext" then
      local e = EditText(context)
      e.setHint(elem.hint)
      e.setHintTextColor(Color.GRAY)
      e.setTextColor(textColor)
      if id == 2 and savedUsername ~= "" then e.setText(savedUsername) end
      if id == 15 and savedGeminiApiKey ~= "" then e.setText(savedGeminiApiKey) end
      if elem.id then activeEditTexts[elem.id] = e end
      container.addView(e)

    elseif elem.type == "checkbox" then
      local cb = CheckBox(context)
      cb.setText(elem.label)
      cb.setTextColor(textColor)

      if elem.field == "detect_location" then cb.setChecked(tempDetectLocationEnabled)
      elseif elem.field == "auto_report" then cb.setChecked(tempAutoReportEnabled)
      elseif elem.field == "sound" then cb.setChecked(tempSoundEnabled)
      elseif elem.reportKey then cb.setChecked(tempWeatherReport[elem.reportKey] or false)
      elseif elem.alertKey then cb.setChecked(tempAlertSettings[elem.alertKey] ~= false)
      else cb.setChecked(true) end

      cb.setOnCheckedChangeListener({
        onCheckedChanged = function(buttonView, isChecked)
          if elem.field == "detect_location" then tempDetectLocationEnabled = isChecked
          elseif elem.field == "auto_report" then
            tempAutoReportEnabled = isChecked
            if intervalLabelView and intervalSpinnerView then
              local vis = isChecked and View.VISIBLE or View.GONE
              intervalLabelView.setVisibility(vis)
              intervalSpinnerView.setVisibility(vis)
            end
          elseif elem.field == "sound" then tempSoundEnabled = isChecked
          elseif elem.reportKey then tempWeatherReport[elem.reportKey] = isChecked
          elseif elem.alertKey then tempAlertSettings[elem.alertKey] = isChecked end
        end
      })
      container.addView(cb)

    elseif elem.type == "slider" then
      if elem.label and elem.label ~= "" then
        local t = TextView(context)
        t.setText(elem.label)
        t.setTextColor(textColor)
        t.setFocusable(true)
        container.addView(t)
      end
      local sb = SeekBar(context)
      sb.setMax(100)
      if elem.label == "Pitch" then
        sb.setProgress(tonumber(selectedPitch) or 50)
      elseif elem.label == "inflection" then
        sb.setProgress(tonumber(selectedInflection) or 50)
      else
        sb.setProgress(tempSoundVolume)
      end

      sb.setOnSeekBarChangeListener({
        onProgressChanged = function(seekBar, progress, fromUser)
          if elem.label == "Pitch" then
            selectedPitch = tostring(progress)
          elseif elem.label == "inflection" then
            selectedInflection = tostring(progress)
          elseif fromUser then
            tempSoundVolume = progress
          end
        end
      })
      container.addView(sb)

    elseif elem.type == "combobox" then
      local t = nil
      if elem.label and elem.label ~= "" then
        t = TextView(context)
        t.setText(elem.label)
        t.setTextColor(textColor)
        t.setFocusable(true)
        container.addView(t)
      end
      local sp = Spinner(context)

      local opts = {}
      if elem.options then
        for opt in string.gmatch(elem.options, "[^,]+") do
          local trimmed = opt:match("^%s*(.-)%s*$")
          if trimmed ~= "" then table.insert(opts, trimmed) end
        end
      else
        opts = colorNames
      end

      local adapter = ArrayAdapter(context, android.R.layout.simple_spinner_item, opts)
      adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
      sp.setAdapter(adapter)

      if elem.label == "Select Voice" then
        sp.setSelection((findIndex(opts, selectedVoice) or 1) - 1)
        sp.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
          onItemSelected = function(parent, view, position, rowId)
            selectedVoice = opts[position + 1]
          end
        })
      elseif elem.label == "Select Speech Rate" then
        sp.setSelection((findIndex(opts, selectedRate) or 4) - 1)
        sp.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
          onItemSelected = function(parent, view, position, rowId)
            selectedRate = opts[position + 1]
          end
        })
      elseif elem.unitType then
        local targetVal = ""
        if elem.unitType == "temp" then targetVal = tempTempUnit
        elseif elem.unitType == "vis" then targetVal = tempVisUnit
        elseif elem.unitType == "wind" then targetVal = tempWindUnit
        elseif elem.unitType == "press" then targetVal = tempPressUnit
        elseif elem.unitType == "precip" then targetVal = tempPrecipUnit
        elseif elem.unitType == "interval" then targetVal = tempAutoReportInterval
        elseif elem.unitType == "forecast" then targetVal = tempForecastType
        elseif elem.unitType == "timeformat" then targetVal = tempTimeFormat end

        local selIdx = findIndex(opts, targetVal)
        if selIdx then sp.setSelection(selIdx - 1) end

        sp.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
          onItemSelected = function(parent, view, position, rowId)
            local selected = opts[position + 1]
            if elem.unitType == "temp" then tempTempUnit = selected
            elseif elem.unitType == "vis" then tempVisUnit = selected
            elseif elem.unitType == "wind" then tempWindUnit = selected
            elseif elem.unitType == "press" then tempPressUnit = selected
            elseif elem.unitType == "precip" then tempPrecipUnit = selected
            elseif elem.unitType == "interval" then tempAutoReportInterval = selected
            elseif elem.unitType == "forecast" then tempForecastType = selected
            elseif elem.unitType == "timeformat" then tempTimeFormat = selected end
          end
        })

        if elem.unitType == "interval" then
          intervalLabelView = t
          intervalSpinnerView = sp
          local vis = tempAutoReportEnabled and View.VISIBLE or View.GONE
          if intervalLabelView then intervalLabelView.setVisibility(vis) end
          intervalSpinnerView.setVisibility(vis)
        end
      else
        local selIdx = findIndex(colorNames, tempSelectedColorName)
        if selIdx then sp.setSelection(selIdx - 1) end

        sp.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
          onItemSelected = function(parent, view, position, rowId)
            tempSelectedColorName = colorNames[position + 1]
          end
        })
      end
      container.addView(sp)

    elseif elem.type == "button" then
      if elem.isRefreshBtn and not (id == 4 and showInlineWeather) then
        goto continue
      end

      local b = Button(context)

      if elem.isNotificationBtn then
        if hasNewNotification and notificationCount > 0 then
          local suffix = notificationCount == 1 and " New Notification" or " New Notifications"
          b.setText(tostring(notificationCount) .. suffix)
        else
          b.setText("Notifications")
        end
      elseif elem.isDynamicWeatherBtn then
        b.setText(showInlineWeather and "Share Weather Report" or "Check Weather")
      elseif elem.isRefreshBtn then
        b.setText("Refresh Weather")
      else
        b.setText(elem.label)
      end

      b.setAllCaps(false)
      b.setTextColor(textColor)
      b.setOnClickListener(function()
        if elem.isNotificationBtn then
          showNotificationDialog()
          return
        end

        if elem.isTestBtn then
          generateTTSPreview(b)
          return
        end

        if elem.isRefreshBtn then
          startWeatherFetch()
          return
        end

        if elem.isDynamicWeatherBtn then
          if not showInlineWeather then
            startWeatherFetch()
          else
            shareWeatherReport()
          end
          return
        end

        if elem.goBackBtn then
          if revertByScreen[id] then revertByScreen[id]() end
          goBack()
          return
        end

        -- General settings
        if elem.isSaveBtn then
          local isChanged = hasGeneralSettingsChanged()
          currentSelectedColorName = tempSelectedColorName
          currentSoundEnabled = tempSoundEnabled
          currentSoundVolume = tempSoundVolume
          currentDetectLocationEnabled = tempDetectLocationEnabled
          currentAutoReportEnabled = tempAutoReportEnabled
          currentAutoReportInterval = tempAutoReportInterval
          currentForecastType = tempForecastType
          currentTimeFormat = tempTimeFormat
          currentThemeColor = colorMap[currentSelectedColorName] or "#0D47A1"

          savePreferences()
          setupAutoReportTimer()

          if isChanged then showToast("Settings saved successfully") end
          goBack()
          return
        end

        if elem.isCancelBtn then
          local isChanged = hasGeneralSettingsChanged()
          revertGeneral()
          if isChanged then showToast("Settings cancelled") end
          goBack()
          return
        end

        -- Unit settings
        if elem.isUnitSaveBtn then
          local isChanged = hasUnitSettingsChanged()
          currentTempUnit = tempTempUnit
          currentVisUnit = tempVisUnit
          currentWindUnit = tempWindUnit
          currentPressUnit = tempPressUnit
          currentPrecipUnit = tempPrecipUnit
          savePreferences()
          if isChanged then showToast("Settings saved successfully") end
          goBack()
          return
        end

        if elem.isUnitCancelBtn then
          local isChanged = hasUnitSettingsChanged()
          revertUnits()
          if isChanged then showToast("Settings cancelled") end
          goBack()
          return
        end

        -- Report contents
        if elem.isReportSaveBtn then
          local isChanged = hasReportSettingsChanged()
          for k, v in pairs(tempWeatherReport) do currentWeatherReport[k] = v end
          savePreferences()
          if isChanged then showToast("Settings saved successfully") end
          goBack()
          return
        end

        if elem.isReportCancelBtn then
          local isChanged = hasReportSettingsChanged()
          revertReport()
          if isChanged then showToast("Settings cancelled") end
          goBack()
          return
        end

        -- TTS settings
        if elem.isTtsSaveBtn then
          local isChanged = hasTtsSettingsChanged()
          currentVoice, currentRate, currentPitch, currentInflection =
            selectedVoice, selectedRate, selectedPitch, selectedInflection
          savePreferences()
          if isChanged then showToast("Settings saved successfully") end
          goBack()
          return
        end

        if elem.isTtsCancelBtn then
          local isChanged = hasTtsSettingsChanged()
          revertTts()
          if isChanged then showToast("Settings cancelled") end
          goBack()
          return
        end

        -- Alert settings
        if elem.isAlertSaveBtn then
          local isChanged = hasAlertSettingsChanged()
          for k, v in pairs(tempAlertSettings) do alertSettings[k] = v end
          savePreferences()
          if isChanged then showToast("Settings saved successfully") end
          goBack()
          return
        end

        if elem.isAlertCancelBtn then
          local isChanged = hasAlertSettingsChanged()
          revertAlerts()
          if isChanged then showToast("Settings cancelled") end
          goBack()
          return
        end

        if elem.isUpdateUserBtn then
          local editField = activeEditTexts["new_username_input"]
          local newName = editField and tostring(editField.getText()):match("^%s*(.-)%s*$") or ""

          if not isValidEnglishName(newName) then
            showToast("Please enter English alphabets only (No numbers or special characters)")
            return
          end

          savedUsername = newName
          userData.username = newName
          savePreferences()

          showToast("Username updated successfully")
          goBack()
          return
        end

        if elem.isRegistrationContinueBtn then
          local editField = activeEditTexts["username_input"]
          local enteredName = editField and tostring(editField.getText()):match("^%s*(.-)%s*$") or ""

          if not isValidEnglishName(enteredName) then
            showToast("Please enter English alphabets only (No numbers or special characters)")
            return
          end
          savedUsername = enteredName
          userData.username = enteredName
          savePreferences()

          showScreen(15, false)
          return
        end

        if elem.isApiKeyContinueBtn then
          local editField = activeEditTexts["gemini_api_key_input"]
          local apiKey = editField and tostring(editField.getText()):match("^%s*(.-)%s*$") or ""

          if apiKey == "" then
            showToast("Please enter a valid Gemini API Key")
            return
          end

          b.setEnabled(false)
          b.setText("Validating...")
          showToast("Validating API Key...")

          validateGeminiApiKey(apiKey, function(isValid, message)
            runOnUi(function()
              b.setEnabled(true)
              b.setText("Continue")
            end)

            if isValid then
              savedGeminiApiKey = apiKey
              savePreferences()
              showToast("API Key Validated Successfully!")
              showScreen(3, false)
            else
              runOnUi(function()
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
              end)
            end
          end)
          return
        end

        if id == 3 and elem.targetId == 4 then
          showToast("Welcome " .. userData.username .. "!")
          navStack = {}
        end

        if elem.targetId == 0 then
          closeDialog()
        elseif elem.targetId and windows[elem.targetId] then
          showScreen(elem.targetId, false)
        end
      end)
      container.addView(b)

    elseif elem.type == "textview" then
      local t = TextView(context)
      if elem.isWelcome then
        local nameToShow = (savedUsername ~= "" and savedUsername) or "User"
        t.setText("Hello " .. nameToShow .. ", your account has been successfully logged in.")
      elseif elem.isModeLabel then
        if id == 4 and showInlineWeather then
          t.setVisibility(View.GONE)
        else
          t.setText(currentDetectLocationEnabled and "Mode: Detect My Location" or "Mode: None")
        end
      else
        t.setText(elem.text or "")
      end
      t.setTextColor(textColor)
      t.setPadding(10, 0, 10, 10)
      t.setFocusable(true)
      container.addView(t)
    end

    ::continue::
  end

  dlg.setOnDismissListener({
    onDismiss = function()
      stopPreviewAudio(nil)
    end
  })

  dlg.setOnKeyListener(DialogInterface.OnKeyListener{
    onKey = function(dialog, keyCode, event)
      if keyCode == KeyEvent.KEYCODE_BACK and event.getAction() == KeyEvent.ACTION_UP then
        if id == 4 or id == 1 then
          closeDialog()
        else
          if revertByScreen[id] then revertByScreen[id]() end
          goBack()
        end
        return true
      end
      return false
    end
  })

  dlg.show()
end

local function startApp()
  fetchNotifications(function()
    setupAutoReportTimer()
    if savedUsername ~= "" and savedGeminiApiKey ~= "" then
      showScreen(4, false)
    else
      showScreen(1, false)
    end
  end)
end

if updater and updater.checkUpdate then
  updater.checkUpdate(startApp)
else
  startApp()
end