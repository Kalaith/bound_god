param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.2.2-stable_mono_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot executable not found. Pass -GodotExe with the path to your installed Godot 4 executable.'
}
& $GodotExe --path $PSScriptRoot
exit $LASTEXITCODE
