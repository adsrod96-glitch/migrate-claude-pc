<#
  Registers a migrated project's sessions in Claude Desktop's session index,
  so they show up in the app's sidebar (not just in the terminal via
  claude --resume). Doesn't touch any history (.jsonl) file. Creates new
  registration files in the app's own config folder.

  Finds that folder on its own (regular Claude install, or Microsoft Store
  version with AppData virtualized under
  AppData\Local\Packages\Claude_*\LocalCache\Roaming\Claude\...) and copies
  the exact format of an already-existing real registration, instead of
  assuming fixed paths or schemas - those change between installs/versions.

  Run fix-session-paths.ps1 FIRST (should already have run before this one).

  Don't run this from inside a Claude Code session (the app itself blocks
  this action as "self-modification" - intentional). Run it in a normal
  PowerShell terminal, yourself.

  Usage:
    powershell -File register-sessions-sidebar.ps1 -ProjectPath "C:\Path\To\The\Project"
    (without -ProjectPath, uses the current folder)

  IMPORTANT: after running this you have to FULLY QUIT Claude Desktop
  (including the system tray icon) and reopen it, for the sidebar to
  refresh.
#>
param(
  [string]$ProjectPath = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'

$ProjectPath = (Resolve-Path $ProjectPath).Path

Write-Host "Looking for Claude Desktop's sessions folder..." -ForegroundColor Yellow
$sessionsRoot = Get-ChildItem "$env:APPDATA" -Recurse -Directory -Filter "claude-code-sessions" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sessionsRoot) {
    $sessionsRoot = Get-ChildItem "$env:LOCALAPPDATA" -Recurse -Directory -Filter "claude-code-sessions" -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $sessionsRoot) {
    throw "Couldn't find any 'claude-code-sessions' folder under AppData. Make sure Claude Desktop has been opened at least once on this PC."
}
Write-Host "Found: $($sessionsRoot.FullName)" -ForegroundColor Green

$sample = Get-ChildItem $sessionsRoot.FullName -Recurse -File -Filter "local_*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sample) {
    throw "Found the folder but there's no existing local_*.json file to copy the format from. Open Claude Desktop, create any session (in any project), and try again."
}
$regDir = $sample.DirectoryName
Write-Host "Real registration folder (account/organization): $regDir" -ForegroundColor Green
Write-Host "Template file: $($sample.Name)" -ForegroundColor Green

$template = Get-Content $sample.FullName -Raw | ConvertFrom-Json

$slug = ($ProjectPath -replace '[:\\ ]', '-')
$projDir = "$env:USERPROFILE\.claude\projects\$slug"
if (-not (Test-Path $projDir)) { throw "Project sessions folder not found: $projDir" }

Write-Host "Checking already-registered sessions (to avoid duplicates)..." -ForegroundColor Yellow
$alreadyRegistered = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem "$regDir\local_*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -Encoding UTF8
    $m = [regex]::Match($content, '"cliSessionId":"([^"]*)"')
    if ($m.Success) { [void]$alreadyRegistered.Add($m.Groups[1].Value) }
}
Write-Host "$($alreadyRegistered.Count) sessions already registered on this account (across all projects)." -ForegroundColor Yellow

$created = 0
$skipped = 0

Get-ChildItem "$projDir\*.jsonl" | ForEach-Object {
    $file = $_.FullName
    $sid = $_.BaseName

    if ($alreadyRegistered.Contains($sid)) {
        Write-Host "$sid : already registered, skipping (no duplicate)" -ForegroundColor DarkGray
        $script:skipped++
        return
    }

    $text = Get-Content $file -Raw -Encoding UTF8

    $titleMatch = [regex]::Match($text, '"type":"custom-title","customTitle":"([^"]*)"')
    if ($titleMatch.Success -and $titleMatch.Groups[1].Value.Trim() -ne "") {
        $title = $titleMatch.Groups[1].Value
    } else {
        $title = "Migrated session ($($sid.Substring(0,8)))"
    }

    $modelMatch = [regex]::Match($text, '"model":"(claude-[^"]+)"')
    $model = if ($modelMatch.Success) { $modelMatch.Groups[1].Value } else { $template.model }

    $tsMatches = [regex]::Matches($text, '"timestamp":"([0-9T:\.\-Z]+)"')
    if ($tsMatches.Count -gt 0) {
        $timestamps = $tsMatches | ForEach-Object { [DateTimeOffset]::Parse($_.Groups[1].Value) } | Sort-Object
        $created_ = $timestamps[0]
        $lastAct = $timestamps[-1]
    } else {
        $created_ = Get-Date
        $lastAct = Get-Date
    }

    $turnCount = ([regex]::Matches($text, '"type":"assistant"')).Count

    $newLocalId = "local_$([guid]::NewGuid().ToString())"

    # Clone the template object (to keep exactly the fields your app
    # version expects) and only override the fields specific to this session.
    $new = $template | Select-Object *
    $new.sessionId = $newLocalId
    $new.cliSessionId = $sid
    $new.cwd = $ProjectPath
    $new.originCwd = $ProjectPath
    $new.lastFocusedAt = $lastAct.ToUnixTimeMilliseconds()
    $new.createdAt = $created_.ToUnixTimeMilliseconds()
    $new.lastActivityAt = $lastAct.ToUnixTimeMilliseconds()
    $new.model = $model
    $new.isArchived = $false
    $new.title = $title
    $new.titleSource = "auto"
    if ($new.PSObject.Properties.Name -contains "permissionMode") { $new.permissionMode = "default" }
    if ($new.PSObject.Properties.Name -contains "completedTurns") { $new.completedTurns = $turnCount }

    $json = $new | ConvertTo-Json -Depth 10 -Compress
    $outPath = Join-Path $regDir "$newLocalId.json"
    $enc = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($outPath, $json, $enc)

    Write-Host "$sid -> $newLocalId : $title" -ForegroundColor Green
    $script:created++
}

Write-Host "`n$created new registration file(s) created in: $regDir" -ForegroundColor Cyan
if ($skipped -gt 0) { Write-Host "$skipped were already registered, skipped (no duplicate)." -ForegroundColor Cyan }
if ($created -gt 0) {
    Write-Host "Now FULLY QUIT Claude Desktop (including the system tray) and reopen it." -ForegroundColor Cyan
    Write-Host "The project's sessions should show up in the sidebar (probably under 'Ungrouped')." -ForegroundColor Cyan
} else {
    Write-Host "Nothing new to register, no need to reopen the app." -ForegroundColor Cyan
}
