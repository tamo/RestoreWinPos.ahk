#Requires AutoHotkey v2.0
#Warn
#SingleInstance Force

;@Ahk2Exe-SetName        RestoreWinPos.ahk
;@Ahk2Exe-SetVersion     0.5
;@Ahk2Exe-SetDescription RestoreWinPos.ahk - workaround for Rapid HPD
; https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/
; https://superuser.com/questions/1292435

waitinterval := 100
maxloglen := A_Args.Length ? Integer(A_Args[1]) : 20 ; assign 0 if you don't want log by default
oldloglen := (maxloglen > 0) ? 0 : 20
clearlog()

A_TrayMenu.Add("Toggle log", togglelog)
A_TrayMenu.Add("Clear log", clearlog)
A_TrayMenu.Add("Show log", showlog)
TraySetIcon("shell32.dll", -26)

CoordMode("Mouse", "Screen")
Persistent(true)
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
  if ((maxloglen > 0) && !ok) {
    MsgBox("Failed to unregister " . kind . " notification", "Nevermind")
  }
  return 0
}

savewins(&winmap) {
  if (winmap.Has("restoring")) {
    ; maybe getting asleep while waiting for unlocking
    note("skip savewins")
    return
  }
  winmap.Clear()

  for (this_id in WinGetList(, , "Program Manager")) {
    if (WinExist(this_id)) {
      wp := normalwp(this_id, &x, &y, &showcmd)
      winmap[this_id] := { wp: wp, x: x, y: y, showcmd: showcmd }
    }
  }

  ; MouseGetPos(&mx, &my) returns (bogus big number, 0) in POWERSETTINGCHANGE just before APMSUSPEND
  ; because GetCursorPos() fails with ACCESS_DENIED but AutoHotkey ignores the failure
  if (!DllCall("GetCursorPos", "Ptr", lppoint := Buffer(8, 0))) {
    note(Format(" mouse error {} (5=ACCESS_DENIED)", DllCall("GetLastError", "UInt")))
  } else {
    mx := NumGet(lppoint, 0, "Int")
    my := NumGet(lppoint, 4, "Int")
    winmap["mouse"] := { x: mx, y: my }
    note(Format(" mouse ({},{})", mx, my))
  }
}

restorewins(winmap) {
  ; wait until unlocked
  ; also note that monitors can get asleep within this loop
  winmap["restoring"] := true
  while (!WinExist("A") || WinGetProcessName("A") = "LockApp.exe") {
    sleep(waitinterval)
  }

  for (this_id, d in winmap) {
    if (IsInteger(this_id) && WinExist(this_id)) {
      normalwp(this_id, &x, &y, &showcmd)
      if (d.x = x && d.y = y && d.showcmd = showcmd) {
        continue
      }
      WinRestore(this_id)
      WinRestore(this_id) ; needed twice for some apps e.g. maximized & minimized GitKraken
      DllCall("SetWindowPlacement", "Ptr", this_id, "Ptr", d.wp)
      note(Format(
        " {}({},{}) -> {}({},{}) {}",
        showcmdstr(showcmd), x, y,
        showcmdstr(d.showcmd), d.x, d.y,
        WinGetTitle(this_id)
      ))
    }
  }

  if (winmap.Has("mouse")) {
    MouseMove(winmap["mouse"].x, winmap["mouse"].y, 0)
    note(Format(" mouse ({},{})", winmap["mouse"].x, winmap["mouse"].y))
  } else {
    note(" mouse has not been saved")
  }

  winmap.Delete("restoring")
}

; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement
normalwp(hwnd, &x, &y, &showcmd) {
  NumPut("UInt", 44, wp := Buffer(44, 0))
  DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
  showcmd := NumGet(wp, 8, "UInt")
  x := NumGet(wp, 28, "Int")
  y := NumGet(wp, 32, "Int")
  return wp
}

; https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-showwindow
showcmdstr(showcmd) {
  switch(showcmd) {
    case 0: return "hidden"
    case 1: return ""
    case 2: return "min"
    case 3: return "max"
    default: return Format("[{}]", showcmd)
  }
}

note(txt) {
  global logtxt

  if (maxloglen > 0) {
    logtxt.Push(A_Now . ": " . txt)
  }
}

showlog(*) {
  global logtxt

  if (maxloglen = 0) {
    if ("Yes" = MsgBox("Enable logging?", "Logging is disabled", "YesNo")) {
      togglelog()
    }
    return
  }

  t := Format("Log (last {} lines):`n", maxloglen)
  loglen := Min(logtxt.Length, maxloglen)
  loop (loglen) {
    t .= logtxt[logtxt.Length - loglen + A_Index] . "`n"
  }
  MsgBox(t)
}

togglelog(*)
{
  global oldloglen, maxloglen

  tmp := oldloglen
  oldloglen := maxloglen
  maxloglen := 1 ; to always log it
  note("log " . ((oldloglen > 0) ? "disabled" : "enabled"))
  maxloglen := tmp
}

clearlog(*) {
  global logtxt := []
}