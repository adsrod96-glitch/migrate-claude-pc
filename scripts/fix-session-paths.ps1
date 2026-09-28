<#
  Fixes references to the old path (from another computer) inside a migrated
  project's session (.jsonl) files: not just the "cwd" field, but any
  mention of the old path in the conversation text (e.g. a link to a PDF
  generated during that session, paths used in tool calls, etc.). Detects
  the old path(s) on its own, from existing "cwd" fields, and swaps only the
  project's root PREFIX (preserves everything after it, e.g. subfolders).
  Always makes a backup of the folder before changing anything.

  Don't run this from inside a Claude Code session (the app itself blocks
  this action as "session history tampering" - intentional). Run it in a
  normal PowerShell terminal, yourself.

  Usage:
    powershell -File fix-session-paths.ps1 -ProjectPath "C:\Path\To\The\Project"
    (without -ProjectPath, uses the current folder)
#>
param(
  [string]$ProjectPath = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'

$ProjectPath = (Resolve-Path $ProjectPath).Path
$slug = ($ProjectPath -replace '[:\\ ]', '-')
$dir = "$env:USERPROFILE\.claude\projects\$slug"

if (-not (Test-Path $dir)) {
    Write-Host "No sessions folder found for this project: $dir" -ForegroundColor Yellow
    Write-Host "(normal if this project never had Claude Code conversations attached, only memory)" -ForegroundColor Yellow
    exit 0
}

$enc = New-Object System.Text.UTF8Encoding $false
$files = Get-ChildItem "$dir\*.jsonl"
if ($files.Count -eq 0) {
    Write-Host "No .jsonl files in $dir (memory only, no raw conversations). Nothing to fix." -ForegroundColor Yellow
    exit 0
}

$backup = "$dir.pre-fix-backup"
if (-not (Test-Path $backup)) {
    Copy-Item $dir $backup -Recurse
    Write-Host "Backup created at: $backup" -ForegroundColor Yellow
} else {
    Write-Host "Backup already existed, didn't recreate it: $backup" -ForegroundColor DarkYellow
}

# Always detect old paths from the BACKUP (the original, never-touched
# state) - not from the live files. If a fix already ran before (even just
# on the "cwd" field), the live files no longer have the old path recorded
# anywhere, and a stray old mention left in the text (e.g. a PDF link)
# would become undetectable. The backup always keeps the pre-fix version.
$backupFiles = Get-ChildItem "$backup\*.jsonl" -ErrorAction SilentlyContinue
if (-not $backupFiles -or $backupFiles.Count -eq 0) { $backupFiles = $files }

$allCwd = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $backupFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    foreach ($m in [regex]::Matches($text, '"cwd":"((?:[^"\\]|\\.)*)"')) {
        [void]$allCwd.Add($m.Groups[1].Value)
    }
}

$newCwdEscaped = $ProjectPath -replace '\\', '\\\\'

# For each old cwd, extract just the project's ROOT (up to and including
# the project folder name), to also catch subfolder cwds (e.g. "...\web")
# and, by swapping only that prefix across the whole file, fix any other
# mention of the old path in the text too (e.g. a PDF link generated in
# that session), not just the "cwd" field.
$projectName = Split-Path $ProjectPath -Leaf
$escapedName = [regex]::Escape($projectName)
$oldRoots = New-Object System.Collections.Generic.HashSet[string]
foreach ($cwd in $allCwd) {
    if ($cwd -eq $newCwdEscaped) { continue }
    $m = [regex]::Match($cwd, "^.*?(?:\\\\|/)$escapedName")
    if ($m.Success) {
        [void]$oldRoots.Add($m.Value)
    }
}

if ($oldRoots.Count -eq 0) {
    Write-Host "Didn't find any old path different from the current one. Maybe it's already fixed." -ForegroundColor Yellow
    exit 0
}

Write-Host "Old root(s) detected:" -ForegroundColor Cyan
$oldRoots | ForEach-Object { Write-Host "  $_" }
Write-Host "New root: $newCwdEscaped`n" -ForegroundColor Cyan

# New root in posix style (git-bash), in case there are old cwds in that
# style (e.g. "/c/Users/name/Documents/Claude/project").
$driveLetter = $ProjectPath.Substring(0,1).ToLower()
$restOfPath = ($ProjectPath.Substring(2) -replace '\\', '/')
$newRootPosix = "/$driveLetter$restOfPath"

$totalFiles = 0
$totalOccurrences = 0

foreach ($f in $files) {
    $content = [System.IO.File]::ReadAllText($f.FullName, $enc)
    $changed = $false
    $nFile = 0
    foreach ($root in $oldRoots) {
        # Preserve the original separator style (\\ or /) in the new root,
        # replacing only the prefix, not the whole string - so any
        # subfolder or file name after it stays intact.
        if ($root.StartsWith('/')) {
            $newRoot = $newRootPosix
        } else {
            $newRoot = $newCwdEscaped
        }
        $n = ([regex]::Matches($content, [regex]::Escape($root))).Count
        if ($n -gt 0) {
            $content = $content.Replace($root, $newRoot)
            $nFile += $n
            $changed = $true
        }
    }
    if ($changed) {
        [System.IO.File]::WriteAllText($f.FullName, $content, $enc)
        Write-Host "$($f.Name): fixed $nFile occurrences" -ForegroundColor Green
        $totalFiles++
        $totalOccurrences += $nFile
    }
}

Write-Host "`nDone: $totalOccurrences occurrences fixed across $totalFiles files." -ForegroundColor Cyan
Write-Host "This includes file references in the conversation text (e.g. generated PDF links), not just the cwd field." -ForegroundColor Cyan
Write-Host "If anything goes wrong, the backup is at: $backup" -ForegroundColor Cyan
Write-Host "`nTo confirm: open a terminal, 'cd' into the project, and run 'claude --resume'." -ForegroundColor Cyan
