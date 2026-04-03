Write-Output "7% Completado"
# ==========================================================
# STORE + WINGET INSTALLER TODO EN UNO
# Orden:
#   1) Microsoft Store (solo LTSC/IoT)
#   2) VCLibs
#   3) UI.Xaml
#   4) Windows App Runtime
#   5) Winget
# ==========================================================

# TLS 1.2 obligatorio
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BasePath = "$env:TEMP\WingetFullInstall"
New-Item $BasePath -ItemType Directory -Force | Out-Null

# ==========================================================
# FUNCION → INSTALAR MICROSOFT STORE (LTSC / IoT)
# ==========================================================
function Install-StoreIfNeeded {

    $OfflineFolder = "$PSScriptRoot\StoreOffline"
    $TempDir       = "$BasePath\StorePack"
    $ZipFile       = "$BasePath\store_pack.zip"
    $CmdName       = "Add-Store.cmd"

    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $edition = $cv.EditionID

    $esLTSC = @("EnterpriseS","EnterpriseSN","IoTEnterpriseS") -contains $edition

    Write-Host "Edición detectada: $edition"

    if (-not $esLTSC) {
        Write-Host "No es LTSC/IoT → se omite instalación de Store"
        return
    }

    if (Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue) {
        Write-Host "Microsoft Store ya instalada"
        return
    }

    Write-Host "Instalando Microsoft Store..."

    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item $TempDir -ItemType Directory | Out-Null

    # ===============================
    # OFFLINE primero
    # ===============================
    if (Test-Path $OfflineFolder) {

        Write-Host "Modo OFFLINE detectado"
        Copy-Item "$OfflineFolder\*" $TempDir -Recurse -Force
    }
    else {

        Write-Host "Descargando última versión desde GitHub..."

        try {
            $latest = Invoke-RestMethod `
                "https://api.github.com/repos/mggons93/LTSC_STORE/releases/latest" `
                -ErrorAction Stop

            $StoreZipURL = $latest.zipball_url

            Write-Host "Versión: $($latest.tag_name)"

            Invoke-WebRequest $StoreZipURL -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop
            Expand-Archive $ZipFile -DestinationPath $TempDir -Force
        }
        catch {
            Write-Host "ERROR descargando Microsoft Store → se omite"
            Write-Host $_.Exception.Message
            return
        }
    }

    # ===============================
    # Ejecutar Add-Store.cmd
    # ===============================
    $cmdPath = Get-ChildItem $TempDir -Recurse -Filter $CmdName |
               Select-Object -First 1 -ExpandProperty FullName

    if ($cmdPath) {
        Start-Process $cmdPath -Verb RunAs -Wait
    }
    else {
        Write-Host "No se encontró Add-Store.cmd"
    }
}

# ==========================================================
# FUNCIONES DE VALIDACION
# ==========================================================
function Test-VCLibsInstalled {
    $pkg = Get-AppxPackage -AllUsers "Microsoft.VCLibs.140.00.UWPDesktop" -ErrorAction SilentlyContinue
    if (-not $pkg) {
        $pkg = Get-AppxPackage -AllUsers "Microsoft.VCLibs.140.00" -ErrorAction SilentlyContinue
    }
    return ($null -ne $pkg)
}

function Test-UIXamlInstalled {
    $pkg = Get-AppxPackage -AllUsers "Microsoft.UI.Xaml.2.7" -ErrorAction SilentlyContinue
    return ($null -ne $pkg)
}

function Test-WindowsAppRuntimeInstalled {
    # Buscar en el registro la instalación de Windows App Runtime
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($regPath in $regPaths) {
        if (Test-Path $regPath) {
            $entries = Get-ChildItem $regPath -ErrorAction SilentlyContinue |
                Get-ItemProperty -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "Windows App Runtime*" -or $_.DisplayName -like "WindowsAppRuntime*" }
            if ($entries) {
                return $true
            }
        }
    }
    # También verificar como paquete AppX
    $pkg = Get-AppxPackage -AllUsers "Microsoft.WindowsAppRuntime*" -ErrorAction SilentlyContinue
    return ($null -ne $pkg)
}

function Test-WingetInstalled {
    return ($null -ne (Get-Command winget -ErrorAction SilentlyContinue))
}

# ==========================================================
# FUNCION → INSTALAR WINGET SIN STORE
# ==========================================================
function Install-Winget {

    $VCLibsUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $XamlUrl    = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx"
    $RuntimeUrl = "https://aka.ms/windowsappsdk/1.8/1.8.260101001/windowsappruntimeinstall-x64.exe"
    $WingetOldUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.6.3482/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WingetUrl  = "https://aka.ms/getwinget"

    $VCLibsPath  = "$BasePath\VCLibs.appx"
    $XamlPath    = "$BasePath\UI.Xaml.appx"
    $RuntimeExe  = "$BasePath\Runtime.exe"
    $WingetOldPath = "$BasePath\Wingetold.msixbundle"
    $WingetPath  = "$BasePath\Winget.msixbundle"

    $wingetYaInstalado = Test-WingetInstalled

    try {

        # ----------------------------------------------------------
        # 1. VCLibs
        # ----------------------------------------------------------
        if (Test-VCLibsInstalled) {
            Write-Host "VCLibs ya instalado → se omite"
        }
        else {
            Write-Host "Descargando VCLibs..."
            Invoke-WebRequest $VCLibsUrl -OutFile $VCLibsPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Instalando VCLibs..."
            Add-AppxPackage $VCLibsPath -ErrorAction Stop
        }

        # ----------------------------------------------------------
        # 2. UI.Xaml
        # ----------------------------------------------------------
        if (Test-UIXamlInstalled) {
            Write-Host "UI.Xaml ya instalado → se omite"
        }
        else {
            Write-Host "Descargando UI.Xaml..."
            Invoke-WebRequest $XamlUrl -OutFile $XamlPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Instalando UI.Xaml..."
            Add-AppxPackage $XamlPath -ErrorAction Stop
        }

        # Esperar a que Windows registre los paquetes AppX antes de continuar
        Start-Sleep 2

        # ----------------------------------------------------------
        # 3. Windows App Runtime
        # ----------------------------------------------------------
        if (Test-WindowsAppRuntimeInstalled) {
            Write-Host "Windows App Runtime ya instalado → se omite"
        }
        else {
            Write-Host "Descargando Windows App Runtime..."
            Invoke-WebRequest $RuntimeUrl -OutFile $RuntimeExe -UseBasicParsing -ErrorAction Stop
            Write-Host "Instalando Windows App Runtime..."
            Start-Process $RuntimeExe -ArgumentList "/quiet" -Wait
            # Esperar a que el instalador registre correctamente el runtime
            Start-Sleep 3
        }

        # ----------------------------------------------------------
        # 4. Winget
        # ----------------------------------------------------------
        if ($wingetYaInstalado) {
            Write-Host "Winget ya instalado → actualizando a la última versión..."
            Invoke-WebRequest $WingetUrl -OutFile $WingetPath -UseBasicParsing -ErrorAction Stop
            Add-AppxPackage $WingetPath -ErrorAction Stop
        }
        else {
            Write-Host "Winget no encontrado → instalando desde cero..."

            Write-Host "Descargando Winget (versión base)..."
            Invoke-WebRequest $WingetOldUrl -OutFile $WingetOldPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Instalando Winget (versión base)..."
            Add-AppxPackage $WingetOldPath -ErrorAction Stop
            # Esperar a que Winget base se registre antes de instalar la actualización
            Start-Sleep 3

            Write-Host "Descargando Winget (versión actual)..."
            Invoke-WebRequest $WingetUrl -OutFile $WingetPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Actualizando Winget a la versión actual..."
            Add-AppxPackage $WingetPath -ErrorAction Stop
        }

        # ----------------------------------------------------------
        # Verificacion final
        # ----------------------------------------------------------
        Write-Host "Verificando instalación de Winget..."
        if (Test-WingetInstalled) {
            Write-Host "Winget instalado correctamente"
            winget --version
        }
        else {
            Write-Host "Winget no se instaló correctamente"
        }
    }
    catch {
        Write-Host "Error instalando Winget:"
        Write-Host $_.Exception.Message
    }
    finally {
        # ----------------------------------------------------------
        # Limpieza de archivos temporales
        # ----------------------------------------------------------
        Write-Host "Limpiando archivos temporales..."
        Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ==========================================================
# EJECUCIÓN PRINCIPAL
# ==========================================================
Install-StoreIfNeeded
Install-Winget

Write-Host "Proceso completo finalizado."
