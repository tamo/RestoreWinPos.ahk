# RestoreWinPos.ahk
A workaround for [Rapid HPD](https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/)
(windows on multiple monitors move to a monitor when monitors timeout)

Put it (or a shortcut .lnk to it) in [shell:startup](https://support.microsoft.com/windows/150da165-dcd9-7230-517b-cf3c295d89dd)

It saves [placements](https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement) of windows (and mouse) before sleeping,
and restores them after awaking

## options
`RestoreWinPos.ahk [loglen [hotkey [msgnum [waitms]]]]`

- loglen: number of log lines to show
  - default: 0 (disabled)
  - set number of moved windows + 10 or more
- hotkey: shortcut symbol to trigger sleep
  - default: "disabled"
  - set any [hotkey](https://www.autohotkey.com/docs/v2/Hotkeys.htm) such as "Pause" or "VKC1"
- msgnum: message number to SendMessage from another script
  - default: 0 (disabled)
  - set any [message number](https://www.autohotkey.com/docs/v2/misc/SendMessageList.htm) such as 0x5ADD
  - after `DetectHiddenWindows(true)`, another script can `SendMessage(thisvalue, 16,,, "RestoreWinPos ahk_class AutoHotkey")` to make the machine sleep
- waitms: milliseconds to wait between checks
  - default: 100 (0.1 second)
  - used in lock-screen (waiting for unlock) and hotkey (waiting for release)
  - lower value increases quickness and power consumption

Use hotkey or msgnum to keep your mouse cursor position over a sleep.
(Monitor timeouts don't move mouse cursor even without them)
