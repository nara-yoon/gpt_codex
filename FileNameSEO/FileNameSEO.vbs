Set shell = CreateObject("WScript.Shell")
scriptPath = Replace(WScript.ScriptFullName, "FileNameSEO.vbs", "FileNameSEO.ps1")
shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & scriptPath & """", 0, False

