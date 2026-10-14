[CmdletBinding()]
param(
    [string]$ProjectDir = '',
    [string]$ToolkitDir = '',
    [ValidateSet('all', 'html5', 'windows')][string]$Channel = 'all',
    [string]$ButlerPath = '',
    [string]$UserVersion = '',
    [switch]$Preview,
    [switch]$Status,
    [switch]$DryRun,
    [switch]$Help
)
# A game's publish-itch.ps1: copy beside project.godot.
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty in param defaults.
if (-not $ProjectDir) { $ProjectDir = $PSScriptRoot }
if (-not $ToolkitDir) { $ToolkitDir = Join-Path $PSScriptRoot '..\godot_toolkit' }
. (Join-Path $ToolkitDir 'publishing/Publisher.ps1')
if ($Help) {
    Write-Host 'publish-itch.ps1 [-Channel all|html5|windows] [-Preview | -Status | -DryRun] [-ButlerPath path] [-UserVersion version] [-ProjectDir path] [-ToolkitDir path]'
    Write-Host 'Run publish.ps1 -BuildOnly first. Default pushes every channel this game builds. Preview compares with itch; DryRun is offline and writes nothing.'
    return
}
if (@(@($Preview, $Status, $DryRun) | Where-Object { $_ }).Count -gt 1) { throw 'Choose only one of -Preview, -Status or -DryRun.' }
$info = Get-PublishProject $ProjectDir
Invoke-PublishItch $info $Channel $ButlerPath $UserVersion -Preview:$Preview -Status:$Status -DryRun:$DryRun
