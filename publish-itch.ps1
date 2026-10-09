[CmdletBinding()]
param(
    [string]$ProjectDir = $PSScriptRoot,
    [ValidateSet('windows')][string]$Channel = 'windows',
    [string]$ButlerPath = '',
    [string]$UserVersion = '',
    [switch]$Preview,
    [switch]$Status,
    [switch]$DryRun,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/tools/publishing/Publisher.ps1"
if ($Help) {
    Write-Host 'publish-itch.ps1 [-Preview | -Status | -DryRun] [-ButlerPath path] [-UserVersion version] [-ProjectDir path]'
    Write-Host 'Run publish.ps1 -BuildOnly first. Pushes the Windows channel. Preview compares with itch; DryRun is offline and writes nothing.'
    return
}
if (@(@($Preview, $Status, $DryRun) | Where-Object { $_ }).Count -gt 1) { throw 'Choose only one of -Preview, -Status or -DryRun.' }
$info = Get-PublishProject $ProjectDir
$channels = @($Channel)
if (-not $Status) { $build = Read-PublishBuild $info }
if (-not $DryRun) { $butler = Resolve-PublishButler $ButlerPath }
foreach ($name in $channels) {
    $target = "$($info.Config.itch_target):$($info.Config.itch_channels.$name)"
    if ($Status) { Invoke-PublishTool $butler @('status', $target); continue }
    $source = Join-Path $build.Directory 'windows'
    if ($DryRun) { Write-Host "[dry-run] $source -> $target"; continue }
    if ($Preview) { Invoke-PublishTool $butler @('push-preview', '--changes-only', $source, $target); continue }
    $arguments = @('push', '--assume-yes', '--if-changed')
    if ($UserVersion) { $arguments += @('--userversion', $UserVersion) }
    $arguments += @($source, $target)
    Invoke-PublishTool $butler $arguments
}
