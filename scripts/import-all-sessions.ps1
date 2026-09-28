<#
  Runs fix-session-paths.ps1 + register-sessions-sidebar.ps1 for several
  projects at once, so you don't have to write the foreach loop by hand or
  deal with confusing error messages when a project has no history.

  By default, discovers on its own every project under Documents\Claude
  that has an associated sessions folder (~/.claude/projects/<slug>) - you
  don't need to say which ones. You can also name just a few, with
  -Projects.

  Don't run this from inside a Claude Code session (the two actions it
  calls are blocked by the app as a safety guardrail - intentional). Run it
  in a normal PowerShell terminal, yourself.

  Usage:
    powershell -File import-all-sessions.ps1
    powershell -File import-all-sessions.ps1 -Projects "Restaurant Menu","Auto Shop SaaS"
    powershell -File import-all-sessions.ps1 -BaseDir "C:\Different\Path"
#>
param(
  [string[]]$Projects,
  [string]$BaseDir = "$env:USERPROFILE\Documents\Claude"
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

if (-not $Projects) {
    Write-Host "No -Projects given, discovering on my own in $BaseDir..." -ForegroundColor Yellow
    $Projects = Get-ChildItem $BaseDir -Directory | Where-Object {
        $slug = ($_.FullName -replace '[:\\ ]', '-')
        Test-Path "$env:USERPROFILE\.claude\projects\$slug"
    } | Select-Object -ExpandProperty Name
}

if (-not $Projects -or $Projects.Count -eq 0) {
    Write-Host "Didn't find any project with an associated sessions folder." -ForegroundColor Yellow
    exit 0
}

Write-Host "Projects to process: $($Projects -join ', ')`n" -ForegroundColor Cyan

$summary = @()

foreach ($p in $Projects) {
    $path = Join-Path $BaseDir $p
    if (-not (Test-Path $path)) {
        Write-Host "== $p == folder not found at $path, skipping" -ForegroundColor Red
        $summary += [pscustomobject]@{ Project = $p; Result = "folder not found" }
        continue
    }

    Write-Host "== $p ==" -ForegroundColor Cyan
    & "$here\fix-session-paths.ps1" -ProjectPath $path
    & "$here\register-sessions-sidebar.ps1" -ProjectPath $path
    Write-Host ""

    $slug = ($path -replace '[:\\ ]', '-')
    $sessionsDir = "$env:USERPROFILE\.claude\projects\$slug"
    $n = (Get-ChildItem "$sessionsDir\*.jsonl" -ErrorAction SilentlyContinue).Count
    $summary += [pscustomobject]@{ Project = $p; Result = if ($n -gt 0) { "$n session(s) processed" } else { "no raw conversations (memory only)" } }
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
$summary | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "Now FULLY QUIT Claude Desktop (including the system tray) and reopen it." -ForegroundColor Cyan
Write-Host "You only need to do this once, even with several projects." -ForegroundColor Cyan
