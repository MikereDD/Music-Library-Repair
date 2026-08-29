#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$MainScript = (Join-Path (Split-Path -Parent $PSScriptRoot) "src\Repair-MusicLibrary.ps1"),
    [switch]$KeepWorkspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ExpectedVersion = (Get-Content -LiteralPath (Join-Path $RepoRoot "VERSION") -Raw).Trim()
$Workspace = Join-Path ([IO.Path]::GetTempPath()) ("Music-Library-Repair-RC-" + [guid]::NewGuid().ToString("N"))
$LibraryRoot = Join-Path $Workspace "library"
$StateRoot = Join-Path $Workspace "state"
$AuditRoot = Join-Path $StateRoot "audit"
$StageRoot = Join-Path $StateRoot "staging"
$Passes = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "RC ASSERTION FAILED: $Message" }
    $script:Passes.Add($Message)
    Write-Host ("  PASS  " + $Message)
}

function Invoke-FFmpegChecked {
    param([string[]]$Arguments)
    & ffmpeg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg failed with exit code $LASTEXITCODE" }
}

function New-SyntheticFlac {
    param([string]$Path,[string]$Title,[int]$Frequency=440)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Invoke-FFmpegChecked @(
        "-hide_banner","-loglevel","error","-y",
        "-f","lavfi","-i","sine=frequency=${Frequency}:duration=1.5",
        "-c:a","flac",
        "-metadata","title=$Title",
        "-metadata","artist=RC Test Artist",
        "-metadata","album_artist=RC Test Artist",
        "-metadata","album=RC Test Album",
        "-metadata","track=1",
        "-metadata","date=2026",
        $Path
    )
}

function New-SyntheticMp3 {
    param([string]$Path,[string]$Title,[int]$Frequency=550)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Invoke-FFmpegChecked @(
        "-hide_banner","-loglevel","error","-y",
        "-f","lavfi","-i","sine=frequency=${Frequency}:duration=1.5",
        "-c:a","libmp3lame","-b:a","192k",
        "-metadata","title=$Title",
        "-metadata","artist=RC Test Artist",
        "-metadata","album_artist=RC Test Artist",
        "-metadata","album=RC Test Album",
        "-metadata","track=1",
        "-metadata","date=2026",
        $Path
    )
}

try {
    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " MUSIC-LIBRARY-REPAIR RELEASE CANDIDATE TEST"
    Write-Host ("=" * 72)
    Write-Host "Expected version : $ExpectedVersion"
    Write-Host "Workspace        : $Workspace"
    Write-Host ""

    Assert-True (Test-Path -LiteralPath $MainScript -PathType Leaf) "main script exists"
    Assert-True ($null -ne (Get-Command ffmpeg -ErrorAction SilentlyContinue)) "ffmpeg is available"
    Assert-True ($null -ne (Get-Command ffprobe -ErrorAction SilentlyContinue)) "ffprobe is available"

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path -LiteralPath $MainScript), [ref]$tokens, [ref]$parseErrors
    )
    Assert-True (@($parseErrors).Count -eq 0) "main script parses with zero PowerShell errors"

    $scriptText = Get-Content -LiteralPath $MainScript -Raw
    $versionMatch = [regex]::Match($scriptText, '\$ToolVersion\s*=\s*"(?<version>[^"]+)"')
    Assert-True ($versionMatch.Success) "ToolVersion declaration is present"
    Assert-True ($versionMatch.Groups["version"].Value -eq $ExpectedVersion) "VERSION matches ToolVersion"

    $requiredSwitches = @(
        "AuditOnly","ReviewReplacementCandidates","StageReplacementCandidates",
        "ApplyStagedReplacements","VerifyReplacementTransactions","BackupOriginals","Yes"
    )
    $paramNames = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    foreach ($name in $requiredSwitches) {
        Assert-True ($paramNames -contains $name) "parameter -$name exists"
    }

    New-Item -ItemType Directory -Force -Path $LibraryRoot,$AuditRoot,$StageRoot | Out-Null

    # Safe synthetic audit.
    $AuditAlbum = Join-Path $LibraryRoot "Audit Artist\Audit Album (2026)"
    $AuditTrack = Join-Path $AuditAlbum "01 - RC Audit.flac"
    New-SyntheticFlac -Path $AuditTrack -Title "RC Audit" -Frequency 330

    & $MainScript -Root $LibraryRoot -StateRoot $StateRoot -AuditOnly
    Assert-True (Test-Path -LiteralPath (Join-Path $AuditRoot "tracks.csv")) "AuditOnly writes tracks.csv"
    Assert-True (Test-Path -LiteralPath (Join-Path $AuditRoot "albums.csv")) "AuditOnly writes albums.csv"
    Assert-True (Test-Path -LiteralPath (Join-Path $AuditRoot "source-decode-audit.csv")) "AuditOnly writes source-decode-audit.csv"

    $auditDecode = @(Import-Csv -LiteralPath (Join-Path $AuditRoot "source-decode-audit.csv"))
    $auditTrackRow = $auditDecode | Where-Object Path -eq $AuditTrack | Select-Object -First 1
    Assert-True ($null -ne $auditTrackRow) "synthetic audit track appears in decode report"
    Assert-True ([string]$auditTrackRow.SourceDecodeStatus -eq "PASS") "synthetic FLAC strict decode passes"

    # Synthetic replacement fixtures, all under TEMP.
    $TxAlbumA = Join-Path $LibraryRoot "Transaction Artist\Same Extension (2026)"
    $SourceSame = Join-Path $TxAlbumA "01 - Same Extension.flac"
    $StagedSame = Join-Path $StageRoot "same\01 - Same Extension.flac"
    New-SyntheticFlac -Path $SourceSame -Title "Old Same Extension" -Frequency 440
    New-SyntheticFlac -Path $StagedSame -Title "New Same Extension" -Frequency 660

    $TxAlbumB = Join-Path $LibraryRoot "Transaction Artist\Downgrade Gate (2026)"
    $SourceDowngrade = Join-Path $TxAlbumB "01 - Downgrade Gate.flac"
    $StagedDowngrade = Join-Path $StageRoot "downgrade\01 - Downgrade Gate.mp3"
    New-SyntheticFlac -Path $SourceDowngrade -Title "Downgrade Gate" -Frequency 770
    New-SyntheticMp3 -Path $StagedDowngrade -Title "Downgrade Gate" -Frequency 880

    $IntakePath = Join-Path $AuditRoot "replacement-candidate-intake.csv"
    $StageManifestPath = Join-Path $AuditRoot "replacement-staging-manifest.csv"

    @(
        [pscustomobject]@{
            SourcePath=$SourceSame; CandidatePath=$StagedSame; StageApproved="Yes";
            ReplaceApproved="No"; QualityDowngradeApproved="No"; ReviewNotes="RC same-extension fixture"
        },
        [pscustomobject]@{
            SourcePath=$SourceDowngrade; CandidatePath=$StagedDowngrade; StageApproved="Yes";
            ReplaceApproved="Yes"; QualityDowngradeApproved="No"; ReviewNotes="RC downgrade fixture"
        }
    ) | Export-Csv -LiteralPath $IntakePath -NoTypeInformation -Encoding UTF8

    @(
        [pscustomobject]@{
            StageStatus="StagedVerified"; BlockReason=""; SourcePath=$SourceSame; CandidatePath=$StagedSame;
            CandidateStatus="CandidateValidatedForReview"; ForcedDemuxer=""; StagedPath=$StagedSame;
            CandidateSHA256=(Get-FileHash $StagedSame -Algorithm SHA256).Hash.ToLowerInvariant();
            StagedSHA256=(Get-FileHash $StagedSame -Algorithm SHA256).Hash.ToLowerInvariant();
            CopyHashVerified="True"; StagedDecodeStatus="Pass"; StagedAt=(Get-Date).ToString("o")
        },
        [pscustomobject]@{
            StageStatus="StagedVerified"; BlockReason=""; SourcePath=$SourceDowngrade; CandidatePath=$StagedDowngrade;
            CandidateStatus="CandidateValidatedForReview"; ForcedDemuxer=""; StagedPath=$StagedDowngrade;
            CandidateSHA256=(Get-FileHash $StagedDowngrade -Algorithm SHA256).Hash.ToLowerInvariant();
            StagedSHA256=(Get-FileHash $StagedDowngrade -Algorithm SHA256).Hash.ToLowerInvariant();
            CopyHashVerified="True"; StagedDecodeStatus="Pass"; StagedAt=(Get-Date).ToString("o")
        }
    ) | Export-Csv -LiteralPath $StageManifestPath -NoTypeInformation -Encoding UTF8

    # Downgrade refusal.
    & $MainScript -Root $LibraryRoot -StateRoot $StateRoot -ApplyStagedReplacements -BackupOriginals -Yes
    $blocked = @(Import-Csv -LiteralPath (Join-Path $AuditRoot "replacement-transaction-manifest.csv"))
    Assert-True ($blocked.Count -eq 1) "only explicitly ReplaceApproved fixture is considered"
    Assert-True ($blocked[0].TransactionStatus -eq "Blocked") "unapproved quality downgrade is blocked"
    Assert-True ($blocked[0].BlockReason -eq "QualityDowngradeRequiresExplicitApproval") "downgrade block reason is explicit"
    Assert-True (Test-Path -LiteralPath $SourceDowngrade -PathType Leaf) "blocked downgrade leaves original source untouched"

    # Approve both and exercise same- plus cross-extension commit.
    $intake = @(Import-Csv -LiteralPath $IntakePath)
    foreach ($row in $intake) {
        $row.ReplaceApproved = "Yes"
        if ($row.SourcePath -eq $SourceDowngrade) { $row.QualityDowngradeApproved = "Yes" }
    }
    $intake | Export-Csv -LiteralPath $IntakePath -NoTypeInformation -Encoding UTF8

    & $MainScript -Root $LibraryRoot -StateRoot $StateRoot -ApplyStagedReplacements -BackupOriginals -Yes
    $tx = @(Import-Csv -LiteralPath (Join-Path $AuditRoot "replacement-transaction-manifest.csv"))
    Assert-True ($tx.Count -eq 2) "two approved synthetic transactions are recorded"
    Assert-True (@($tx | Where-Object TransactionStatus -eq "ReplacementCommitted").Count -eq 2) "same- and cross-extension replacements commit"

    $sameTx = $tx | Where-Object SourcePath -eq $SourceSame | Select-Object -First 1
    $downTx = $tx | Where-Object SourcePath -eq $SourceDowngrade | Select-Object -First 1
    Assert-True ($sameTx.BackupVerified -eq "True") "same-extension source backup is verified"
    Assert-True ($sameTx.ReplacementDecode -eq "Pass") "same-extension committed replacement strict-decodes"
    Assert-True (Test-Path -LiteralPath $SourceSame -PathType Leaf) "same-extension replacement remains at original path"

    $DowngradeTarget = [IO.Path]::ChangeExtension($SourceDowngrade, ".mp3")
    Assert-True ($downTx.QualityRelationship -eq "QualityDowngrade") "FLAC-to-MP3 relationship is recorded as QualityDowngrade"
    Assert-True ($downTx.QualityDowngradeApproved -eq "True") "downgrade transaction records explicit approval"
    Assert-True (-not (Test-Path -LiteralPath $SourceDowngrade -PathType Leaf)) "cross-extension commit removes original only after success"
    Assert-True (Test-Path -LiteralPath $DowngradeTarget -PathType Leaf) "cross-extension replacement is published with correct extension"
    Assert-True ($downTx.BackupVerified -eq "True") "cross-extension source backup is verified"
    Assert-True ($downTx.ReplacementDecode -eq "Pass") "cross-extension committed replacement strict-decodes"

    # Read-only post-verification.
    & $MainScript -Root $LibraryRoot -StateRoot $StateRoot -VerifyReplacementTransactions
    $post = @(Import-Csv -LiteralPath (Join-Path $AuditRoot "replacement-postverify.csv"))
    Assert-True ($post.Count -eq 2) "post-verifier sees both committed transactions"
    Assert-True (@($post | Where-Object VerificationStatus -eq "Verified").Count -eq 2) "both transactions pass post-verification"
    Assert-True (@($post | Where-Object QueueStatus -eq "ClearedByCurrentState").Count -eq 2) "both repaired items clear by current state"
    Assert-True (@($post | Where-Object AlbumSourceDecodeErrors -ne "0").Count -eq 0) "affected synthetic albums have zero source decode errors"

    $partials = @(Get-ChildItem -LiteralPath $LibraryRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object Name -like "*.partial")
    Assert-True ($partials.Count -eq 0) "no transaction partial files remain"

    $swapBackups = @(Get-ChildItem -LiteralPath $LibraryRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object Name -like "*.swap-backup-*")
    Assert-True ($swapBackups.Count -eq 0) "no same-directory swap backup files remain"

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " RC RESULT: PASS"
    Write-Host ("=" * 72)
    Write-Host "Assertions passed : $($Passes.Count)"
    Write-Host "Real library touched: NO"
    Write-Host "All destructive-path tests ran only under the temporary workspace."
}
finally {
    if ($KeepWorkspace) {
        Write-Host ""
        Write-Host "RC workspace retained:"
        Write-Host "  $Workspace"
    }
    elseif (Test-Path -LiteralPath $Workspace) {
        Remove-Item -LiteralPath $Workspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}
