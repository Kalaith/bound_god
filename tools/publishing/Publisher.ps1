# Shared functions for the two project entry points. No work runs when loaded.
Set-StrictMode -Version Latest

function Write-PublishJson($Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
}

function Get-PublishProject([string]$ProjectDir) {
    $root = (Resolve-Path -LiteralPath $ProjectDir).Path
    foreach ($file in @('project.godot', 'publish.json', 'export_presets.cfg')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file) -PathType Leaf)) { throw "Missing project file: $file" }
    }
    $config = Get-Content -LiteralPath (Join-Path $root 'publish.json') -Raw | ConvertFrom-Json
    if ($config.slug -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Invalid project slug.' }
    if ($config.godot_version -ne '4.2.2') { throw 'This publisher is validated for Godot 4.2.2.' }
    if ($config.itch_target -notmatch '^[a-z0-9_-]+/[a-z0-9_-]+$') { throw 'Invalid itch target; use owner/game.' }
    if ($config.itch_channels.windows -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Invalid itch channel.' }
    if ($config.executable -notmatch '^[A-Za-z0-9_-]+\.exe$') { throw 'Invalid executable name; use Name.exe.' }
    return [pscustomobject]@{ Root = $root; Slug = $config.slug; Config = $config; Exe = $config.executable }
}

function Read-PublishEnvironment([string]$Path) {
    $settings = @{}
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
                $settings[$matches[1]] = $matches[2].Trim('"').Trim("'")
            }
        }
    }
    return $settings
}

function Get-PublishSetting($Settings, [string]$Name, [string]$Default = '') {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ($value) { return $value }
    if ($Settings.ContainsKey($Name) -and $Settings[$Name]) { return $Settings[$Name] }
    return $Default
}

function New-PublishProjectRoostPayload($Info, [string]$EnvironmentName, [string]$TargetType, [string]$Destination, [string]$RemotePath, [string]$PublishMode) {
    $titleProperty = $Info.Config.PSObject.Properties['display_name']
    $descriptionProperty = $Info.Config.PSObject.Properties['description']
    $displayName = if ($titleProperty) { [string]$titleProperty.Value } else { '' }
    $description = if ($descriptionProperty) { [string]$descriptionProperty.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase(($Info.Slug -replace '[-_]', ' ').ToLowerInvariant())
    }
    if ([string]::IsNullOrWhiteSpace($description)) { $description = "$displayName." }

    return [ordered]@{
        project = $Info.Slug
        game_title = $displayName
        game_description = $description
        environment = $EnvironmentName
        target_type = $TargetType
        status = 'success'
        frontend_deployed = $true
        backend_deployed = $false
        destination_path = $Destination
        remote_path = $RemotePath
        source_path = $Info.Root
        publish_mode = $PublishMode
        actor = if ($env:USERNAME) { $env:USERNAME } else { $env:USER }
        deployed_at = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    }
}

function Register-PublishProjectRoostDeployment($Settings, $Info, [string]$EnvironmentName, [string]$TargetType, [string]$Destination, [string]$RemotePath, [string]$PublishMode) {
    $token = Get-PublishSetting $Settings 'PROJECT_ROOST_PUBLISH_TOKEN'
    $urlKey = if ($EnvironmentName -eq 'production') { 'PROJECT_ROOST_API_URL_PRODUCTION' } else { 'PROJECT_ROOST_API_URL_PREVIEW' }
    $apiUrl = (Get-PublishSetting $Settings $urlKey).TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($apiUrl)) {
        Write-Warning "Project Roost tracking skipped: configure PROJECT_ROOST_PUBLISH_TOKEN and $urlKey."
        return $false
    }

    $payload = New-PublishProjectRoostPayload $Info $EnvironmentName $TargetType $Destination $RemotePath $PublishMode
    $headers = @{ 'X-Project-Roost-Publish-Token' = $token }
    try {
        $result = Invoke-RestMethod -Uri "$apiUrl/deployments/publish" -Method Post -Body ($payload | ConvertTo-Json -Depth 5) -ContentType 'application/json' -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if (-not $result.success) { throw 'Project Roost returned an unsuccessful publish response.' }
        Write-Host "Project Roost recorded $($Info.Slug) $EnvironmentName deployment."
        return $true
    } catch {
        Write-Warning "Project Roost tracking failed for ${EnvironmentName}: $($_.Exception.Message)"
        return $false
    }
}

function Get-DeployDirectory([string]$Root, $Info) {
    if (-not [IO.Path]::IsPathRooted($Root)) { throw 'DeployRoot must be an absolute path.' }
    $path = [IO.Path]::GetFullPath((Join-Path $Root "games/$($Info.Slug)"))
    $project = $Info.Root.TrimEnd('\', '/')
    if ($path.Equals($project, [StringComparison]::OrdinalIgnoreCase) -or
        $project.StartsWith($path + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment cannot contain the source project.'
    }
    return $path
}

function Invoke-PublishTool([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Tool failed with exit code ${LASTEXITCODE}: $Executable" }
}

function Resolve-PublishGodot($Info, [string]$Requested) {
    if (-not $Requested) { $Requested = $env:GODOT_EXE }
    if (-not $Requested) { $Requested = Join-Path $Info.Root 'exports/tooling/Godot_v4.2.2-stable_win64_console.exe' }
    if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) { throw 'Standard Godot 4.2.2 not found. Pass -GodotExe or set GODOT_EXE.' }
    $version = (& $Requested --headless --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.2\.2\.stable\.' -or $version -match 'mono') {
        # The installed export templates are the standard (non-mono) 4.2.2 ones.
        throw "Use the standard (non-mono) Godot 4.2.2 editor for exports. Found: $version"
    }
    return (Resolve-Path -LiteralPath $Requested).Path
}

function Invoke-PublishGodot([string]$Executable, [string[]]$Arguments, [string]$Log) {
    # Godot can log errors and still exit zero; inspect both signals.
    & $Executable @Arguments *> $Log
    $exitCode = $LASTEXITCODE
    $errors = Select-String -LiteralPath $Log -Pattern '(?m)^\s*(ERROR:|SCRIPT ERROR:|Error:)'
    if ($exitCode -ne 0 -or $errors) { throw "Godot failed (exit $exitCode). Inspect $Log" }
}

function New-PublishBuild($Info, [string]$RequestedGodot) {
    $godot = Resolve-PublishGodot $Info $RequestedGodot
    $buildRoot = Join-Path $Info.Root 'builds/publish'
    $id = [guid]::NewGuid().ToString('N')
    $directory = Join-Path $buildRoot $id
    New-Item -ItemType Directory -Path "$directory/windows" -Force | Out-Null
    # Export mode performs the editor import before exporting. A separate
    # --import invocation hits this machine's known automatic-shutdown exit 1.
    [IO.File]::WriteAllText((Join-Path $Info.Root 'builds/.gdignore'), '')
    if (Test-Path -LiteralPath (Join-Path $Info.Root 'exports')) {
        [IO.File]::WriteAllText((Join-Path $Info.Root 'exports/.gdignore'), '')
    }
    Invoke-PublishGodot $godot @('--headless', '--path', $Info.Root, '--export-release', 'Windows Desktop', "$directory/windows/$($Info.Exe)") "$directory/windows-export.log"
    if (-not (Test-Path -LiteralPath "$directory/windows/$($Info.Exe)" -PathType Leaf)) { throw 'Windows export missing.' }
    Compress-Archive -Path "$directory/windows/*" -DestinationPath "$directory/$($Info.Slug)_windows.zip"
    $records = @()
    foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File | Where-Object { $_.Extension -ne '.log' }) {
        $records += [ordered]@{
            path = $file.FullName.Substring($directory.Length + 1).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    Write-PublishJson "$directory/manifest.json" ([ordered]@{ schema = 1; slug = $Info.Slug; created_utc = [DateTime]::UtcNow.ToString('o'); files = $records })
    # The pointer changes only after both exports and packaging have succeeded.
    Write-PublishJson "$buildRoot/latest.tmp" @{ id = $id }
    Move-Item -LiteralPath "$buildRoot/latest.tmp" -Destination "$buildRoot/latest.json" -Force
    return Read-PublishBuild $Info
}

function Read-PublishBuild($Info) {
    $buildRoot = Join-Path $Info.Root 'builds/publish'
    $pointer = Join-Path $buildRoot 'latest.json'
    if (-not (Test-Path -LiteralPath $pointer)) { throw 'No completed build. Run .\publish.ps1 -BuildOnly first.' }
    $id = (Get-Content -LiteralPath $pointer -Raw | ConvertFrom-Json).id
    if ($id -notmatch '^[a-f0-9]{32}$') { throw 'Invalid build pointer.' }
    $directory = Join-Path $buildRoot $id
    $manifest = Get-Content -LiteralPath "$directory/manifest.json" -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.slug -ne $Info.Slug) { throw 'Invalid build manifest.' }
    $paths = @{}
    foreach ($record in $manifest.files) {
        if ($record.path -notmatch '^(windows/[a-zA-Z0-9._-]+|[a-z0-9_-]+_windows\.zip)$' -or $paths.ContainsKey($record.path)) {
            throw 'Invalid or duplicate build file path.'
        }
        $paths[$record.path] = $true
        $file = Join-Path $directory $record.path
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $record.sha256) {
            throw "Build file missing or changed: $($record.path). Rebuild before publishing."
        }
    }
    foreach ($required in @("windows/$($Info.Exe)", "$($Info.Slug)_windows.zip")) {
        if (-not $paths.ContainsKey($required)) { throw "Build manifest missing $required" }
    }
    foreach ($folder in @('windows')) {
        foreach ($file in Get-ChildItem -LiteralPath "$directory/$folder" -Recurse -File -Force) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or -not $paths.ContainsKey($file.FullName.Substring($directory.Length + 1).Replace('\', '/'))) {
                throw 'Untracked or linked file in build. Rebuild before publishing.'
            }
        }
    }
    return [pscustomobject]@{ Directory = $directory; Manifest = $manifest }
}

# Windows-only game: its web page is a download page generated from download.html.
function New-PublishDownloadPage($Info, [string]$Path) {
    $page = Get-Content -LiteralPath "$PSScriptRoot/download.html" -Raw
    $page = $page.Replace('{{TITLE}}', [Net.WebUtility]::HtmlEncode([string]$Info.Config.display_name))
    $page = $page.Replace('{{DESCRIPTION}}', [Net.WebUtility]::HtmlEncode([string]$Info.Config.description))
    $page = $page.Replace('{{ZIP}}', "$($Info.Slug)_windows.zip")
    $page = $page.Replace('{{BUILT}}', [DateTime]::UtcNow.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))
    [IO.File]::WriteAllText($Path, $page, [Text.UTF8Encoding]::new($false))
}

function Copy-PublishWebsite($Build, $Info, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    # Never recursively mirror/delete a deployment directory or its neighbours.
    Copy-Item -LiteralPath "$($Build.Directory)/$($Info.Slug)_windows.zip" -Destination $Destination -Force
    New-PublishDownloadPage $Info (Join-Path $Destination 'index.html')
}

function Get-PublishFtpConfig($Settings, [string]$Slug) {
    $config = @{}
    foreach ($key in @('FTP_SERVER', 'FTP_USERNAME', 'FTP_PASSWORD')) {
        $config[$key] = Get-PublishSetting $Settings $key
        if (-not $config[$key]) { throw "Missing $key. Set it in the environment or the external .env file." }
    }
    if ($config.FTP_SERVER -notmatch '^[a-zA-Z0-9.-]+$') { throw 'FTP_SERVER must be a hostname.' }
    $config.Port = [int](Get-PublishSetting $Settings 'FTP_PORT' '21')
    if ($config.Port -lt 1 -or $config.Port -gt 65535) { throw 'Invalid FTP_PORT.' }
    foreach ($key in @('FTP_USE_SSL', 'FTP_PASSIVE_MODE')) {
        $default = if ($key -eq 'FTP_USE_SSL') { 'false' } else { 'true' }
        $value = Get-PublishSetting $Settings $key $default
        if ($value -notmatch '^(true|false|1|0|yes|no|on|off)$') { throw "Invalid boolean $key" }
        $config[$key] = $value -match '^(true|1|yes|on)$'
    }
    $remoteRoot = (Get-PublishSetting $Settings 'FTP_REMOTE_ROOT' '/').Replace('\', '/').TrimEnd('/')
    if ($remoteRoot -and (-not $remoteRoot.StartsWith('/') -or $remoteRoot -match '(^|/)\.\.?(/|$)')) { throw 'FTP_REMOTE_ROOT must be an absolute path without traversal.' }
    $config.RemoteDirectory = "$remoteRoot/games/$Slug"
    return $config
}

function New-PublishFtpRequest($Config, [string]$Path, [string]$Method) {
    $escaped = (($Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
    $request = [Net.FtpWebRequest]::Create("ftp://$($Config.FTP_SERVER):$($Config.Port)$escaped")
    $request.Credentials = [Net.NetworkCredential]::new($Config.FTP_USERNAME, $Config.FTP_PASSWORD)
    $request.Method = $Method
    $request.EnableSsl = $Config.FTP_USE_SSL
    $request.UsePassive = $Config.FTP_PASSIVE_MODE
    $request.UseBinary = $true
    $request.KeepAlive = $false
    $request.Timeout = 60000
    $request.ReadWriteTimeout = 60000
    return $request
}

function Send-PublishWebsite($Build, $Info, $Config) {
    $current = ''
    foreach ($part in $Config.RemoteDirectory.Trim('/').Split('/')) {
        $current += "/$part"
        try { (New-PublishFtpRequest $Config $current 'MKD').GetResponse().Close() }
        catch {
            # Confirm an existing directory instead of treating every 550 as success.
            (New-PublishFtpRequest $Config $current 'NLST').GetResponse().Close()
        }
    }
    # The download page is generated beside the build and uploaded last.
    $page = Join-Path $Build.Directory 'index.html'
    New-PublishDownloadPage $Info $page
    $files = @(Get-Item -LiteralPath "$($Build.Directory)/$($Info.Slug)_windows.zip", $page)
    foreach ($file in $files) {
        $remoteName = $file.Name
        Write-Host "Uploading $remoteName ($($file.Length) bytes)"
        $request = New-PublishFtpRequest $Config "$($Config.RemoteDirectory)/$remoteName" 'STOR'
        $request.ContentLength = $file.Length
        $inputStream = [IO.File]::OpenRead($file.FullName)
        try {
            $outputStream = $request.GetRequestStream()
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
        $request.GetResponse().Close()
    }
}

function Resolve-PublishButler([string]$Requested) {
    if (-not $Requested) { $Requested = $env:BUTLER_EXE }
    if (-not $Requested) {
        $command = Get-Command butler -ErrorAction SilentlyContinue
        if ($command) { $Requested = $command.Source }
    }
    if (-not $Requested) { $Requested = 'D:\WebHatchery\RustGames\rust_management\itch-butler\butler.exe' }
    if (-not (Test-Path -LiteralPath $Requested -PathType Leaf)) { throw 'Butler not found. Pass -ButlerPath or set BUTLER_EXE.' }
    return (Resolve-Path -LiteralPath $Requested).Path
}
