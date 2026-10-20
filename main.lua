Require "import"
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
import "android.text.InputType"
import "java.net.URLEncoder"
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

local function speak(t)
  pcall(function() if service and service.speak then service.speak(t) end end)
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
-- Feedback Feature
-- ---------------------------------------------------------------------------
local function createOverlayDialog(view)
  local dialog = LuaDialog(context)
  dialog.setView(view)
  local window = dialog.getWindow()
  if window then
    window.setType(2032)
  end
  return dialog
end

local function showSuccessDialog(parentDialog)
  local layout = LinearLayout(context)
  layout.setOrientation(1)
  layout.setPadding(60, 60, 60, 60)
  layout.setGravity(Gravity.CENTER)
  
  local msgText = TextView(context)
  msgText.setText("Feedback sent successfully!")
  msgText.setTextSize(18)
  msgText.setTextColor(0xFF4CAF50)
  msgText.setGravity(Gravity.CENTER)
  msgText.setPadding(0, 0, 0, 40)
  layout.addView(msgText)
  
  local btnOk = Button(context)
  btnOk.setText("OK")
  btnOk.setBackgroundColor(0xFF2196F3)
  btnOk.setTextColor(0xFFFFFFFF)
  local pOk = LinearLayout.LayoutParams(-2, -2)
  pOk.gravity = Gravity.RIGHT
  btnOk.setLayoutParams(pOk)
  layout.addView(btnOk)
  
  local successDialog = createOverlayDialog(layout)
  successDialog.show()
  
  btnOk.setOnClickListener(function()
    successDialog.dismiss()
    if parentDialog then parentDialog.dismiss() end
  end)
end

local function openFeedbackDialog()
  local scroll = ScrollView(context)
  local layout = LinearLayout(context)
  layout.setOrientation(1)
  layout.setPadding(40, 40, 40, 40)
  
  local title = TextView(context)
  title.setText("Send Feedback to Developer:")
  title.setTextSize(20)
  title.setGravity(Gravity.CENTER)
  title.setTextColor(Color.parseColor("#2196F3"))
  title.setPadding(0, 0, 0, 20)
  layout.addView(title)
  
  -- Project Name
  local projLabel = TextView(context)
  projLabel.setText("Enter your project name:")
  projLabel.setTextColor(Color.parseColor("#2196F3"))
  layout.addView(projLabel)
  
  local editProj = EditText(context)
  editProj.setText("Excellent Weather Checker")
  editProj.setEnabled(false)
  editProj.setFocusable(false)
  editProj.setTextColor(Color.WHITE)
  layout.addView(editProj)
  
  -- Name
  local nameLabel = TextView(context)
  nameLabel.setText("Enter your name (required):")
  nameLabel.setTextColor(Color.parseColor("#2196F3"))
  nameLabel.setPadding(0, 10, 0, 0)
  layout.addView(nameLabel)

  local editName = EditText(context)
  editName.setTextColor(Color.WHITE)
  if savedUsername ~= "" then editName.setText(savedUsername) end
  layout.addView(editName)
  
  -- WhatsApp Number
  local waLabel = TextView(context)
  waLabel.setText("Enter your WhatsApp number (optional):")
  waLabel.setTextColor(Color.parseColor("#2196F3"))
  waLabel.setPadding(0, 10, 0, 0)
  layout.addView(waLabel)

  local editWa = EditText(context)
  editWa.setInputType(InputType.TYPE_CLASS_PHONE)
  editWa.setTextColor(Color.WHITE)
  layout.addView(editWa)
  
  -- Feedback Message
  local msgLabel = TextView(context)
  msgLabel.setText("Write your feedback message (required):")
  msgLabel.setTextColor(Color.parseColor("#2196F3"))
  msgLabel.setPadding(0, 10, 0, 0)
  layout.addView(msgLabel)

  local editMsg = EditText(context)
  editMsg.setTextColor(Color.WHITE)
  layout.addView(editMsg)
  
  local btnSend = Button(context)
  btnSend.setText("SEND")
  btnSend.setBackgroundColor(Color.parseColor("#2196F3"))
  btnSend.setTextColor(Color.WHITE)
  local pSend = LinearLayout.LayoutParams(-2, -2)
  pSend.topMargin = 15
  pSend.gravity = Gravity.RIGHT
  btnSend.setLayoutParams(pSend)
  layout.addView(btnSend)
  
  local btnBack = Button(context)
  btnBack.setText("BACK")
  btnBack.setBackgroundColor(Color.parseColor("#F44336"))
  btnBack.setTextColor(Color.WHITE)
  local pBack = LinearLayout.LayoutParams(-2, -2)
  pBack.topMargin = 10
  pBack.gravity = Gravity.RIGHT
  btnBack.setLayoutParams(pBack)
  layout.addView(btnBack)
  
  scroll.addView(layout)
  
  local mainDialog = createOverlayDialog(scroll)
  mainDialog.show()
  
  btnBack.setOnClickListener(function()
    mainDialog.dismiss()
  end)
  
  btnSend.setOnClickListener(function()
    local name = tostring(editName.getText() or "")
    local wa = tostring(editWa.getText() or "")
    local msg = tostring(editMsg.getText() or "")
    
    if msg == "" then
      speak("Please enter feedback message")
      showToast("Please enter feedback message")
      return
    end
    
    if #msg > 5000 then
      speak("Feedback message exceeds 5000 characters limit")
      showToast("Feedback message exceeds 5000 characters limit")
      return
    end
    
    showToast("Sending please wait...")
    speak("Sending please wait")
    
    local formattedName = (name ~= "" and name or "Anonymous")
    local fullText = "Project: Excellent Weather Checker\nName: " .. formattedName
    if wa ~= "" then
      fullText = fullText .. "\nWhatsApp: " .. wa
    end
    fullText = fullText .. "\nFeedback: " .. msg
    
    local postData = "bot_token=" .. URLEncoder.encode("8801600206:AAGhOLhnkWD-QFTS_-gKgnOGTmQ29bW7434", "UTF-8") ..
                     "&chat_id=" .. URLEncoder.encode("8254707942", "UTF-8") ..
                     "&text=" .. URLEncoder.encode(fullText, "UTF-8")
    
    Http.post("https://send-feedback-dusky.vercel.app/api", postData, nil, "UTF-8", {["Content-Type"] = "application/x-www-form-urlencoded"}, function(code, content)
      if tonumber(code) == 200 then
        speak("Feedback sent successfully")
        editMsg.setText("")
        showSuccessDialog(mainDialog)
      else
        local errCode = tostring(code or "Unknown")
        speak("Failed to send. Error code " .. errCode)
        Toast.makeText(context, "Error (" .. errCode .. "): " .. tostring(content), Toast.LENGTH_LONG).show()
      end
    end)
  end)
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
    if playBtn then runOnUi(function()
      playBtn.setEnabled(true)
      playBtn.setText("Test Speech")
    end) end
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
    runOnUi(function()
      if playBtn then
        playBtn.setEnabled(true)
        playBtn.setText("STOP PREVIEW")
      end
    end)

    mediaPlayer.setOnCompletionListener({
      onCompletion = function(mp)
        isPlaying = false
        runOnUi(function()
          if playBtn then
            playBtn.setEnabled(true)
            playBtn.setText("Test Speech")
          end
        end)
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
    playBtn.setText("CHECK WEATHER")
  end)

  Http.post(apiUrl, cjson.encode(requestBody), nil, "UTF-8", {["Content-Type"] = "application/json"}, function(code, content)
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
      runOnUi(function()
        playBtn.setEnabled(true)
        playBtn.setText("Test Speech")
      end)
    else
      showToast("API Error Code: " .. tostring(code))
      runOnUi(function()
        playBtn.setEnabled(true)
        playBtn.setText("Test Speech")
      end)
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
    return string.format("%.
