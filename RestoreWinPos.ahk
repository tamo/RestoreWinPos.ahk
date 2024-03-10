#Requires AutoHotkey v2.0
#Warn
#SingleInstance Force

;@Ahk2Exe-SetName        RestoreWinPos.ahk
;@Ahk2Exe-SetVersion     0.3
;@Ahk2Exe-SetDescription RestoreWinPos.ahk - workaround for Rapid HPD
; https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/
; https://superuser.com/questions/1292435

TraySetIcon("shell32.dll", -26)
CoordMode("Mouse", "Screen")
Persistent(true)
debug := false
registerpower()
return

registerpower() {
  ; for system-wide sleep
  SRN := DllCall("RegisterSuspendResumeNotification", "Ptr", A_ScriptHwnd, "UInt", 0, "Ptr")
  if (!SRN) {
    throw (OSError(A_LastError, -1, "RegisterSuspendResumeNotification"))
  }
  OnExit(unregister.Bind("SuspendResume", SRN))

  ; for monitor-only timeout
  ;@Ahk2Exe-SetCopyright https://www.autohotkey.com/boards/viewtopic.php?p=539708
  failed := DllCall(
    "ole32\CLSIDFromString",
    ; https://learn.microsoft.com/windows/win32/power/power-setting-guids#GUID_CONSOLE_DISPLAY_STATE
    "WStr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}",
    "Ptr", CLSID := Buffer(16),
    "UInt"
  )
  if (failed) {
    throw (Error("CLSIDFromString failed. Error: " . Format("{:#x}", failed)))
  }
  PSN := DllCall("RegisterPowerSettingNotification", "Ptr", A_ScriptHwnd, "Ptr", CLSID, "UInt", 0, "Ptr")
  if (!PSN) {
    throw (OSError(A_LastError, -1, "RegisterPowerSettingNotification"))
  }
  OnExit(unregister.Bind("PowerSetting", PSN))

  ; a notification is always emitted immediately after registering for it for some reason.
  ; this prevents seeing it
  Sleep(1)
  OnMessage(0x218, _WM_POWERBROADCAST)
}

; https://learn.microsoft.com/windows/win32/power/wm-powerbroadcast
_WM_POWERBROADCAST(wParam, lParam, msg, hwnd) {
  static oldpower := 1
  static wins := Map()

  Critical(1000)
  switch (wParam) {
    case (0x8013): ; PBT_POWERSETTINGCHANGE
      newpower := NumGet(lParam, 20, "UChar") ; 1 (on) -> 2 (dim) -> 0 (off) -> 1 (on)
      note("monitor power " . newpower)
      switch {
        case (oldpower and !newpower): savewins(&wins)
        case (!oldpower and newpower): restorewins(wins)
      }
      oldpower := newpower
    case (0x4): ; PBT_APMSUSPEND
      note("suspend")
      ; this is after PBT_POWERSETTINGCHANGE, where savewins() fails to MouseGetPos()
      savewins(&wins)
      oldpower := 0
    case (0x7): ; PBT_APMRESUMESUSPEND
      note("resume (suspend)")
      if (!oldpower) {
        restorewins(wins)
        oldpower := 1
      }
      /*
      case (0x12): ; PBT_APMRESUMEAUTOMATIC (never seen on my machine)
        note("resume (automatic)")
        if (!oldpower) {
          restorewins(wins)
          oldpower := 1
        }
      */
  }
  return true
}

; https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-unregisterpowersettingnotification
; https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-unregistersuspendresumenotification
; they return nonzero on success, while OnExit treats nonzero as failure
unregister(kind, hPowerNotify, *) {
  ok := DllCall("Unregister" . kind . "Notification", "Ptr", hPowerNotify)
  if (debug && !ok) {
    MsgBox("Failed to unregister " . kind . " notification", "Nevermind")
  }
  return 0
}

savewins(&winmap) {
  winmap.Clear()
  for (this_id in WinGetList(, , "Program Manager")) {
    if (WinExist(this_id)) {
      wp := normalwp(this_id, &x, &y)
      winmap[this_id] := { x: x, y: y, wp: wp }
    }
  }

  MouseGetPos(&mx, &my)
  winmap["mouse"] := { x: mx, y: my }
  note(Format(" mouse ({},{})", mx, my))
}

restorewins(winmap) {
  for (this_id, d in winmap) {
    if (this_id != "mouse" && WinExist(this_id)) {
      WinGetPos(&x, &y, , , this_id)
      if (d.x = x && d.y = y) {
        continue
      }
      note(Format(" ({},{}) -> ({},{}) {}", x, y, d.x, d.y, WinGetTitle(this_id)))
      WinRestore(this_id)
      DllCall("SetWindowPlacement", "Ptr", this_id, "Ptr", d.wp)
    }
  }

  ; wait until unlocked
  while (!WinExist("A") || WinGetProcessName("A") = "LockApp.exe") {
    sleep 500
  }
  MouseMove(winmap["mouse"].x, winmap["mouse"].y, 0)
  note(Format(" mouse ({},{})", winmap["mouse"].x, winmap["mouse"].y))
  note()
}

; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement
normalwp(hwnd, &x, &y) {
  NumPut("UInt", 44, wp := Buffer(44, 0))
  DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
  x := NumGet(wp, 28, "Int")
  y := NumGet(wp, 32, "Int")
  return wp
}

note(txt := false) {
  static logtxt := ""

  if (!debug) {
    return
  } else if (txt) {
    logtxt .= txt . "`n"
  } else {
    ToolTip(logtxt)
    logtxt := ""
  }
}