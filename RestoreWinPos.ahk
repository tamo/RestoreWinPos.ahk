#Requires AutoHotkey v2.0
#Warn
#SingleInstance Force

; A simple workaround for the Rapid HPD problem
; https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/
; https://superuser.com/questions/1292435

CoordMode("Mouse", "Screen")
Persistent(true)
registerpower()
return

; https://www.autohotkey.com/boards/viewtopic.php?p=539708
registerpower() {
  CLSID := Buffer(16)
  if (res :=
    DllCall("ole32\CLSIDFromString",
      ; GUID_CONSOLE_DISPLAY_STATE_
      "WStr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}",
      "Ptr", CLSID,
      "UInt")
  ) {
    throw (Error("CLSIDFromString failed. Error: " . Format("{:#x}", res)))
  }

  if (! ;hPowerNotify :=
    DllCall('RegisterPowerSettingNotification',
      'Ptr', A_ScriptHwnd,
      'Ptr', CLSID,
      'UInt', 0,
      'Ptr')
  ) {
    throw (OSError(A_LastError, -1, 'RegisterPowerSettingNotification'))
  }

  Sleep(1) ; a notification is always emitted immediately after registering for it for some reason. this prevents seeing it
  OnMessage(0x218, _WM_POWERBROADCAST)
}

_WM_POWERBROADCAST(wParam, lParam, msg, hwnd) {
  Critical(1000)
  static oldpower := 1
  static newpower
  static wins := Map()

  if (wParam = 0x8013) { ; PBT_POWERSETTINGCHANGE
    newpower := NumGet(lParam, 20, 'UChar') ; 0 (off) or 1 (on).
    switch {
      case (oldpower and !newpower): savewins(&wins)
      case (!oldpower and newpower): restorewins(wins)
    }
    oldpower := newpower
  }
  return (true)
}

savewins(&winmap) {
  winmap.Clear()

  MouseGetPos(&mx, &my)
  winmap["mouse"] := { x: mx, y: my }

  for (this_id in WinGetList(, , "Program Manager")) {
    if (WinExist(this_id)) {
      wp := normalwp(this_id, &x, &y)
      winmap[this_id] := { x: x, y: y, wp: wp }
    }
  }
}

restorewins(winmap) {
  for (this_id, d in winmap) {
    if (this_id = "mouse") {
      MouseMove(d.x, d.y, 0)
      continue
    }

    if (WinExist(this_id)) {
      WinGetPos(&x, &y, , , this_id)
      if (d.x = x && d.y = y) {
        continue
      }
      WinRestore(this_id)
      DllCall("SetWindowPlacement", "Ptr", this_id, "Ptr", d.wp)
    }
  }
}

; https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement
normalwp(hwnd, &x, &y) {
  NumPut("UInt", 44, wp := Buffer(44, 0))
  DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", wp)
  x := NumGet(wp, 28, "Int")
  y := NumGet(wp, 32, "Int")
  return wp
}
