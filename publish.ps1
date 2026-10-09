[CmdletBinding()]
param(
    [string]$ProjectDir = $PSScriptRoot,
    [string]$GodotExe = '',
    [string]$EnvFile = 'D:\WebHatchery\.env',
    [string]$DeployRoot = '',
    [switch]$Preview,
    [Alias('p')][switch]$Production,
    [switch]$FTP,
    [switch]$BuildOnly,
    [switch]$SkipBuild,
    [switch]$DryRun,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/tools/publishing/Publisher.ps1"
if ($Help) {
    Write-Host 'publish.ps1 [-Preview | -Production (-p) | -FTP] [-BuildOnly] [-SkipBuild] [-DryRun] [-GodotExe path] [-EnvFile path] [-DeployRoot path] [-ProjectDir path]'
    Write-Host 'Default: export Windows and copy the ZIP and a download page to PREVIEW_ROOT/games/<slug>. -FTP also deploys local production. -DryRun makes no changes.'
    return
}
if ($Preview -and ($Production -or $FTP)) { throw '-Preview cannot be combined with -Production or -FTP.' }
if ($BuildOnly -and ($Preview -or $Production -or $FTP -or $DeployRoot)) { throw '-BuildOnly cannot select a deployment target.' }
if ($BuildOnly -and $SkipBuild) { throw '-BuildOnly and -SkipBuild are mutually exclusive.' }
$info = Get-PublishProject $ProjectDir
$settings = Read-PublishEnvironment $EnvFile
if ($FTP) { $Production = $true }
if (-not $BuildOnly) {
    if (-not $DeployRoot) {
        $key = if ($Production) { 'PRODUCTION_ROOT' } else { 'PREVIEW_ROOT' }
        $DeployRoot = Get-PublishSetting $settings $key
        if (-not $DeployRoot) { throw "Set $key in $EnvFile or pass -DeployRoot." }
    }
    $destination = Get-DeployDirectory $DeployRoot $info
    Write-Host "WebHatchery $(if ($Production) { 'production' } else { 'preview' }): $destination"
    if ($FTP) {
        $ftpConfig = Get-PublishFtpConfig $settings $info.Slug
        Write-Host "FTP destination: $($ftpConfig.RemoteDirectory)"
    }
}
if ($DryRun) {
    Write-Host "[dry-run] $(if ($SkipBuild) { 'Validate existing build' } else { 'Export Windows Desktop' }) for $($info.Slug)"
    if (-not $BuildOnly) { Write-Host '[dry-run] Copy the verified Windows ZIP and a generated download page to the destination.' }
    if ($FTP) { Write-Host '[dry-run] Upload only this game directory; publish index.html last.' }
    if (-not $BuildOnly) { Write-Host "[dry-run] Record $($info.Slug) deployment in Project Roost for $(if ($Production) { 'production' } else { 'preview' })." }
    return
}
if ($SkipBuild) { $build = Read-PublishBuild $info } else { $build = New-PublishBuild $info $GodotExe }
if ($BuildOnly) { Write-Host "Build ready: $($build.Directory)"; return }
Copy-PublishWebsite $build $info $destination
if ($FTP) { Send-PublishWebsite $build $info $ftpConfig }
$environmentName = if ($Production) { 'production' } else { 'preview' }
$remotePath = if ($Production) { "/public_html/games/$($info.Slug)" } else { "games/$($info.Slug)" }
$targetType = if ($FTP) { 'ftp' } else { 'filesystem' }
$publishMode = if ($SkipBuild) { 'reuse-build' } else { 'build' }
if ($FTP) { $publishMode += '+ftp' }
Register-PublishProjectRoostDeployment $settings $info $environmentName $targetType $destination $remotePath $publishMode | Out-Null
Write-Host "Published: $destination"
