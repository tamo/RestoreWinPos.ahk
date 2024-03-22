#Requires AutoHotkey v2.0
#Warn
#SingleInstance Force

;@Ahk2Exe-SetName        RestoreWinPos.ahk
;@Ahk2Exe-SetVersion     0.7
;@Ahk2Exe-SetDescription RestoreWinPos.ahk - workaround for Rapid HPD
; https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/
; https://superuser.com/questions/1292435

maxloglen := (A_Args.Length > 0) ? Integer(A_Args[1]) : 0
sleepkey := (A_Args.Length > 1) ? A_Args[2] : "disabled"
msgnumber := (A_Args.Length > 2) ? Integer(A_Args[3]) : 0
waitinterval := (A_Args.Length > 3) ? Integer(A_Args[4]) : 100
if (A_Args.Length > 4) {
  MsgBox(
    "Usage: " . A_ScriptName . " [loglen [hotkey [msgnum [waitms]]]]`n`n" .
    " loglen: number of log lines to show (default: 0 [disabled])`n" .
    " hotkey: symbol to trigger sleep (default: disabled)`n" .
    " msgnum: number to SendMessage from another script (default: 0 [disabled])`n" .
    " waitms: milliseconds to wait between checks (default: 100)",
    "Too many arguments"
  )
  ExitApp()
}

oldloglen := (maxloglen > 0) ? 0 : 20
clearlog()

A_TrayMenu.Add("Toggle log", togglelog)
A_TrayMenu.Add("Clear log", clearlog)
A_TrayMenu.Add("Show log", showlog)
TraySetIcon("shell32.dll", -26)

CoordMode("Mouse", "Screen")
Persistent(true)
registerpower()
if (sleepkey != "disabled") {
  Hotkey(sleepkey, saveandsleep, "On")
}
if (msgnumber > 0) {
  OnMessage(msgnumber, receivemsg)
}
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
  global wins := Map()
  OnMessage(0x218, _WM_POWERBROADCAST)
}

; https://learn.microsoft.com/windows/win32/power/wm-powerbroadcast
_WM_POWERBROADCAST(wParam, lParam, msg, hwnd) {
  static oldpower := 1

  Critical(1000)
  switch (wParam) {
    case (0x8013): ; PBT_POWERSETTINGCHANGE
      newpower := NumGet(lParam, 20, "UChar") ; 1 (on) -> 2 (dim) -> 0 (off) -> 1 (on)
      note("monitor power " . newpower)
      switch {
        case (oldpower and !newpower): savewins()
        case (!oldpower and newpower): restorewins()
      }
      oldpower := newpower
      /*
      case (0x4): ; PBT_APMSUSPEND (called after PBT_POWERSETTINGCHANGE)
        note("suspend")
        savewins()
        oldpower := 0
      */
    case (0x7): ; PBT_APMRESUMESUSPEND
      note("resume")
      if (!oldpower) {
        restorewins()
        oldpower := 1
      }
      /*
      case (0x12): ; PBT_APMRESUMEAUTOMATIC (never seen on my machine)
        note("resume (automatic)")
        if (!oldpower) {
          restorewins()
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

receivemsg(wParam, *) {
  switch (wParam) {
    case 1: note("message 1 (save)"), savewins(true)
    case 2: note("message 2 (restore)"), restorewins()
    case 16: note("message 16 (sleep)"), saveandsleep()
  }
}

savewins(force := false) {
  global wins

  if (!force && wins.Count > 0) {
    note("skip savewins")
    return
  }

  for (this_id in WinGetList(, , "Program Manager")) {
    if (WinExist(this_id)) {
      wins[this_id] := getwinplace(this_id)
    }
  }

  ; MouseGetPos(&mx, &my) returns (bogus big number, 0) in POWERSETTINGCHANGE just before APMSUSPEND
  ; because GetCursorPos() fails with ACCESS_DENIED but AutoHotkey ignores the failure
  if (!DllCall("GetCursorPos", "Ptr", lppoint := Buffer(8, 0))) {
    note(Format(" mouse error {} (5=ACCESS_DENIED)", DllCall("GetLastError", "UInt")))
  } else {
    mx := NumGet(lppoint, 0, "Int")
    my := NumGet(lppoint, 4, "Int")
    wins["mouse"] := { x: mx, y: my }
    note(Format(" mouse ({},{})", mx, my))
  }
}

restorewins() {
  global wins

  ; wait until unlocked
  ; also note that monitors can get asleep within this loop
  while (!WinExist("A") || WinGetProcessName("A") = "LockApp.exe") {
    sleep(waitinterval)
  }

  for (this_id, d in wins) {
    if (IsInteger(this_id) && WinExist(this_id)) {
      c := getwinplace(this_id)
      if (samewp(c, d)) {
        continue
      }
      WinRestore(this_id)
      WinRestore(this_id) ; needed twice for some apps e.g. maximized & minimized GitKraken
      DllCall("SetWindowPlacement", "Ptr", this_id, "Ptr", d.wp)
      note(Format(" {} -> {} {}", c.note, d.note, c.title))
    }
  }

  if (wins.Has("mouse")) {
    d := wins["mouse"]
    MouseGetPos(&cx, &cy)
    MouseMove(d.x, d.y, 0)
    note(Format(" mouse ({},{}) -> ({},{})", cx, cy, d.x, d.y))
  } else {
    note(" mouse has not been saved")
  }

  wins.Clear()
}

; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement
getwinplace(hwnd) {
  NumPut("UInt", 44, wp := Buffer(44, 0))
  DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)

  ; some apps moves without updating wp so we need to GetWindowRect too
  ; restorewins doesn't need to WinMove, SetWindowPlacement is enough
  WinGetPos(&rx, &ry, &rw, &rh, hwnd)

  return {
    wp: wp,
    flags: NumGet(wp, 4, "UInt"),
    showcmd: showcmd := NumGet(wp, 8, "UInt"),
    minx: NumGet(wp, 12, "Int"),
    miny: NumGet(wp, 16, "Int"),
    maxx: NumGet(wp, 20, "Int"),
    maxy: NumGet(wp, 24, "Int"),
    x: x := NumGet(wp, 28, "Int"),
    y: y := NumGet(wp, 32, "Int"),
    rx: rx,
    ry: ry,
    title: WinGetTitle(hwnd),
    note: Format(
      "{}({},{})[{},{}]",
      showcmdstr(showcmd), x, y, rx, ry
    )
  }
}

samewp(c, d) {
  return (
    d.flags = c.flags &&
    d.showcmd = c.showcmd &&
    (!(d.flags & 1) || ; WPF_SETMINPOSITION
      (
        d.minx = c.minx &&
        d.miny = c.miny
      )
    ) &&
    d.maxx = c.maxx &&
    d.maxy = c.maxy &&
    d.x = c.x &&
    d.y = c.y &&
    d.rx = c.rx &&
    d.ry = c.ry
  )
}

; https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-showwindow
showcmdstr(showcmd) {
  switch (showcmd) {
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

; if you want to call this function from other scripts, do
;   DetectHiddenWindows(true) ; AHK without a Gui is hidden
;   SendMessage(msgnumber, 16,,, "RestoreWinPos ahk_class AutoHotkey")
saveandsleep(keywithmod := "") {
  if (keywithmod) {
    note(Format("hotkey [{}]", keywithmod))
    ; wait till the key is up
    try { ; keyname may be inappropriate for GetKeyState
      thiskey := RegExReplace(keywithmod, "^\W*")
      note(Format(" rawkey [{}]", thiskey))
      while (GetKeyState(thiskey, "P")) {
        Sleep (waitinterval)
      }
    } catch as e {
      note(" error " . e)
    }
  }

  savewins(true)

  note("suspend")
  ; https://www.autohotkey.com/docs/v2/lib/Shutdown.htm#ExSuspend
  DllCall("PowrProf\SetSuspendState", "Int", 0, "Int", 0, "Int", 0)
}