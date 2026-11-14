#requires -Version 5.1
<#
  Shared 4-player / 6-player Tabletop Simulator updater.
  One-way sync from GitHub main. Local edits are intentionally discarded.
  No stash, no upload, and no backups are created.
#>
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$exitCode = 1

Write-Host ""
Write-Host "=== MTG TABLE: REPLACE LOCAL FILES FROM GITHUB ==="
Write-Host "Repository: $repoRoot"
Write-Host "WARNING: Local tracked edits and untracked scripts in New/ and live/ will be deleted."
Write-Host ""

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

    Write-Host "[1/5] Fetching origin/main..."
    & git fetch --prune origin main
    if ($LASTEXITCODE -ne 0) { throw "Git fetch failed. Local files were not reset." }

    Write-Host "[2/5] Replacing all tracked local files (including savegame.json)..."
    & git reset --hard origin/main
    if ($LASTEXITCODE -ne 0) { throw "Git reset failed." }

    Write-Host "[3/5] Removing untracked Smart Import scripts..."
    & git clean -fd -- New live
    if ($LASTEXITCODE -ne 0) { throw "Git clean failed." }

    # Ignore legacy .tts-backups/ and .tts-smart-backup/ folders.
    # Git already ignores them and tools/audit_objects.py skips them.
    # Never recursively traverse old .bak files; Windows PowerShell can
    # fail on long historical object filenames, aborting the update.

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
