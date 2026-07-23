#Requires -Version 5.1

<#
.SYNOPSIS
    Limpieza segura y auditable para estaciones Windows.

.DESCRIPTION
    Windows Cleanup Pro elimina archivos temporales y caches seleccionadas,
    genera logs y entrega un reporte JSON. No elimina documentos, descargas,
    perfiles de usuario ni archivos de OneDrive.

.PARAMETER Mode
    Quick: temporales del usuario.
    Standard: Quick + temporales del sistema, caches de navegadores y crash dumps.
    Deep: Standard + Windows Update, Delivery Optimization y DISM.

.PARAMETER IncludeRecycleBin
    Incluye el vaciado de la papelera. Es una accion opcional.

.PARAMETER CloseBrowsers
    Cierra Chrome, Edge y Firefox antes de limpiar sus caches.

.PARAMETER LogDirectory
    Directorio donde se guardan el log y el reporte JSON.

.EXAMPLE
    .\LimpiezaWindows.ps1 -Mode Standard -WhatIf

.EXAMPLE
    .\LimpiezaWindows.ps1 -Mode Deep -IncludeRecycleBin -Confirm
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Quick', 'Standard', 'Deep')]
    [string]$Mode = 'Standard',

    [switch]$IncludeRecycleBin,

    [switch]$CloseBrowsers,

    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "$env:ProgramData\WindowsCleanupPro"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AppName = 'Windows Cleanup Pro'
$script:Version = '2.0.0'
$script:StartTime = Get-Date
$script:Stats = [ordered]@{
    ExaminedBytes = [int64]0
    RemovedItems  = 0
    SkippedItems  = 0
    Warnings      = 0
    Errors        = 0
}
$script:StoppedServices = [System.Collections.Generic.List[string]]::new()

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-ReadableSize {
    param([Parameter(Mandatory)][int64]$Bytes)

    if ($Bytes -ge 1TB) { return '{0:N2} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N2} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N2} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Initialize-Workspace {
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = Join-Path $LogDirectory "Cleanup_$timestamp.log"
    $script:ReportFile = Join-Path $LogDirectory "Cleanup_$timestamp.json"
}

function Write-CleanupLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $colors = @{
        INFO = 'Gray'; SUCCESS = 'Green'; WARNING = 'Yellow'; ERROR = 'Red'
    }
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line -ForegroundColor $colors[$Level]

    if ($Level -eq 'WARNING') { $script:Stats.Warnings++ }
    if ($Level -eq 'ERROR') { $script:Stats.Errors++ }
}

function Get-SystemDriveInfo {
    $driveName = $env:SystemDrive.TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName
    [PSCustomObject]@{
        Drive     = "$driveName`:"
        TotalBytes = [int64]($drive.Used + $drive.Free)
        UsedBytes  = [int64]$drive.Used
        FreeBytes  = [int64]$drive.Free
    }
}

function Get-FolderSize {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Force -File -Recurse -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

function Test-SafeCleanupPath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\') } catch { return $false }

    $blocked = @(
        [IO.Path]::GetPathRoot($fullPath).TrimEnd('\'),
        $env:SystemRoot.TrimEnd('\'),
        $env:ProgramFiles.TrimEnd('\'),
        ${env:ProgramFiles(x86)}.TrimEnd('\'),
        $env:USERPROFILE.TrimEnd('\')
    ) | Where-Object { $_ }

    return $blocked -notcontains $fullPath
}

function Clear-CleanupTarget {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label,
        [string]$Filter = '*'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-CleanupLog "${Label}: no encontrado ($Path)"
        return
    }
    if (-not (Test-SafeCleanupPath -Path $Path)) {
        $script:Stats.SkippedItems++
        Write-CleanupLog "${Label}: ruta protegida omitida ($Path)" 'WARNING'
        return
    }

    $size = Get-FolderSize -Path $Path
    $script:Stats.ExaminedBytes += $size

    if (-not $PSCmdlet.ShouldProcess($Path, "Limpiar $Label ($(ConvertTo-ReadableSize $size))")) {
        Write-CleanupLog "${Label}: simulacion/confirmacion omitida"
        return
    }

    $removed = 0
    Get-ChildItem -LiteralPath $Path -Filter $Filter -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $removed++
            }
            catch {
                $script:Stats.SkippedItems++
                Write-CleanupLog "En uso o sin acceso: $($_.FullName)" 'WARNING'
            }
        }

    $script:Stats.RemovedItems += $removed
    Write-CleanupLog "${Label}: $removed elementos eliminados" 'SUCCESS'
}

function Stop-CleanupService {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        if ($service.Status -eq 'Running' -and $PSCmdlet.ShouldProcess($Name, 'Detener servicio temporalmente')) {
            Stop-Service -Name $Name -Force
            $script:StoppedServices.Add($Name)
            Write-CleanupLog "Servicio detenido temporalmente: $Name"
        }
    }
    catch {
        Write-CleanupLog "No fue posible detener $Name`: $($_.Exception.Message)" 'WARNING'
    }
}

function Restore-CleanupServices {
    foreach ($name in $script:StoppedServices) {
        try {
            Start-Service -Name $name
            Write-CleanupLog "Servicio restaurado: $name" 'SUCCESS'
        }
        catch {
            Write-CleanupLog "No fue posible restaurar $name`: $($_.Exception.Message)" 'ERROR'
        }
    }
}

function Stop-BrowserProcesses {
    $processes = @('chrome', 'msedge', 'firefox')
    foreach ($name in $processes) {
        $running = Get-Process -Name $name -ErrorAction SilentlyContinue
        if (-not $running) { continue }

        if ($CloseBrowsers -and $PSCmdlet.ShouldProcess($name, 'Cerrar navegador para limpiar la cache')) {
            $running | Stop-Process -Force
            Write-CleanupLog "Navegador cerrado: $name"
        }
        else {
            Write-CleanupLog "$name esta abierto; algunos archivos se omitiran" 'WARNING'
        }
    }
}

function Invoke-BrowserCleanup {
    Stop-BrowserProcesses

    $chromiumTargets = @(
        @{ Name = 'Google Chrome'; Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ Name = 'Microsoft Edge'; Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
    )
    $cacheFolders = @('Cache', 'Code Cache', 'GPUCache', 'GrShaderCache', 'ShaderCache')

    foreach ($browser in $chromiumTargets) {
        if (-not (Test-Path -LiteralPath $browser.Root)) { continue }
        Get-ChildItem -LiteralPath $browser.Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
            ForEach-Object {
                foreach ($cache in $cacheFolders) {
                    Clear-CleanupTarget -Path (Join-Path $_.FullName $cache) -Label "$($browser.Name) $($_.Name) $cache"
                }
            }
    }

    $firefoxRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $firefoxRoot) {
        Get-ChildItem -LiteralPath $firefoxRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Clear-CleanupTarget -Path (Join-Path $_.FullName 'cache2') -Label "Firefox $($_.Name) cache"
                Clear-CleanupTarget -Path (Join-Path $_.FullName 'startupCache') -Label "Firefox $($_.Name) startup cache"
            }
    }
}

function Invoke-ComponentCleanup {
    if (-not (Test-IsAdministrator)) {
        Write-CleanupLog 'DISM requiere una consola con permisos de administrador' 'WARNING'
        return
    }
    if (-not $PSCmdlet.ShouldProcess('Windows Component Store', 'Ejecutar DISM StartComponentCleanup')) { return }

    Write-CleanupLog 'Ejecutando limpieza del almacen de componentes; puede tardar varios minutos'
    $process = Start-Process -FilePath 'DISM.exe' `
        -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/Quiet' `
        -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -eq 0) {
        Write-CleanupLog 'DISM finalizo correctamente' 'SUCCESS'
    }
    else {
        Write-CleanupLog "DISM finalizo con codigo $($process.ExitCode)" 'ERROR'
    }
}

function Export-CleanupReport {
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )

    $report = [ordered]@{
        application = $script:AppName
        version = $script:Version
        mode = $Mode
        computer = $env:COMPUTERNAME
        user = $env:USERNAME
        administrator = Test-IsAdministrator
        startedAt = $script:StartTime.ToString('o')
        finishedAt = (Get-Date).ToString('o')
        durationSeconds = [math]::Round(((Get-Date) - $script:StartTime).TotalSeconds, 2)
        disk = [ordered]@{
            drive = $Before.Drive
            freeBeforeBytes = $Before.FreeBytes
            freeAfterBytes = $After.FreeBytes
            recoveredBytes = [math]::Max(0, ($After.FreeBytes - $Before.FreeBytes))
        }
        statistics = $script:Stats
        logFile = $script:LogFile
    }

    $report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
    return $report
}

Initialize-Workspace
$before = Get-SystemDriveInfo

Write-Host ''
Write-Host " $script:AppName v$script:Version " -ForegroundColor Black -BackgroundColor Cyan
Write-Host " Modo: $Mode | Equipo: $env:COMPUTERNAME | Administrador: $(Test-IsAdministrator)"
Write-Host ''
Write-CleanupLog "Inicio de limpieza en modo $Mode"

try {
    Clear-CleanupTarget -Path $env:TEMP -Label 'Temporales del usuario'
    Clear-CleanupTarget -Path "$env:LOCALAPPDATA\D3DSCache" -Label 'Cache de shaders Direct3D'
    Clear-CleanupTarget -Path "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" -Label 'Cache de miniaturas' -Filter 'thumbcache*'

    if ($Mode -in @('Standard', 'Deep')) {
        if (Test-IsAdministrator) {
            Clear-CleanupTarget -Path "$env:SystemRoot\Temp" -Label 'Temporales de Windows'
            Clear-CleanupTarget -Path "$env:ProgramData\Microsoft\Windows\WER" -Label 'Windows Error Reporting'
        }
        else {
            Write-CleanupLog 'Temporales del sistema omitidos: se requieren permisos de administrador' 'WARNING'
        }

        Clear-CleanupTarget -Path "$env:LOCALAPPDATA\CrashDumps" -Label 'Volcados de aplicaciones'
        Invoke-BrowserCleanup
    }

    if ($Mode -eq 'Deep') {
        if (Test-IsAdministrator) {
            Stop-CleanupService -Name 'wuauserv'
            Stop-CleanupService -Name 'bits'
            Clear-CleanupTarget -Path "$env:SystemRoot\SoftwareDistribution\Download" -Label 'Descargas de Windows Update'
            Clear-CleanupTarget -Path "$env:SystemRoot\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache" -Label 'Delivery Optimization'
        }
        else {
            Write-CleanupLog 'Limpieza profunda del sistema omitida: se requieren permisos de administrador' 'WARNING'
        }
        Invoke-ComponentCleanup
    }

    if ($IncludeRecycleBin) {
        if ($PSCmdlet.ShouldProcess('Papelera de reciclaje', 'Vaciar')) {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-CleanupLog 'Papelera vaciada' 'SUCCESS'
        }
    }
}
catch {
    Write-CleanupLog "Error no controlado: $($_.Exception.Message)" 'ERROR'
}
finally {
    Restore-CleanupServices
}

$after = Get-SystemDriveInfo
$report = Export-CleanupReport -Before $before -After $after
$recovered = [int64]$report.disk.recoveredBytes

Write-Host ''
Write-Host ' RESUMEN ' -ForegroundColor Black -BackgroundColor Green
Write-Host " Espacio recuperado : $(ConvertTo-ReadableSize $recovered)"
Write-Host " Elementos eliminados: $($script:Stats.RemovedItems)"
Write-Host " Elementos omitidos  : $($script:Stats.SkippedItems)"
Write-Host " Advertencias        : $($script:Stats.Warnings)"
Write-Host " Errores             : $($script:Stats.Errors)"
Write-Host " Log                  : $script:LogFile"
Write-Host " Reporte JSON         : $script:ReportFile"
Write-Host ''

if ($script:Stats.Errors -gt 0) { exit 1 }
exit 0
