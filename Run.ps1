param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string[]]$GameArgs = @()
)
# Plays the game from source with the installed standard Godot 4.7.2 editor.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    throw 'Godot executable not found. Pass -GodotExe with the path to your installed Godot 4.7.2 executable.'
}
& $GodotExe --path $PSScriptRoot @GameArgs
exit $LASTEXITCODE
