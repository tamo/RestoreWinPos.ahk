# RestoreWinPos.ahk
A workaround for [Rapid HPD](https://devblogs.microsoft.com/directx/avoid-unexpected-app-rearrangement/)
(windows on multiple monitors move to a monitor when the computer returns from sleep)

Put it in [shell:startup](https://support.microsoft.com/windows/150da165-dcd9-7230-517b-cf3c295d89dd)

It saves windows' positions before sleeping,
and restores the positions after awaking

See https://www.autohotkey.com/boards/viewtopic.php?p=539708
and https://learn.microsoft.com/windows/win32/api/winuser/ns-winuser-windowplacement
