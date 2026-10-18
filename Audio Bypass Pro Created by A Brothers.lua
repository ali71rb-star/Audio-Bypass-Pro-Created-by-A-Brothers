require "import"
import "android.app.AlertDialog"
import "android.content.DialogInterface"
import "android.content.Context"
import "android.content.Intent"
import "android.content.IntentFilter"
import "android.content.BroadcastReceiver"
import "android.net.Uri"
import "android.os.Handler"
import "android.os.Looper"
import "java.lang.Runnable"
import "java.net.URLEncoder"
import "android.widget.LinearLayout"
import "android.widget.RadioGroup"
import "android.widget.RadioButton"
import "android.widget.CheckBox"
import "android.widget.Button"
import "android.widget.TextView"
import "android.widget.ScrollView"
import "android.widget.SeekBar"
import "android.view.Gravity"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.Typeface"
import "java.io.File"
import "android.app.DownloadManager"
import "android.os.Environment"
import "android.media.MediaPlayer"
import "java.lang.Long"

local function showToast(msg)
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            pcall(function() luajava.bindClass("android.widget.Toast").makeText(service, msg, 1).show() end)
        end
    }))
end

local SDK_INT = 21
pcall(function() SDK_INT = luajava.bindClass("android.os.Build").VERSION.SDK_INT end)
local pluginDir = ""
pcall(function() pluginDir = debug.getinfo(1, "S").source:match("^@?(.*)/") end)
if not pluginDir or pluginDir == "" then
    pluginDir = "/storage/emulated/0/瑙ｈ/Plugins/Audio Bypass Pro Created by A Brothers"
    pcall(function() File(pluginDir).mkdirs() end)
end

local configPath = pluginDir .. "/bypass_config.txt"
local selectedChannel = "Call Volume"
local autoBtEnabled = false
local openBtSettingsEnabled = false
if _G.bypass_media_is_on == nil then _G.bypass_media_is_on = false end

local tutorialListDialog = nil
local tutorialDialog = nil
local tutorialMediaPlayer = nil
local tutorialFilePath = nil
local tutorialPlayerActive = false

local function dismissAllDialogsCustom()
    if tutorialListDialog then pcall(function() tutorialListDialog.dismiss() end) tutorialListDialog = nil end
    if tutorialDialog then pcall(function() tutorialDialog.dismiss() end) tutorialDialog = nil end
    if tutorialMediaPlayer then
        pcall(function() tutorialMediaPlayer.stop() end)
        pcall(function() tutorialMediaPlayer.release() end)
        tutorialMediaPlayer = nil
        tutorialPlayerActive = false
    end
end

local function safeShow(d)
    if d then
        d.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
        d.show()
    end
end

local function loadConfig()
    pcall(function()
        local f = io.open(configPath, "r")
        if f then
            local saved = f:read("*l")
            if saved and saved ~= "" then
                if string.find(saved, ",") then
                    local parts = {}
                    for part in string.gmatch(saved, "([^,]+)") do
                        table.insert(parts, part)
                    end
                    selectedChannel = parts[1] or "Call Volume"
                    autoBtEnabled = (parts[2] == "true")
                    openBtSettingsEnabled = (parts[3] == "true")
                else
                    selectedChannel = saved
                    autoBtEnabled = false
                    openBtSettingsEnabled = false
                end
            end
            f:close()
        end
    end)
end

local function saveConfig(channel, autoBt, openBt)
    pcall(function()
        local f = io.open(configPath, "w")
        if f then 
            f:write(channel .. "," .. tostring(autoBt) .. "," .. tostring(openBt))
            f:close() 
        end
    end)
end

local function checkBluetoothConnected()
    local isBtConnected = false
    pcall(function()
        local am = service.getSystemService(Context.AUDIO_SERVICE)
        if am.isBluetoothA2dpOn() or am.isBluetoothScoOn() then isBtConnected = true end
    end)
    pcall(function()
        if not isBtConnected then
            local btAdapter = luajava.bindClass("android.bluetooth.BluetoothAdapter").getDefaultAdapter()
            if btAdapter and btAdapter.isEnabled() then
                if btAdapter.getProfileConnectionState(2) == 2 or btAdapter.getProfileConnectionState(1) == 2 then
                    isBtConnected = true
                end
            end
        end
    end)
    return isBtConnected
end

local function turnOffBypass(silent)
    if not _G.bypass_media_is_on then return end
    pcall(function()
        local am = service.getSystemService(Context.AUDIO_SERVICE)
        if am then
            if SDK_INT >= 31 then am.clearCommunicationDevice() end
            am.setMode(0)
            am.setBluetoothScoOn(false)
            am.setSpeakerphoneOn(false)
        end
    end)
    _G.bypass_media_is_on = false
    if not silent then
        showToast("Audio Bypass Pro OFF")
    end
end

local function turnOnBypass(silent, force)
    if _G.bypass_media_is_on and not force then return end
    pcall(function()
        local am = service.getSystemService(Context.AUDIO_SERVICE)
        if am then
            am.setBluetoothScoOn(false)
            am.setBluetoothA2dpOn(true)
            
            if selectedChannel == "Call Volume" then
                am.setMode(3)
                am.setSpeakerphoneOn(true)
            else
                am.setMode(0)
                am.setSpeakerphoneOn(true)
            end
            
            if SDK_INT >= 31 then
                local devices = am.getDevices(2)
                local targetDevice = nil
                if devices and devices.length > 0 then
                    for i = 0, devices.length - 1 do
                        if devices[i].getType() == 2 then
                            targetDevice = devices[i]
                            break
                        end
                    end
                end
                if targetDevice then am.setCommunicationDevice(targetDevice) end
            end
        end
    end)
    _G.bypass_media_is_on = true
    if not silent then
        showToast("Audio Bypass Pro ON")
    end
end

local function processBypassToggle()
    loadConfig()
    local isBtConnected = checkBluetoothConnected()
    local btAdapter = nil
    pcall(function() btAdapter = luajava.bindClass("android.bluetooth.BluetoothAdapter").getDefaultAdapter() end)
    
    if _G.bypass_media_is_on then
        turnOffBypass(false)
        if autoBtEnabled and btAdapter and btAdapter.isEnabled() then
            pcall(function() btAdapter.disable() end)
        end
    else
        if not autoBtEnabled and not isBtConnected then
            showToast("Bluetooth is not connected. Please connect a device first.")
            return
        end

        if autoBtEnabled then
            if btAdapter and not btAdapter.isEnabled() then
                pcall(function() btAdapter.enable() end)
            end
            if openBtSettingsEnabled then
                pcall(function()
                    local Settings = luajava.bindClass("android.provider.Settings")
                    local intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    service.startActivity(intent)
                end)
            end
        end
        
        turnOnBypass(false, false)
    end
end

if not _G.bt_disconnect_receiver_registered then
    pcall(function()
        local BluetoothDevice = luajava.bindClass("android.bluetooth.BluetoothDevice")
        local BroadcastReceiver = luajava.bindClass("android.content.BroadcastReceiver")
        local IntentFilter = luajava.bindClass("android.content.IntentFilter")
        
        local receiver = BroadcastReceiver({
            onReceive = function(context, intent)
                local action = intent.getAction()
                if action == BluetoothDevice.ACTION_ACL_DISCONNECTED then
                    if _G.bypass_media_is_on then
                        turnOffBypass(true)
                    end
                end
            end
        })
        local filter = IntentFilter(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        service.registerReceiver(receiver, filter)
        _G.bt_disconnect_receiver_registered = true
    end)
end

local function showChannelSettings()
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            loadConfig()
            local layout = LinearLayout(service)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(50, 50, 50, 50)
            local titleView = TextView(service)
            titleView.setText("Select Audio Channel for Speaker")
            titleView.setTextSize(18)
            titleView.setGravity(Gravity.CENTER)
            titleView.setPadding(0, 0, 0, 30)
            layout.addView(titleView)
            local radioGroup = RadioGroup(service)
            local rbCall = RadioButton(service)
            rbCall.setText("Call Volume")
            radioGroup.addView(rbCall)
            local rbNotif = RadioButton(service)
            rbNotif.setText("Notification")
            radioGroup.addView(rbNotif)
            local rbAlarm = RadioButton(service)
            rbAlarm.setText("Alarm")
            radioGroup.addView(rbAlarm)
            if selectedChannel == "Notification" then rbNotif.setChecked(true)
            elseif selectedChannel == "Alarm" then rbAlarm.setChecked(true)
            else rbCall.setChecked(true) end
            layout.addView(radioGroup)
            
            local cbAutoBt = CheckBox(service)
            cbAutoBt.setText("Auto Toggle Bluetooth")
            cbAutoBt.setChecked(autoBtEnabled)
            local lpCb1 = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lpCb1.setMargins(0, 30, 0, 0)
            cbAutoBt.setLayoutParams(lpCb1)
            layout.addView(cbAutoBt)
            
            local cbOpenBt = CheckBox(service)
            cbOpenBt.setText("Auto Open Bluetooth Settings")
            cbOpenBt.setChecked(openBtSettingsEnabled)
            if not autoBtEnabled then
                cbOpenBt.setEnabled(false)
                cbOpenBt.setChecked(false)
            end
            local lpCb2 = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lpCb2.setMargins(0, 15, 0, 0)
            cbOpenBt.setLayoutParams(lpCb2)
            layout.addView(cbOpenBt)
            
            cbAutoBt.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    if cbAutoBt.isChecked() then
                        cbOpenBt.setEnabled(true)
                    else
                        cbOpenBt.setChecked(false)
                        cbOpenBt.setEnabled(false)
                    end
                end
            }))
            
            local btnSave = Button(service)
            btnSave.setText("Save")
            local lpBtn = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            lpBtn.setMargins(0, 40, 0, 0)
            btnSave.setLayoutParams(lpBtn)
            layout.addView(btnSave)
            
            local builder = AlertDialog.Builder(service)
            builder.setTitle("Audio Stream Channel Settings")
            builder.setView(layout)
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            btnSave.setOnClickListener(View.OnClickListener({
                onClick = function(v)
                    local newChannel = "Call Volume"
                    if rbNotif.isChecked() then newChannel = "Notification"
                    elseif rbAlarm.isChecked() then newChannel = "Alarm" end
                    local isAutoBt = cbAutoBt.isChecked()
                    local isOpenBt = cbOpenBt.isChecked()
                    saveConfig(newChannel, isAutoBt, isOpenBt)
                    selectedChannel = newChannel
                    autoBtEnabled = isAutoBt
                    openBtSettingsEnabled = isOpenBt
                    showToast("Setting Saved")
                    dialog.dismiss()
                end
            }))
            dialog.show()
        end
    }))
end

local function showAbout()
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local builder = AlertDialog.Builder(service)
            builder.setTitle("About & Credits")
            
            local scrollView = ScrollView(service)
            local layout = LinearLayout(service)
            layout.setOrientation(LinearLayout.VERTICAL)
            layout.setPadding(40, 20, 40, 20)
            
            local elements = {
                {text = "Credits", isBold = true, size = 20, topPad = 0},
                {text = "Ahmed Ali", isBold = true, size = 18, topPad = 20},
                {text = "Major Idea and Conceptualization.", isBold = false, size = 16, topPad = 5},
                {text = "Ali Gujjar", isBold = true, size = 18, topPad = 20},
                {text = "Working and Development.", isBold = false, size = 16, topPad = 5},
                {text = "Azlan Tahir", isBold = true, size = 18, topPad = 20},
                {text = "Quality Assurance and Testing.", isBold = false, size = 16, topPad = 5},
                {text = "About", isBold = true, size = 20, topPad = 40},
                {text = "Audio Bypass Pro, created by A Brothers, is an advanced extension designed to seamlessly manage and route your device's audio channels.", isBold = false, size = 16, topPad = 10},
                {text = "Features:", isBold = true, size = 18, topPad = 30},
                {text = "1. Automatic Bluetooth toggling for seamless connections.", isBold = false, size = 16, topPad = 10},
                {text = "2. Customizable audio stream routing to specific channels like Call Volume, Notification, or Alarm.", isBold = false, size = 16, topPad = 15},
                {text = "3. Forces screen reader audio output to the internal phone speaker, bypassing external Bluetooth devices.", isBold = false, size = 16, topPad = 15},
                {text = "4. Silent and automatic bypass shut down upon Bluetooth disconnection.", isBold = false, size = 16, topPad = 15},
                {text = "5. User-friendly interface with quick double-tap activation and easy accessibility.", isBold = false, size = 16, topPad = 15}
            }
            
            for i = 1, #elements do
                local item = elements[i]
                local tv = TextView(service)
                tv.setText(item.text)
                tv.setTextSize(item.size)
                if item.isBold then
                    tv.setTypeface(Typeface.DEFAULT_BOLD)
                end
                tv.setPadding(0, item.topPad, 0, 10)
                tv.setFocusable(true) 
                layout.addView(tv)
            end
            
            scrollView.addView(layout)
            builder.setView(scrollView)
            builder.setPositiveButton("OK", nil)
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dialog.show()
        end
    }))
end

local function showTutorialDownloadDialog(name, url)
  dismissAllDialogsCustom()
  local sv = ScrollView(service)
  local layout = LinearLayout(service)
  layout.setOrientation(LinearLayout.VERTICAL)
  layout.setPadding(60, 40, 60, 40)
  sv.addView(layout)

  local downloadCancelled = false
  local userIsSeeking = false

  local function formatTime(ms)
    local totalSeconds = math.floor(ms / 1000)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return string.format("%d:%02d", minutes, seconds)
  end

  local downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
  local folder = File(downloadsDir, "Audio Bypass Pro")
  local safeName = name:gsub("[^%w%s%-]", ""):gsub("%s+", "_")
  local outFile = File(folder, safeName .. ".mp3")
  local fileAlreadyExists = false
  pcall(function() fileAlreadyExists = outFile.exists() end)
  if fileAlreadyExists then tutorialFilePath = outFile.getAbsolutePath() end

  local titleTxt = TextView(service)
  titleTxt.setText(name)
  titleTxt.setTextSize(16)
  titleTxt.setGravity(Gravity.CENTER)
  titleTxt.setPadding(0, 10, 0, 30)
  layout.addView(titleTxt)

  local downloadInfoRow = LinearLayout(service)
  downloadInfoRow.setOrientation(LinearLayout.HORIZONTAL)
  downloadInfoRow.setVisibility(View.GONE)
  layout.addView(downloadInfoRow)

  local percentTxt = TextView(service)
  percentTxt.setText("Downloading in progress... Please wait 0%")
  percentTxt.setTextSize(13)
  percentTxt.setGravity(Gravity.LEFT)
  local percentTxtParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
  percentTxt.setLayoutParams(percentTxtParams)
  downloadInfoRow.addView(percentTxt)

  local btnCancelDuring = Button(service)
  btnCancelDuring.setText("Cancel")
  downloadInfoRow.addView(btnCancelDuring)

  local statusTxt = TextView(service)
  statusTxt.setText(fileAlreadyExists and "Already downloaded." or "Ready to download this tutorial.")
  statusTxt.setTextSize(14)
  statusTxt.setGravity(Gravity.CENTER)
  statusTxt.setPadding(0, 0, 0, 20)
  layout.addView(statusTxt)

  local btnDownload = Button(service)
  btnDownload.setText("Download")
  btnDownload.setVisibility(fileAlreadyExists and View.GONE or View.VISIBLE)
  layout.addView(btnDownload)

  local btnCancel = Button(service)
  btnCancel.setText("Close")
  btnCancel.setVisibility(fileAlreadyExists and View.GONE or View.VISIBLE)
  layout.addView(btnCancel)

  local btnPlayExisting = Button(service)
  btnPlayExisting.setText("Play")
  btnPlayExisting.setVisibility(fileAlreadyExists and View.VISIBLE or View.GONE)
  layout.addView(btnPlayExisting)

  local btnOk = Button(service)
  btnOk.setText("Close")
  btnOk.setVisibility(View.GONE)
  layout.addView(btnOk)

  local seekRow = LinearLayout(service)
  seekRow.setOrientation(LinearLayout.HORIZONTAL)
  seekRow.setVisibility(View.GONE)
  layout.addView(seekRow)

  local durationTxt = TextView(service)
  durationTxt.setText("0:00 / 0:00")
  durationTxt.setTextSize(13)
  durationTxt.setGravity(Gravity.CENTER)
  seekRow.addView(durationTxt)

  local seekBar = SeekBar(service)
  seekBar.setMax(100)
  seekBar.setProgress(0)
  seekBar.setFocusable(true)
  seekBar.setFocusableInTouchMode(true)
  local seekBarParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1.0)
  seekBar.setLayoutParams(seekBarParams)
  seekRow.addView(seekBar)

  local btnRewind = Button(service)
  btnRewind.setText("Rewind")
  btnRewind.setVisibility(View.GONE)
  layout.addView(btnRewind)

  local btnPlayPause = Button(service)
  btnPlayPause.setText("Play")
  btnPlayPause.setVisibility(View.GONE)
  layout.addView(btnPlayPause)

  local btnFastForward = Button(service)
  btnFastForward.setText("Fast Forward")
  btnFastForward.setVisibility(View.GONE)
  layout.addView(btnFastForward)

  local btnGoBack = Button(service)
  btnGoBack.setText("Close")
  btnGoBack.setVisibility(View.GONE)
  layout.addView(btnGoBack)

  tutorialDialog = AlertDialog.Builder(service).setView(sv).setCancelable(false).create()
  safeShow(tutorialDialog)

  local function startDownload()
    downloadCancelled = false
    titleTxt.setText(name)
    statusTxt.setVisibility(View.GONE)
    percentTxt.setText("Downloading in progress... Please wait 0%")
    btnDownload.setVisibility(View.GONE)
    btnCancel.setVisibility(View.GONE)
    downloadInfoRow.setVisibility(View.VISIBLE)

    pcall(function() if not folder.exists() then folder.mkdirs() end end)
    pcall(function() if outFile.exists() then outFile.delete() end end)
    tutorialFilePath = outFile.getAbsolutePath()

    local dm = service.getSystemService(Context.DOWNLOAD_SERVICE)
    local downloadId = nil
    local enqueueOk, enqueueErr = pcall(function()
      local request = DownloadManager.Request(Uri.parse(url))
      request.setTitle(name)
      request.setDescription("Audio Bypass Pro Tutorial")
      request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Audio Bypass Pro/" .. safeName .. ".mp3")
      request.setAllowedOverMetered(true)
      request.setAllowedOverRoaming(true)
      request.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
      downloadId = dm.enqueue(request)
    end)

    if not enqueueOk or not downloadId then
      titleTxt.setText(name)
      downloadInfoRow.setVisibility(View.GONE)
      statusTxt.setVisibility(View.VISIBLE)
      statusTxt.setText("Download failed: " .. tostring(enqueueErr) .. " - Try Again")
      btnDownload.setVisibility(View.VISIBLE)
      btnCancel.setVisibility(View.VISIBLE)
      return
    end

    local function pollProgress()
      if downloadCancelled then
        pcall(function() dm.remove(downloadId) end)
        pcall(function() outFile.delete() end)
        titleTxt.setText(name)
        downloadInfoRow.setVisibility(View.GONE)
        statusTxt.setVisibility(View.VISIBLE)
        statusTxt.setText("Download cancelled.")
        btnDownload.setVisibility(View.VISIBLE)
        btnCancel.setVisibility(View.VISIBLE)
        return
      end

      local finished = false
      pcall(function()
        local cursor = dm.query(DownloadManager.Query())
        while cursor.moveToNext() do
          local rowId = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_ID))
          if rowId == downloadId then
            local status = cursor.getInt(cursor.getColumnIndex(DownloadManager.COLUMN_STATUS))
            local bytesDownloaded = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            local bytesTotal = cursor.getLong(cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))

            if status == DownloadManager.STATUS_SUCCESSFUL then
              finished = true
              titleTxt.setText(name)
              downloadInfoRow.setVisibility(View.GONE)
              statusTxt.setVisibility(View.VISIBLE)
              statusTxt.setText("Download Successfully")
              btnOk.setVisibility(View.VISIBLE)
              btnPlayExisting.setVisibility(View.VISIBLE)
            elseif status == DownloadManager.STATUS_FAILED then
              finished = true
              pcall(function() outFile.delete() end)
              titleTxt.setText(name)
              downloadInfoRow.setVisibility(View.GONE)
              statusTxt.setVisibility(View.VISIBLE)
              statusTxt.setText("Download failed: Try Again")
              btnDownload.setVisibility(View.VISIBLE)
              btnCancel.setVisibility(View.VISIBLE)
            elseif bytesTotal and bytesTotal > 0 then
              local percent = math.floor((bytesDownloaded / bytesTotal) * 100)
              local roundedPercent = math.floor(percent / 10) * 10
              percentTxt.setText("Downloading in progress... Please wait " .. roundedPercent .. "%")
            end
            break
          end
        end
        cursor.close()
      end)

      if not finished then
        service.handler.postDelayed(Runnable({run = pollProgress}), Long(400))
      end
    end

    pollProgress()
  end

  btnDownload.setOnClickListener(View.OnClickListener({ onClick = function(v) startDownload() end }))

  btnCancel.setOnClickListener(View.OnClickListener({ onClick = function(v) dismissAllDialogsCustom() end }))

  btnCancelDuring.setOnClickListener(View.OnClickListener({ onClick = function(v) downloadCancelled = true end }))

  local function updateSeekLoop()
    if not tutorialPlayerActive or not tutorialMediaPlayer then return end
    pcall(function()
      local dur = tutorialMediaPlayer.getDuration()
      local pos = tutorialMediaPlayer.getCurrentPosition()
      if dur > 0 then
        seekBar.setMax(dur)
        if not userIsSeeking then
          seekBar.setProgress(pos)
          durationTxt.setText(formatTime(pos) .. " / " .. formatTime(dur))
        end
      end
    end)
    service.handler.postDelayed(Runnable({run = updateSeekLoop}), Long(500))
  end

  local function startPlayback()
    btnDownload.setVisibility(View.GONE)
    btnCancel.setVisibility(View.GONE)
    btnPlayExisting.setVisibility(View.GONE)
    btnOk.setVisibility(View.GONE)
    statusTxt.setVisibility(View.VISIBLE)
    statusTxt.setText(name)
    seekRow.setVisibility(View.VISIBLE)
    btnRewind.setVisibility(View.VISIBLE)
    btnPlayPause.setVisibility(View.VISIBLE)
    btnFastForward.setVisibility(View.VISIBLE)
    btnGoBack.setVisibility(View.VISIBLE)

    pcall(function()
      tutorialMediaPlayer = MediaPlayer()
      tutorialMediaPlayer.setDataSource(tutorialFilePath)
      tutorialMediaPlayer.prepare()
      tutorialMediaPlayer.start()
      btnPlayPause.setText("Pause")
      tutorialPlayerActive = true
      updateSeekLoop()
    end)
  end

  btnOk.setOnClickListener(View.OnClickListener({ onClick = function(v) dismissAllDialogsCustom() end }))

  btnPlayExisting.setOnClickListener(View.OnClickListener({ onClick = function(v) startPlayback() end }))

  btnRewind.setOnClickListener(View.OnClickListener({
    onClick = function(v)
      pcall(function()
        if tutorialMediaPlayer then
          local pos = tutorialMediaPlayer.getCurrentPosition()
          local newPos = pos - 10000
          if newPos < 0 then newPos = 0 end
          tutorialMediaPlayer.seekTo(newPos)
        end
      end)
    end
  }))

  btnPlayPause.setOnClickListener(View.OnClickListener({
    onClick = function(v)
      pcall(function()
        if tutorialMediaPlayer then
          if tutorialMediaPlayer.isPlaying() then
            tutorialMediaPlayer.pause()
            btnPlayPause.setText("Play")
          else
            tutorialMediaPlayer.start()
            btnPlayPause.setText("Pause")
          end
        end
      end)
    end
  }))

  btnFastForward.setOnClickListener(View.OnClickListener({
    onClick = function(v)
      pcall(function()
        if tutorialMediaPlayer then
          local dur = tutorialMediaPlayer.getDuration()
          local pos = tutorialMediaPlayer.getCurrentPosition()
          local newPos = pos + 10000
          if newPos > dur then newPos = dur end
          tutorialMediaPlayer.seekTo(newPos)
        end
      end)
    end
  }))

  seekBar.setOnSeekBarChangeListener(luajava.createProxy("android.widget.SeekBar$OnSeekBarChangeListener", {
    onProgressChanged = function(sb, progress, fromUser)
      if fromUser then
        pcall(function()
          if tutorialMediaPlayer then
            tutorialMediaPlayer.seekTo(progress)
            durationTxt.setText(formatTime(progress) .. " / " .. formatTime(tutorialMediaPlayer.getDuration()))
          end
        end)
      end
    end,
    onStartTrackingTouch = function(sb) userIsSeeking = true end,
    onStopTrackingTouch = function(sb)
      userIsSeeking = false
      pcall(function()
        if tutorialMediaPlayer then
          tutorialMediaPlayer.seekTo(sb.getProgress())
        end
      end)
    end
  }))

  btnGoBack.setOnClickListener(View.OnClickListener({
    onClick = function(v)
      tutorialPlayerActive = false
      pcall(function()
        if tutorialMediaPlayer then
          tutorialMediaPlayer.stop()
          tutorialMediaPlayer.release()
          tutorialMediaPlayer = nil
        end
      end)
      dismissAllDialogsCustom()
    end
  }))
end

local function showTutorialListMenu()
    local name = "How to use Audio Bypass Pro"
    local url = "https://raw.githubusercontent.com/ali71rb-star/Audio-Bypass-Pro-Created-by-A-Brothers/main/How%20to%20use%20Audio%20Bypass%20Pro%20Created%20by%20A%20Brothers.mp3"
    showTutorialDownloadDialog(name, url)
end

local function openWhatsApp()
    pcall(function()
        local phoneNumber = "923477583735" 
        local message = "Hello, I need help or want to give feedback regarding the 'Audio Bypass Pro' extension."
        local url = "https://api.whatsapp.com/send?phone=" .. phoneNumber .. "&text=" .. URLEncoder.encode(message, "UTF-8")
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        service.startActivity(intent)
    end)
end

local function showMainMenu()
    Handler(Looper.getMainLooper()).post(Runnable({
        run = function()
            local options = {
                "Audio Stream Channel Settings", 
                "About & Credits", 
                "How to Use Audio Bypass Pro", 
                "Help & Feedback", 
                "Exit"
            }
            local builder = AlertDialog.Builder(service)
            builder.setTitle("Audio Bypass Pro Menu")
            builder.setItems(options, DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    if which == 0 then
                        showChannelSettings()
                    elseif which == 1 then
                        showAbout()
                    elseif which == 2 then
                        showTutorialListMenu()
                    elseif which == 3 then
                        openWhatsApp()
                    elseif which == 4 then
                        dialog.dismiss()
                    end
                end
            }))
            local dialog = builder.create()
            dialog.getWindow().setType(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY)
            dialog.show()
        end
    }))
end

local currentTime = 0
pcall(function() currentTime = luajava.bindClass("java.lang.System").currentTimeMillis() end)
if not _G.bp_last_time then _G.bp_last_time = 0 end
local timeDiff = currentTime - _G.bp_last_time
if timeDiff > 0 and timeDiff <= 700 then
    _G.bp_last_time = 0
    if _G.bp_handler and _G.bp_runnable then _G.bp_handler.removeCallbacks(_G.bp_runnable) end
    showMainMenu()
else
    _G.bp_last_time = currentTime
    if not _G.bp_handler then _G.bp_handler = Handler(Looper.getMainLooper()) end
    _G.bp_runnable = Runnable({ run = function() processBypassToggle() end })
    _G.bp_handler.postDelayed(_G.bp_runnable, 700)
end
