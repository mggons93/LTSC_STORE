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
# FUNCION → INSTALAR WINGET SIN STORE
# ==========================================================
function Install-Winget {

    $VCLibsUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $XamlUrl    = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx"
    $RuntimeUrl = "https://aka.ms/windowsappsdk/1.8/1.8.260101001/windowsappruntimeinstall-x64.exe"
    $WingetoldUrl = "https://github.com/microsoft/winget-cli/releases/download/v1.6.3482/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $WingetUrl  = "https://aka.ms/getwinget"

    $VCLibsPath  = "$BasePath\VCLibs.appx"
    $XamlPath    = "$BasePath\UI.Xaml.appx"
    $RuntimeExe  = "$BasePath\Runtime.exe"
    $WingetoldPath = "$BasePath\Wingetold.appxbundle"
    $WingetPath  = "$BasePath\Winget.appxbundle"

    $wingetExists = Get-Command winget -ErrorAction SilentlyContinue

    try {

        if ($wingetExists) {
            # -------------------------------------------------------
            # Winget YA existe → solo actualizar a la última versión
            # -------------------------------------------------------
            Write-Host "Winget detectado → descargando actualización..."
            Invoke-WebRequest $WingetUrl -OutFile $WingetPath -UseBasicParsing

            Write-Host "Actualizando Winget a la última versión..."
            Add-AppxPackage $WingetPath
        }
        else {
            # -------------------------------------------------------
            # Winget NO existe → instalar todos los componentes
            # -------------------------------------------------------
            Write-Host "Winget no encontrado → iniciando instalación completa..."

            # --- VCLibs ---
            if (Get-AppxPackage -AllUsers "Microsoft.VCLibs.140.00.UWPDesktop" -ErrorAction SilentlyContinue) {
                Write-Host "VCLibs ya instalado → se omite descarga e instalación"
            }
            else {
                Write-Host "VCLibs no encontrado → descargando e instalando..."
                Invoke-WebRequest $VCLibsUrl -OutFile $VCLibsPath -UseBasicParsing
                Add-AppxPackage $VCLibsPath
                Write-Host "VCLibs instalado correctamente"
            }

            # --- UI.Xaml ---
            if (Get-AppxPackage -AllUsers "Microsoft.UI.Xaml.2.7" -ErrorAction SilentlyContinue) {
                Write-Host "UI.Xaml ya instalado → se omite descarga e instalación"
            }
            else {
                Write-Host "UI.Xaml no encontrado → descargando e instalando..."
                Invoke-WebRequest $XamlUrl -OutFile $XamlPath -UseBasicParsing
                Add-AppxPackage $XamlPath
                Write-Host "UI.Xaml instalado correctamente"
            }

            Start-Sleep 2

            # --- Windows App Runtime ---
            if (Get-AppxPackage -AllUsers "Microsoft.WindowsAppRuntime*" -ErrorAction SilentlyContinue) {
                Write-Host "Windows App Runtime ya instalado → se omite descarga e instalación"
            }
            else {
                Write-Host "Windows App Runtime no encontrado → descargando e instalando..."
                Invoke-WebRequest $RuntimeUrl -OutFile $RuntimeExe -UseBasicParsing
                Write-Host "Instalando Windows App Runtime..."
                Start-Process $RuntimeExe -ArgumentList "/quiet" -Wait
                Write-Host "Windows App Runtime instalado correctamente"
            }

            Start-Sleep 3

            # --- Winget (versión base) ---
            Write-Host "Descargando Winget versión base..."
            Invoke-WebRequest $WingetoldUrl -OutFile $WingetoldPath -UseBasicParsing
            Write-Host "Instalando Winget versión base..."
            Add-AppxPackage $WingetoldPath

            Start-Sleep 3

            # --- Winget (última versión) ---
            Write-Host "Descargando última versión de Winget..."
            Invoke-WebRequest $WingetUrl -OutFile $WingetPath -UseBasicParsing
            Write-Host "Actualizando Winget a la última versión..."
            Add-AppxPackage $WingetPath
        }

        # -------------------------------------------------------
        # Verificación final
        # -------------------------------------------------------
        Write-Host "Verificando instalación de Winget..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
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
        # -------------------------------------------------------
        # Limpieza de archivos temporales
        # -------------------------------------------------------
        Write-Host "Limpiando archivos temporales..."
        Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Limpieza completada"
    }
}
# ==========================================================
# EJECUCIÓN PRINCIPAL
# ==========================================================
Install-StoreIfNeeded
Install-Winget

Write-Host "Proceso completo finalizado."
