param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.2.2-stable_mono_win64_console.exe',
    [string[]]$GameArgs = @()
)
# Plays the game from source with the installed editor. Exports need the
# standard (non-mono) editor; publish.ps1 finds that one itself.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot executable not found. Pass -GodotExe with the path to your installed Godot 4 executable.'
}
& $GodotExe --path $PSScriptRoot @GameArgs
exit $LASTEXITCODE
