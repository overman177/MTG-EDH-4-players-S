#requires -Version 5.1
<#
  Shared 4-player / 6-player Tabletop Simulator updater.
  Stage 1: download the latest GitHub main and hard-reset local tracked files.
  Stage 2: launch the *freshly downloaded* updater in a new PowerShell process.
  This avoids continuing old in-memory code after the script updates itself.
  No backups, stashes, pushes, or local-edit protection.
#>
param([switch]$AfterSync)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$exitCode = 1

if (-not $AfterSync) {
    Write-Host ""
    Write-Host "=== MTG TABLE: REPLACE LOCAL FILES FROM GITHUB ==="
    Write-Host "Repository: $repoRoot"
    Write-Host "WARNING: Local tracked edits and untracked scripts in New/ and live/ will be deleted."
    Write-Host ""
}

Push-Location -LiteralPath $repoRoot
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is required."
    }
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        throw "Python is required."
    }

    $gitRoot = (& git rev-parse --show-toplevel)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
        throw "This folder is not a Git repository."
    }
    $gitRoot = (Resolve-Path -LiteralPath $gitRoot.Trim()).Path
    if (-not [string]::Equals($gitRoot, $repoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Run the updater from the repository root, not a nested checkout."
    }

    $branch = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $branch -ne "main") {
        throw "This updater only runs on the main branch. Current branch: $branch"
    }

    if (-not $AfterSync) {
        Write-Host "[1/5] Fetching origin/main..."
        & git fetch --prune origin main
        if ($LASTEXITCODE -ne 0) {
            throw "Git fetch failed. Local files were not reset."
        }

        Write-Host "[2/5] Replacing all tracked local files (including savegame.json)..."
        & git reset --hard origin/main
        if ($LASTEXITCODE -ne 0) { throw "Git reset failed." }

        # The script currently in memory may be an OLD version. Do not
        # execute any cleanup/deployment from that version. Always reload
        # the updater from disk after Git replaces the tracked files.
        Write-Host "[SYNC] Starting the freshly downloaded updater..."
        $updatedScript = Join-Path $repoRoot "tools\update-and-deploy.ps1"
        if (-not (Test-Path -LiteralPath $updatedScript -PathType Leaf)) {
            throw "The updated updater script is missing."
        }

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updatedScript -AfterSync
        if ($LASTEXITCODE -ne 0) {
            throw "The refreshed updater failed (exit code $LASTEXITCODE)."
        }
        $exitCode = 0
    }
    else {
        Write-Host "[3/5] Removing untracked Smart Import scripts..."
        & git clean -fd -- New live
        if ($LASTEXITCODE -ne 0) { throw "Git clean failed." }

        # Old .tts-backups/.tts-smart-backup folders are Git-ignored.
        # Do not traverse/delete historical .bak files: Windows long-path
        # errors in those folders must never block a GitHub update.

        Write-Host "[4/5] Deploying built sources to existing GUID scripts..."
        & python tools/deploy.py --apply
        if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }

        Write-Host "[5/5] Checking the build and GUID inventory..."
        & python tools/build.py --check
        if ($LASTEXITCODE -ne 0) { throw "Source and live scripts do not match." }
        & python tools/audit_objects.py .
        if ($LASTEXITCODE -ne 0) { throw "Duplicate TTS GUID files found." }

        & git log -1 --format="GitHub version: %h %s"
        Write-Host ""
        Write-Host "[SUCCESS] Updated from GitHub without creating backups."
        Write-Host "NEXT: In TTS use Smart Import / Save & Play."
        $exitCode = 0
    }
}
catch {
    Write-Host ""
    Write-Host ("[FAILED] " + $_.Exception.Message)
    Write-Host "Resolve the error before using Smart Import / Save & Play."
    $exitCode = 1
}
finally {
    Pop-Location
}
exit $exitCode
