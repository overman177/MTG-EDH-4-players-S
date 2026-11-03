#requires -Version 5.1
<#
  One-click safe update for MTG EDH / Tabletop Simulator (Windows PowerShell).
  - Keep the locally modified savegame.json on disk.
  - Stash other Git changes, including new files, before a fast-forward pull.
  - Move old .tts-backups OUT of the Smart Import project tree.
  - Rebuild/deploy and check all GUID targets.
  - Do not automatically restore old Lotus files from stash.
#>
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoName = Split-Path $repoRoot -Leaf
$backupBase = Join-Path (Split-Path $repoRoot -Parent) ($repoName + "-backups")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$stashedChanges = $false
$exitCode = 1

Write-Host ""
Write-Host "=== MTG TABLE: UPDATE FROM GITHUB + DEPLOY ==="
Write-Host "Repository: $repoRoot"
Write-Host ""

Push-Location -LiteralPath $repoRoot
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git was not found. Install Git or use a VS Code terminal with Git available."
    }
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python was not found. Install Python or use a VS Code terminal with Python available."
    }
    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read Git branch." }
    if ($branch -ne "main") {
        throw "Current Git branch is '$branch', not 'main'. Switch to main before using this updater."
    }

    # Smart Import scans even Git-ignored .lua files. Moving this directory
    # outside the repository prevents duplicate TTS GUID discoveries.
    $legacyBackups = Join-Path $repoRoot ".tts-backups"
    if (Test-Path -LiteralPath $legacyBackups -PathType Container) {
        New-Item -ItemType Directory -Path $backupBase -Force | Out-Null
        $oldBackupDest = Join-Path $backupBase ("legacy-" + $timestamp)
        if (Test-Path -LiteralPath $oldBackupDest) {
            $oldBackupDest = Join-Path $backupBase ("legacy-" + $timestamp + "-" + [guid]::NewGuid().ToString("N").Substring(0,8))
        }
        Move-Item -LiteralPath $legacyBackups -Destination $oldBackupDest -ErrorAction Stop
        Write-Host "[OK] Old Smart Import-conflicting backups moved to:"
        Write-Host "     $oldBackupDest"
    }

    Write-Host "[1/4] Protecting local edits..."
    # savegame.json is a personal table-save file; do not put it in the stash.
    # Git stops safely if a remote change would overwrite that local file.
    $stashMessage = "MTG auto-backup before update " + $timestamp
    $stashOutput = & git stash push --include-untracked -m $stashMessage -- . ":(exclude)savegame.json"
    if ($LASTEXITCODE -ne 0) { throw "Could not back up local edits with git stash." }
    $stashText = $stashOutput -join [Environment]::NewLine
    if ($stashText -notmatch "No local changes to save") {
        $stashedChanges = $true
        Write-Host "[OK] Local edits safely saved in Git stash: $stashMessage"
        Write-Host "     They were NOT deleted. Do not automatically run 'git stash pop'."
    } else {
        Write-Host "[OK] No other local edits to stash."
    }

    Write-Host "[2/4] Downloading latest GitHub code (main)..."
    & git pull --ff-only origin main
    if ($LASTEXITCODE -ne 0) {
        throw "Git pull failed. No scripts were deployed. Your saved edits remain in the stash."
    }

    Write-Host "[3/4] Deploying the current source into live GUID files..."
    & python tools/deploy.py --apply
    if ($LASTEXITCODE -ne 0) { throw "Deployment failed. Review the error above." }

    Write-Host "[4/4] Verifying source and live scripts match..."
    & python tools/build.py --check
    if ($LASTEXITCODE -ne 0) { throw "Build check failed. Do not run Save & Play until resolved." }

    & git log -1 --format="Current GitHub version: %h %s"
    Write-Host ""
    Write-Host "[SUCCESS] Your table scripts are updated and match their source."
    Write-Host "NEXT: In Tabletop Simulator, use Smart Import / Save & Play."
    if ($stashedChanges) {
        Write-Host ""
        Write-Host "NOTE: Pre-update changes are in Git stash, not discarded."
        Write-Host "      Ask for help restoring specific edits; do NOT blindly pop old Lotus code."
    }
    if (Test-Path -LiteralPath (Join-Path $repoRoot "savegame.json")) {
        Write-Host "Local savegame.json was left untouched by the updater."
    }
    $exitCode = 0
}
catch {
    Write-Host ""
    Write-Host ("[FAILED] " + $_.Exception.Message)
    Write-Host "Do not use Smart Import until the error above is addressed."
    if ($stashedChanges) {
        Write-Host "Your pre-update edits are safe in Git stash."
    }
    $exitCode = 1
}
finally {
    Pop-Location
}
exit $exitCode
