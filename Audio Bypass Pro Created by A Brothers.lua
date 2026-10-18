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
import "android.view.Gravity"
import "android.view.WindowManager"
import "android.view.View"
import "android.graphics.Typeface"
import "java.io.File"

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
                elseif action == BluetoothDevice.ACTION_ACL_CONNECTED then
                    if _G.bypass_media_is_on then
                        Handler(Looper.getMainLooper()).postDelayed(Runnable({
                            run = function()
                                if _G.bypass_media_is_on then
                                    turnOnBypass(true, true)
                                end
                            end
                        }), 1500)
                    end
                end
            end
        })
        local filter = IntentFilter()
        filter.addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
        filter.addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
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
            local options = {"Audio Stream Channel Settings", "About & Credits", "Help & Feedback", "Exit"}
            local builder = AlertDialog.Builder(service)
            builder.setTitle("Audio Bypass Pro Menu")
            builder.setItems(options, DialogInterface.OnClickListener({
                onClick = function(dialog, which)
                    if which == 0 then
                        showChannelSettings()
                    elseif which == 1 then
                        showAbout()
                    elseif which == 2 then
                        openWhatsApp()
                    elseif which == 3 then
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
