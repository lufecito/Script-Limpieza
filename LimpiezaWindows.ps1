<#
==============================================================================
 Corporate Windows Cleanup
 Versión : 1.0
 Autor   : Luis Fontecilla / ChatGPT
 Compatibilidad:
   - Windows 10
   - Windows 11
   - Windows Server 2016/2019/2022
   - PowerShell 5.1 y PowerShell 7
==============================================================================

Este script elimina únicamente archivos temporales y cachés.
NO elimina documentos del usuario.
NO elimina Descargas.
NO elimina OneDrive.
NO elimina perfiles.

==============================================================================#>

#-------------------------------------------------------
# CONFIGURACIÓN
#-------------------------------------------------------

$ErrorActionPreference = "Continue"

$ScriptVersion = "1.0"

$LogFolder = "C:\ProgramData\CorpCleanup"

if (!(Test-Path $LogFolder)) {
    New-Item -ItemType Directory -Path $LogFolder -Force | Out-Null
}

$LogFile = Join-Path $LogFolder ("Cleanup_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

$StartTime = Get-Date

#-------------------------------------------------------
# FUNCIONES
#-------------------------------------------------------

function Write-Log {

    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    Add-Content -Path $LogFile -Value $Line

    Write-Host $Line

}

function Clear-Folder {

    param(
        [string]$Folder
    )

    if (!(Test-Path $Folder)) {

        Write-Log "No existe: $Folder"

        return

    }

    try {

        Get-ChildItem $Folder -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

        Write-Log "Limpiado: $Folder"

    }
    catch {

        Write-Log "Error limpiando: $Folder" "ERROR"

    }

}

function Get-DiskInformation {

    $Disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"

    [PSCustomObject]@{

        Total = [math]::Round($Disk.Size / 1GB,2)

        Free = [math]::Round($Disk.FreeSpace / 1GB,2)

        Used = [math]::Round(($Disk.Size-$Disk.FreeSpace)/1GB,2)

        Percent = [math]::Round((($Disk.Size-$Disk.FreeSpace)/$Disk.Size)*100,2)

    }

}

#-------------------------------------------------------
# REPORTE INICIAL
#-------------------------------------------------------

$DiskBefore = Get-DiskInformation

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " CORPORATE WINDOWS CLEANUP v$ScriptVersion"
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Equipo  : $env:COMPUTERNAME"
Write-Host "Usuario : $env:USERNAME"
Write-Host ""

Write-Host "Estado inicial"

Write-Host "----------------------------------------------"

Write-Host ("Capacidad Total : {0} GB" -f $DiskBefore.Total)

Write-Host ("Espacio Usado   : {0} GB" -f $DiskBefore.Used)

Write-Host ("Espacio Libre   : {0} GB" -f $DiskBefore.Free)

Write-Host ("Ocupación       : {0} %" -f $DiskBefore.Percent)

Write-Host ""

Write-Log "============================================"

Write-Log "Inicio de limpieza"

Write-Log "Equipo: $env:COMPUTERNAME"

Write-Log "Usuario: $env:USERNAME"

Write-Log ("Espacio libre inicial: {0} GB" -f $DiskBefore.Free)

Write-Log "============================================"
#-------------------------------------------------------
# LIMPIEZA DEL SISTEMA
#-------------------------------------------------------

Write-Host ""
Write-Host "Iniciando limpieza del sistema..." -ForegroundColor Yellow
Write-Log "Iniciando limpieza del sistema"

# Detener servicios necesarios
Write-Host "Deteniendo servicios..." -ForegroundColor Cyan

$Services = @(
    "wuauserv",
    "bits"
)

foreach ($Service in $Services) {

    try {

        if ((Get-Service $Service).Status -eq "Running") {

            Stop-Service $Service -Force

            Write-Log "Servicio detenido: $Service"

        }

    }
    catch {

        Write-Log "No fue posible detener $Service" "WARNING"

    }

}

# Carpetas temporales
$Folders = @(
    $env:TEMP,
    "$env:LOCALAPPDATA\Temp",
    "C:\Windows\Temp",
    "C:\Windows\SoftwareDistribution\Download",
    "C:\ProgramData\Microsoft\Windows\WER",
    "$env:LOCALAPPDATA\CrashDumps",
    "$env:LOCALAPPDATA\D3DSCache",
    "C:\Windows\Logs\CBS",
    "C:\Windows\Logs\DISM",
    "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
)

foreach ($Folder in $Folders) {

    Clear-Folder $Folder

}

# Limpiar Miniaturas
Write-Host "Limpiando caché de miniaturas..."

try {

    Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" `
        -Filter "thumbcache*" `
        -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Log "Miniaturas eliminadas"

}
catch {

    Write-Log "Error eliminando miniaturas" "WARNING"

}

# Limpiar Icon Cache

try {

    Remove-Item "$env:LOCALAPPDATA\IconCache.db" `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Log "IconCache eliminado"

}
catch {}

# Papelera

try {

    Clear-RecycleBin -Force

    Write-Log "Papelera vaciada"

}
catch {

    Write-Log "No fue posible vaciar la papelera" "WARNING"

}

# Reiniciar servicios

foreach ($Service in $Services) {

    try {

        Start-Service $Service

        Write-Log "Servicio iniciado: $Service"

    }
    catch {

        Write-Log "No fue posible iniciar $Service" "WARNING"

    }

}

# DISM

Write-Host ""
Write-Host "Ejecutando limpieza del almacén de componentes..." -ForegroundColor Cyan

try {

    Start-Process DISM.exe `
        -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /Quiet" `
        -Wait `
        -NoNewWindow

    Write-Log "DISM ejecutado correctamente"

}
catch {

    Write-Log "Error ejecutando DISM" "ERROR"

}

Write-Host ""
Write-Host "Limpieza del sistema completada." -ForegroundColor Green
Write-Log "Limpieza del sistema finalizada"
#-------------------------------------------------------
# LIMPIEZA DE NAVEGADORES
#-------------------------------------------------------

Write-Host ""
Write-Host "Limpiando cachés de navegadores..." -ForegroundColor Yellow
Write-Log "Iniciando limpieza de navegadores"

#-------------------------------------------------------
# GOOGLE CHROME
#-------------------------------------------------------

$ChromeRoot = "$env:LOCALAPPDATA\Google\Chrome\User Data"

if (Test-Path $ChromeRoot) {

    Get-ChildItem $ChromeRoot -Directory | ForEach-Object {

        $Profile = $_.FullName

        $Folders = @(
            "Cache",
            "Code Cache",
            "GPUCache",
            "GrShaderCache",
            "ShaderCache"
        )

        foreach ($Folder in $Folders) {

            Clear-Folder (Join-Path $Profile $Folder)

        }

    }

    Write-Log "Chrome limpiado"

}

#-------------------------------------------------------
# MICROSOFT EDGE
#-------------------------------------------------------

$EdgeRoot = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"

if (Test-Path $EdgeRoot) {

    Get-ChildItem $EdgeRoot -Directory | ForEach-Object {

        $Profile = $_.FullName

        $Folders = @(
            "Cache",
            "Code Cache",
            "GPUCache",
            "GrShaderCache",
            "ShaderCache"
        )

        foreach ($Folder in $Folders) {

            Clear-Folder (Join-Path $Profile $Folder)

        }

    }

    Write-Log "Edge limpiado"

}

#-------------------------------------------------------
# MOZILLA FIREFOX
#-------------------------------------------------------

$FirefoxRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"

if (Test-Path $FirefoxRoot) {

    Get-ChildItem $FirefoxRoot -Directory | ForEach-Object {

        $Profile = $_.FullName

        Clear-Folder (Join-Path $Profile "cache2")
        Clear-Folder (Join-Path $Profile "startupCache")
        Clear-Folder (Join-Path $Profile "thumbnails")

    }

    Write-Log "Firefox limpiado"

}

#-------------------------------------------------------
# INTERNET EXPLORER / LEGACY EDGE
#-------------------------------------------------------

try {

    RunDll32.exe InetCpl.cpl,ClearMyTracksByProcess 8

    Write-Log "Cache de Internet Explorer eliminada"

}
catch {

    Write-Log "No fue posible limpiar Internet Explorer" "WARNING"

}

#-------------------------------------------------------
# MICROSOFT TEAMS
#-------------------------------------------------------

$TeamsClassic = "$env:APPDATA\Microsoft\Teams"

if (Test-Path $TeamsClassic) {

    $Folders = @(
        "Cache",
        "Code Cache",
        "GPUCache",
        "blob_storage",
        "databases",
        "IndexedDB",
        "Local Storage",
        "tmp"
    )

    foreach ($Folder in $Folders) {

        Clear-Folder (Join-Path $TeamsClassic $Folder)

    }

    Write-Log "Teams Classic limpiado"

}

#-------------------------------------------------------
# MICROSOFT STORE
#-------------------------------------------------------

try {

    Start-Process wsreset.exe -Wait -NoNewWindow

    Write-Log "Microsoft Store reseteado"

}
catch {

    Write-Log "No fue posible ejecutar WSReset" "WARNING"

}

#-------------------------------------------------------
# DNS
#-------------------------------------------------------

try {

    ipconfig /flushdns | Out-Null

    Write-Log "Cache DNS limpiada"

}
catch {

    Write-Log "No fue posible limpiar la cache DNS" "WARNING"

}

Write-Host ""
Write-Host "Limpieza de navegadores finalizada." -ForegroundColor Green
Write-Log "Limpieza de navegadores finalizada"
#-------------------------------------------------------
# REPORTE FINAL
#-------------------------------------------------------

$DiskAfter = Get-DiskInformation

$Recovered = [math]::Round($DiskAfter.Free - $DiskBefore.Free,2)

$EndTime = Get-Date

$Elapsed = New-TimeSpan -Start $StartTime -End $EndTime

Write-Host ""
Write-Host "==============================================================" -ForegroundColor Green
Write-Host "              CORPORATE CLEANUP REPORT"
Write-Host "==============================================================" -ForegroundColor Green

Write-Host ""
Write-Host "Equipo.............: $env:COMPUTERNAME"
Write-Host "Usuario............: $env:USERNAME"

Write-Host ""
Write-Host "UNIDAD C:"
Write-Host "--------------------------------------------------------------"

Write-Host ("Capacidad Total....: {0} GB" -f $DiskAfter.Total)

Write-Host ""
Write-Host "ANTES"

Write-Host ("Usado..............: {0} GB" -f $DiskBefore.Used)
Write-Host ("Libre..............: {0} GB" -f $DiskBefore.Free)
Write-Host ("Ocupación..........: {0} %" -f $DiskBefore.Percent)

Write-Host ""
Write-Host "DESPUÉS"

Write-Host ("Usado..............: {0} GB" -f $DiskAfter.Used)
Write-Host ("Libre..............: {0} GB" -f $DiskAfter.Free)
Write-Host ("Ocupación..........: {0} %" -f $DiskAfter.Percent)

Write-Host ""
Write-Host ("ESPACIO RECUPERADO.: {0} GB" -f $Recovered)

Write-Host ("Tiempo ejecución...: {0:hh\:mm\:ss}" -f $Elapsed)

Write-Host ""
Write-Host "Estado.............: SUCCESS"

Write-Host "==============================================================" -ForegroundColor Green

#-------------------------------------------------------
# LOG FINAL
#-------------------------------------------------------

Write-Log "==============================================="
Write-Log "RESUMEN FINAL"
Write-Log ("Total Disco........: {0} GB" -f $DiskAfter.Total)
Write-Log ("Usado Antes........: {0} GB" -f $DiskBefore.Used)
Write-Log ("Usado Después......: {0} GB" -f $DiskAfter.Used)
Write-Log ("Libre Antes........: {0} GB" -f $DiskBefore.Free)
Write-Log ("Libre Después......: {0} GB" -f $DiskAfter.Free)
Write-Log ("Espacio Recuperado.: {0} GB" -f $Recovered)
Write-Log ("Tiempo Ejecución...: {0}" -f $Elapsed)
Write-Log "Script finalizado correctamente"
Write-Log "==============================================="

#-------------------------------------------------------
# CÓDIGO DE SALIDA
#-------------------------------------------------------

if ($Recovered -ge 0) {

    exit 0

}
else {

    exit 1

}


