#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Root,
    [string]$StateRoot = (Join-Path $HOME "Downloads\Music-Library-Repair"),
    [switch]$Resume,
    [switch]$ApplyApproved,
    [switch]$BackupOriginals,
    [switch]$Yes,
    [switch]$SkipSourceDecodeAudit,
    [switch]$AuditOnly,
    [switch]$AnalyzeAuditReports,
    [switch]$RecheckAuditFailures,
    [switch]$AnalyzeFailureSeverity,
    [switch]$ClassifyAuditFailures,
    [switch]$ReclassifyFailureDomains,
    [switch]$BuildRepairQueue,
    [switch]$AnalyzeReplacementReview,
    [switch]$AnalyzeReplacementEvidence,
    [ValidateRange(1,50)]
    [int]$FailureSamplesPerSignature = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ToolVersion = "0.7-dev.10.1"
$AudioExtensions = @(".mp3",".flac",".m4a",".aac",".ogg",".opus",".wav",".wma",".aiff",".aif",".ape",".wv",".m4b")
$ArtworkExtensions = @(".jpg",".jpeg",".png",".webp")

function Get-TagValue {
    param($Tags,[string[]]$Names)
    if ($null -eq $Tags) { return $null }
    foreach ($name in $Names) {
        $prop = $Tags.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) { return [string]$prop.Value }
    }
    return $null
}

function Get-NumberPart {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $n = 0
    if ([int]::TryParse((($Value -split '/')[0]).Trim(), [ref]$n)) { return $n }
    return $null
}

function Get-SafeFileName {
    param([string]$Name)
    $s = $Name -replace '"',''
    $s = $s -replace '[<>:/\\|?*]','-'
    $s = $s -replace '\s+',' '
    $s = $s.Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($s)) { $s = "Untitled" }
    return $s
}



function Test-SuspiciousTitle {
    param([string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) { return $false }

    # Classic ID3v1 title fields are limited to 30 characters.
    # A title landing exactly on 30 characters is not proof of truncation,
    # but it is suspicious enough to require review.
    return ($Title.Length -eq 30)
}

function Get-EffectiveTitle {
    param(
        $Track,
        [hashtable]$Plan
    )

    if ($Plan.ContainsKey("TitleOverrides") -and
        $null -ne $Plan.TitleOverrides -and
        $Plan.TitleOverrides.ContainsKey($Track.FileName)) {
        return [string]$Plan.TitleOverrides[$Track.FileName]
    }

    return [string]$Track.Title
}

function Test-SourceAudioDecode {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File
    )

    $output = @(
        # Disable video/subtitle/data processing at the input as well as the
        # output. This is important for MP3/FLAC files carrying malformed
        # attached artwork: bad cover art must not become SOURCE AUDIO ERROR.
        & ffmpeg -hide_banner -v error -xerror -err_detect explode `
            -vn -sn -dn -i $File.FullName `
            -map 0:a:0 -vn -sn -dn -f null - 2>&1
    )

    $exit = $LASTEXITCODE

    [pscustomobject]@{
        Clean     = ($exit -eq 0 -and $output.Count -eq 0)
        ExitCode  = $exit
        ErrorText = ($output -join " | ")
    }
}


function Sync-ReplacementQueue {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Tracks,
        [Parameter(Mandatory)]
        [hashtable]$State
    )

    if (-not $State.ContainsKey("replacements") -or $null -eq $State.replacements) {
        $State.replacements = @{}
    }

    if ($SkipSourceDecodeAudit) {
        return
    }

    $now = (Get-Date).ToString("o")
    $activeFailures = @(
        $Tracks |
        Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" }
    )

    $activePaths = @{}
    foreach ($track in $activeFailures) {
        $activePaths[$track.Path] = $true

        if ($State.replacements.ContainsKey($track.Path)) {
            $item = $State.replacements[$track.Path]

            # Keep first-detected history and any future workflow fields already
            # present in state, while refreshing the current audit evidence.
            $item.AlbumDirectory = $track.Directory
            $item.FileName = $track.FileName
            $item.Artist = $track.Artist
            $item.Album = $track.Album
            $item.Date = $track.Date
            $item.Disc = $track.Disc
            $item.Track = $track.Track
            $item.Title = $track.Title
            $item.DecodeExitCode = $track.SourceDecodeExitCode
            $item.DecodeError = $track.SourceDecodeError
            $item.LastDetectedAt = $now

            if (-not $item.ContainsKey("FirstDetectedAt") -or -not $item.FirstDetectedAt) {
                $item.FirstDetectedAt = $now
            }

            # A file that is failing again must be actionable even if a prior
            # run had marked the queue item otherwise.
            if (-not $item.ContainsKey("Status") -or
                [string]::IsNullOrWhiteSpace([string]$item.Status) -or
                $item.Status -eq "NoLongerFailing") {
                $item.Status = "Needed"
            }
        }
        else {
            $State.replacements[$track.Path] = @{
                SourcePath       = $track.Path
                AlbumDirectory   = $track.Directory
                FileName         = $track.FileName
                Artist           = $track.Artist
                Album            = $track.Album
                Date             = $track.Date
                Disc             = $track.Disc
                Track            = $track.Track
                Title            = $track.Title
                DecodeExitCode   = $track.SourceDecodeExitCode
                DecodeError      = $track.SourceDecodeError
                Status           = "Needed"
                CandidatePath    = $null
                CandidateStatus  = $null
                FirstDetectedAt  = $now
                LastDetectedAt   = $now
                ResolvedAt       = $null
            }
        }
    }

    # Preserve queue history. If an item previously failed but no longer does,
    # do not delete it; mark that fact for later replacement-workflow logic.
    foreach ($key in @($State.replacements.Keys)) {
        $item = $State.replacements[$key]
        if ($item.SourcePath -and
            $item.SourcePath.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $activePaths.ContainsKey($item.SourcePath) -and
            $item.Status -eq "Needed") {
            $item.Status = "NoLongerFailing"
        }
    }
}

function Export-ReplacementQueue {
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $rows = @(
        foreach ($item in $State.replacements.Values) {
            [pscustomobject]@{
                Status          = $item.Status
                SourcePath      = $item.SourcePath
                AlbumDirectory  = $item.AlbumDirectory
                Artist          = $item.Artist
                Album           = $item.Album
                Date            = $item.Date
                Disc            = $item.Disc
                Track           = $item.Track
                Title           = $item.Title
                FileName        = $item.FileName
                DecodeExitCode  = $item.DecodeExitCode
                DecodeError     = $item.DecodeError
                CandidatePath   = $item.CandidatePath
                CandidateStatus = $item.CandidateStatus
                FirstDetectedAt = $item.FirstDetectedAt
                LastDetectedAt  = $item.LastDetectedAt
                ResolvedAt      = $item.ResolvedAt
            }
        }
    )

    $rows |
        Sort-Object AlbumDirectory, Disc, Track, FileName |
        Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
}



function Invoke-BuildRepairQueue {
    param(
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][string]$ReclassifiedReportPath,
        [Parameter(Mandatory)][string]$ClassificationReportPath,
        [Parameter(Mandatory)][string]$TrackReportPath
    )

    $inputPath = $null

    if (Test-Path -LiteralPath $ReclassifiedReportPath -PathType Leaf) {
        $inputPath = $ReclassifiedReportPath
    }
    elseif (Test-Path -LiteralPath $ClassificationReportPath -PathType Leaf) {
        $inputPath = $ClassificationReportPath
    }
    else {
        throw "No failure classification report exists.`nRun -ClassifyAuditFailures and then -ReclassifyFailureDomains first."
    }

    $rows = @(Import-Csv -LiteralPath $inputPath)

    if ($rows.Count -eq 0) {
        Write-Host "Failure classification report is empty."
        return
    }

    $trackByPath = @{}
    if (Test-Path -LiteralPath $TrackReportPath -PathType Leaf) {
        foreach ($track in @(Import-Csv -LiteralPath $TrackReportPath)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$track.Path)) {
                $trackByPath[[string]$track.Path] = $track
            }
        }
    }

    $queuePath = Join-Path $OutputRoot "repair-action-queue.csv"
    $summaryPath = Join-Path $OutputRoot "repair-action-queue-summary.csv"
    $queue = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $path = [string]$row.Path
        $track = if ($trackByPath.ContainsKey($path)) { $trackByPath[$path] } else { $null }
        $action = [string]$row.Action

        $queueStatus = switch ($action) {
            "ReplacementReview" { "PendingReplacementReview" }
            "RepairArtwork"     { "PendingArtworkRepair" }
            "ContainerReview"   { "PendingContainerReview" }
            "AudioReview"       { "PendingAudioReview" }
            "LocateFile"        { "PendingLocateFile" }
            default             { "PendingManualReview" }
        }

        $queue.Add([pscustomobject]@{
            QueueStatus             = $queueStatus
            RecommendedAction       = $action
            PrimaryDomain           = $row.PrimaryDomain
            EvidenceDomain          = $row.EvidenceDomain
            Severity                = $row.Severity
            Signature               = $row.Signature
            SourcePath              = $path
            AlbumDirectory          = if ($track) { $track.Directory } else { $row.Directory }
            FileName                = if ($track) { $track.FileName } else { $row.FileName }
            Extension               = if ($track) { $track.Extension } else { $row.Extension }
            Artist                  = if ($track) { $track.Artist } else { $null }
            AlbumArtist             = if ($track) { $track.AlbumArtist } else { $null }
            Album                   = if ($track) { $track.Album } else { $null }
            Date                    = if ($track) { $track.Date } else { $null }
            Disc                    = if ($track) { $track.Disc } else { $null }
            Track                   = if ($track) { $track.Track } else { $null }
            Title                   = if ($track) { $track.Title } else { $null }
            ReportedDurationSeconds = $row.ReportedDurationSeconds
            DecodedDurationSeconds  = $row.DecodedDurationSeconds
            DecodedPercent          = $row.DecodedPercent
            TolerantExitCode        = $row.TolerantExitCode
            CandidatePath           = $null
            CandidateStatus         = $null
        })
    }

    $queue |
        Sort-Object RecommendedAction, PrimaryDomain, AlbumDirectory, Disc, Track, FileName |
        Export-Csv -LiteralPath $queuePath -NoTypeInformation -Encoding UTF8

    $summary = [System.Collections.Generic.List[object]]::new()

    foreach ($category in @("RecommendedAction","QueueStatus","PrimaryDomain","Severity")) {
        foreach ($group in ($queue | Group-Object $category | Sort-Object Count -Descending)) {
            $summary.Add([pscustomobject]@{
                Category = $category
                Name     = $group.Name
                Count    = $group.Count
            })
        }
    }

    $summary |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " REPAIR ACTION QUEUE BUILT"
    Write-Host ("=" * 72)
    Write-Host "Input : $inputPath"
    Write-Host "Items : $($queue.Count)"

    Write-Host ""
    Write-Host "Recommended action:"
    foreach ($group in ($queue | Group-Object RecommendedAction | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-26} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Queue status:"
    foreach ($group in ($queue | Group-Object QueueStatus | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-30} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $queuePath"
    Write-Host "  $summaryPath"
    Write-Host ""
    Write-Host "No audio was decoded."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
    Write-Host "ReplacementReview means review only; it does NOT authorize replacement."
}


function Invoke-AnalyzeReplacementReview {
    param(
        [Parameter(Mandatory)][string]$RepairQueuePath,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $RepairQueuePath -PathType Leaf)) {
        throw "Repair action queue not found: $RepairQueuePath`nRun -BuildRepairQueue first."
    }

    $queue = @(Import-Csv -LiteralPath $RepairQueuePath)
    $rows = @(
        $queue |
        Where-Object { $_.RecommendedAction -eq "ReplacementReview" }
    )

    if ($rows.Count -eq 0) {
        Write-Host "No ReplacementReview items exist in the repair action queue."
        return
    }

    $analysisPath = Join-Path $OutputRoot "replacement-review-analysis.csv"
    $summaryPath = Join-Path $OutputRoot "replacement-review-summary.csv"

    $analysis = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $reported = 0.0
        $decoded = 0.0
        $percent = 0.0
        $hasReported = [double]::TryParse([string]$row.ReportedDurationSeconds, [ref]$reported)
        $hasDecoded = [double]::TryParse([string]$row.DecodedDurationSeconds, [ref]$decoded)
        $hasPercent = [double]::TryParse([string]$row.DecodedPercent, [ref]$percent)

        $completionBand = if (-not $hasPercent) {
            "UnknownCompletion"
        }
        elseif ($percent -le 5) {
            "0-5%"
        }
        elseif ($percent -lt 50) {
            "5-50%"
        }
        elseif ($percent -lt 90) {
            "50-90%"
        }
        elseif ($percent -lt 99) {
            "90-99%"
        }
        elseif ($percent -lt 99.9) {
            "99-99.9%"
        }
        else {
            "99.9%+"
        }

        $evidenceAssessment = if ([string]$row.Severity -eq "MissingFile") {
            "SourceMissing"
        }
        elseif (-not $hasPercent) {
            "NeedsMoreEvidence"
        }
        elseif ($percent -le 5) {
            "VeryLowDecodedCompletion"
        }
        elseif ($percent -lt 90) {
            "SubstantialDecodedLoss"
        }
        elseif ($percent -lt 99.9) {
            "NearCompleteButDamaged"
        }
        else {
            "CompleteOrNearlyCompleteSevereDiagnostic"
        }

        $reviewPriority = switch ($evidenceAssessment) {
            "SourceMissing"                         { "P1" }
            "VeryLowDecodedCompletion"              { "P1" }
            "SubstantialDecodedLoss"                { "P1" }
            "NearCompleteButDamaged"                { "P2" }
            "CompleteOrNearlyCompleteSevereDiagnostic" { "P2" }
            default                                 { "P3" }
        }

        $analysis.Add([pscustomobject]@{
            ReviewPriority           = $reviewPriority
            EvidenceAssessment       = $evidenceAssessment
            CompletionBand           = $completionBand
            Severity                 = $row.Severity
            Signature                = $row.Signature
            PrimaryDomain            = $row.PrimaryDomain
            EvidenceDomain           = $row.EvidenceDomain
            Extension                = $row.Extension
            SourcePath               = $row.SourcePath
            AlbumDirectory           = $row.AlbumDirectory
            Artist                   = $row.Artist
            AlbumArtist              = $row.AlbumArtist
            Album                    = $row.Album
            Date                     = $row.Date
            Disc                     = $row.Disc
            Track                    = $row.Track
            Title                    = $row.Title
            ReportedDurationSeconds  = $row.ReportedDurationSeconds
            DecodedDurationSeconds   = $row.DecodedDurationSeconds
            DecodedPercent           = $row.DecodedPercent
            TolerantExitCode         = $row.TolerantExitCode
            CandidatePath            = $row.CandidatePath
            CandidateStatus          = $row.CandidateStatus
        })
    }

    $analysis |
        Sort-Object ReviewPriority, EvidenceAssessment, AlbumDirectory, Disc, Track, SourcePath |
        Export-Csv -LiteralPath $analysisPath -NoTypeInformation -Encoding UTF8

    $summary = [System.Collections.Generic.List[object]]::new()
    foreach ($category in @("ReviewPriority","EvidenceAssessment","CompletionBand","Severity","Signature","Extension")) {
        foreach ($group in ($analysis | Group-Object $category | Sort-Object -Property @{Expression='Count';Descending=$true}, @{Expression='Name';Descending=$false})) {
            $summary.Add([pscustomobject]@{
                Category = $category
                Name     = $group.Name
                Count    = $group.Count
            })
        }
    }

    $summary |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " REPLACEMENT REVIEW ANALYSIS"
    Write-Host ("=" * 72)
    Write-Host "Input : $RepairQueuePath"
    Write-Host "Items : $($analysis.Count)"

    Write-Host ""
    Write-Host "Evidence assessment:"
    foreach ($group in ($analysis | Group-Object EvidenceAssessment | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-42} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Completion band:"
    foreach ($group in ($analysis | Group-Object CompletionBand | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-20} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By signature:"
    foreach ($group in ($analysis | Group-Object Signature | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-42} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $analysisPath"
    Write-Host "  $summaryPath"
    Write-Host ""
    Write-Host "No audio was decoded."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
    Write-Host "This analysis prioritizes review evidence only; it does NOT authorize replacement."
}


function Invoke-AnalyzeReplacementEvidence {
    param(
        [Parameter(Mandatory)][string]$ReplacementReviewAnalysisPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $ReplacementReviewAnalysisPath -PathType Leaf)) {
        throw "Replacement-review analysis not found: $ReplacementReviewAnalysisPath`nRun -AnalyzeReplacementReview first."
    }

    $sourceRows = @(
        Import-Csv -LiteralPath $ReplacementReviewAnalysisPath |
        Where-Object { $_.EvidenceAssessment -eq "NeedsMoreEvidence" }
    )

    if ($sourceRows.Count -eq 0) {
        Write-Host "No NeedsMoreEvidence replacement-review items remain."
        return
    }

    $detailPath = Join-Path $OutputRoot "replacement-evidence-analysis.csv"
    $summaryPath = Join-Path $OutputRoot "replacement-evidence-summary.csv"
    $results = [System.Collections.Generic.List[object]]::new()

    $index = 0
    foreach ($row in $sourceRows) {
        $index++
        $path = [string]$row.SourcePath
        Write-Host ("[{0}/{1}] {2}" -f $index,$sourceRows.Count,$path)

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results.Add([pscustomobject]@{
                EvidenceResolution       = "MissingSourcePath"
                ReplacementConfidence    = "High"
                ProbeStatus              = "Missing"
                TargetedDecodeStatus     = "NotRun"
                OriginalSignature        = $row.Signature
                TargetedSignature        = $null
                Extension                = $row.Extension
                SourcePath               = $path
                AlbumDirectory           = $row.AlbumDirectory
                Artist                   = $row.Artist
                AlbumArtist              = $row.AlbumArtist
                Album                    = $row.Album
                Date                     = $row.Date
                Disc                     = $row.Disc
                Track                    = $row.Track
                Title                    = $row.Title
                ReportedDurationSeconds  = $null
                DecodedDurationSeconds   = $null
                DecodedPercent           = $null
                TolerantExitCode         = $null
                DiagnosticNote           = "Source path is missing."
            })
            continue
        }

        $reported = Get-ReportedAudioDurationSeconds -Path $path
        $diag = Invoke-TolerantAudioDecodeDiagnostic -Path $path
        $decoded = [double]$diag.DecodedSeconds

        $percent = $null
        if ($null -ne $reported -and [double]$reported -gt 0) {
            $percent = [math]::Round((100.0 * $decoded / [double]$reported), 3)
        }

        $probeStatus = if ($null -eq $reported) { "DurationUnavailable" } else { "DurationAvailable" }
        $decodeStatus = if ([int]$diag.ExitCode -eq 0) { "Completed" } else { "Error" }

        $originalSignature = [string]$row.Signature
        $targetedSignature = [string]$diag.ErrorSignature
        $looksLikeContainerOrHeader = (
            $originalSignature -like "Container:*" -or
            $originalSignature -eq "MP3 audio: header missing" -or
            $targetedSignature -like "Container:*" -or
            $targetedSignature -eq "MP3 audio: header missing"
        )

        $resolution = "NeedsManualInspection"
        $confidence = "Low"
        $note = "Targeted evidence remains ambiguous."

        if ($null -eq $reported) {
            if ([int]$diag.ExitCode -eq 0 -and $decoded -gt 0) {
                $resolution = "AudioDecodesButDurationUnknown"
                $confidence = "Low"
                $note = "Audio completed a tolerant decode, but ffprobe could not supply duration."
            }
            elseif ($decoded -le 0) {
                $resolution = "UnreadableMediaSource"
                $confidence = "High"
                $note = "Source exists, but ffprobe cannot determine duration and tolerant decode cannot recover measurable audio."
            }
            elseif ($looksLikeContainerOrHeader) {
                $resolution = "ContainerOrHeaderFailure"
                $confidence = "Medium"
                $note = "Some audio decoded, but container/header diagnostics prevent a trustworthy duration comparison."
            }
            else {
                $resolution = "ProbeDurationUnavailable"
                $confidence = "Low"
                $note = "ffprobe duration is unavailable and the targeted decode still returned an error."
            }
        }
        else {
            if ($null -ne $percent -and $percent -lt 95.0) {
                $resolution = "ConfirmedSevereAudioDamage"
                $confidence = "High"
                $note = "Targeted tolerant decode recovered less than 95% of the reported duration."
            }
            elseif ($looksLikeContainerOrHeader -and [int]$diag.ExitCode -ne 0) {
                $resolution = "ContainerOrHeaderFailure"
                $confidence = "Medium"
                $note = "Most audio is recoverable, but container/header diagnostics remain."
            }
            elseif ([int]$diag.ExitCode -eq 0 -and $null -ne $percent -and $percent -ge 99.9) {
                $resolution = "NeedsManualInspection"
                $confidence = "Low"
                $note = "Targeted tolerant decode now completes essentially the full reported duration."
            }
        }

        $results.Add([pscustomobject]@{
            EvidenceResolution       = $resolution
            ReplacementConfidence    = $confidence
            ProbeStatus              = $probeStatus
            TargetedDecodeStatus     = $decodeStatus
            OriginalSignature        = $originalSignature
            TargetedSignature        = $targetedSignature
            Extension                = $row.Extension
            SourcePath               = $path
            AlbumDirectory           = $row.AlbumDirectory
            Artist                   = $row.Artist
            AlbumArtist              = $row.AlbumArtist
            Album                    = $row.Album
            Date                     = $row.Date
            Disc                     = $row.Disc
            Track                    = $row.Track
            Title                    = $row.Title
            ReportedDurationSeconds  = $reported
            DecodedDurationSeconds   = $decoded
            DecodedPercent           = $percent
            TolerantExitCode         = $diag.ExitCode
            DiagnosticNote           = $note
        })
    }

    $results |
        Sort-Object EvidenceResolution, ReplacementConfidence, AlbumDirectory, Disc, Track, SourcePath |
        Export-Csv -LiteralPath $detailPath -NoTypeInformation -Encoding UTF8

    $summary = [System.Collections.Generic.List[object]]::new()
    foreach ($category in @(
        "EvidenceResolution",
        "ReplacementConfidence",
        "ProbeStatus",
        "TargetedDecodeStatus",
        "OriginalSignature",
        "TargetedSignature",
        "Extension"
    )) {
        foreach ($group in ($results | Group-Object $category | Sort-Object Count -Descending)) {
            $summary.Add([pscustomobject]@{
                Category = $category
                Name     = $group.Name
                Count    = $group.Count
            })
        }
    }

    $summary |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " REPLACEMENT EVIDENCE ANALYSIS"
    Write-Host ("=" * 72)
    Write-Host "Input : $ReplacementReviewAnalysisPath"
    Write-Host "Items : $($results.Count)"

    Write-Host ""
    Write-Host "Evidence resolution:"
    foreach ($group in ($results | Group-Object EvidenceResolution | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-38} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Replacement confidence:"
    foreach ($group in ($results | Group-Object ReplacementConfidence | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-20} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $detailPath"
    Write-Host "  $summaryPath"
    Write-Host ""
    Write-Host "Only the NeedsMoreEvidence subset was targeted."
    Write-Host "Audio was decoded for diagnosis only."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
    Write-Host "High replacement confidence still means review; it does NOT authorize replacement."
}


function Get-DecodeErrorSignature {
    param([string]$ErrorText)

    if ([string]::IsNullOrWhiteSpace($ErrorText)) {
        return "(no decoder error text)"
    }

    $normalized = $ErrorText
    $normalized = $normalized -replace '@\s*(?:0x)?[0-9A-Fa-f]{8,}', '@ <addr>'
    $normalized = $normalized -replace '\[(png|mjpeg|jpeg|webp|gif)\s+@\s+<addr>\]', '[$1]'
    $normalized = $normalized -replace '\[(mp3float|mp3|flac|aac|vorbis|opus|wmalossless|wmav2|alac)\s+@\s+<addr>\]', '[$1]'
    $normalized = $normalized -replace '\s+', ' '

    $rules = @(
        @{ Pattern='\[png\].*chunk too big';                         Signature='PNG artwork: chunk too big' },
        @{ Pattern='\[(?:mjpeg|jpeg)\].*No JPEG data found';         Signature='JPEG artwork: no JPEG data found' },
        @{ Pattern='\[webp\].*';                                     Signature='WebP artwork decode error' },
        @{ Pattern='\[gif\].*';                                      Signature='GIF artwork decode error' },
        @{ Pattern='\[(?:mp3float|mp3)\].*invalid new backstep';     Signature='MP3 audio: invalid new backstep' },
        @{ Pattern='\[(?:mp3float|mp3)\].*Header missing';           Signature='MP3 audio: header missing' },
        @{ Pattern='Header missing';                                 Signature='Audio: header missing' },
        @{ Pattern='Invalid data found when processing input';       Signature='Container: invalid input data' },
        @{ Pattern='Incorrect BOM value';                            Signature='Container: incorrect BOM' },
        @{ Pattern='Error while decoding stream';                    Signature='Audio: decode stream error' },
        @{ Pattern='Error submitting packet to decoder';             Signature='Audio: packet submission error' },
        @{ Pattern='Invalid frame size';                             Signature='Audio: invalid frame size' },
        @{ Pattern='Failed to read frame size';                      Signature='Audio: failed to read frame size' },
        @{ Pattern='CRC mismatch';                                   Signature='Audio: CRC mismatch' },
        @{ Pattern='moov atom not found';                            Signature='Container: moov atom missing' },
        @{ Pattern='Could not find codec parameters';                Signature='Container: codec parameters unavailable' },
        @{ Pattern='Invalid argument';                               Signature='Container/decoder: invalid argument' },
        @{ Pattern='End of file';                                    Signature='Container: unexpected EOF' }
    )

    foreach ($rule in $rules) {
        if ($normalized -match $rule.Pattern) {
            return $rule.Signature
        }
    }

    $first = (($normalized -split '\s*\|\s*')[0]).Trim()
    if ($first.Length -gt 180) {
        $first = $first.Substring(0, 180)
    }

    if ([string]::IsNullOrWhiteSpace($first)) {
        return "(unclassified decoder error)"
    }

    return $first
}

function Get-DecodeErrorDomain {
    param([string]$ErrorText)

    if ([string]::IsNullOrWhiteSpace($ErrorText)) {
        return "NONE"
    }

    $normalized = $ErrorText -replace '@\s*(?:0x)?[0-9A-Fa-f]{8,}', '@ <addr>'

    $hasArtwork = $normalized -match '\[(?:png|mjpeg|jpeg|webp|gif)\b' -or
                  $normalized -match 'No JPEG data found|chunk too big'

    $hasAudio = $normalized -match '\[(?:mp3float|mp3|flac|aac|vorbis|opus|wmalossless|wmav2|alac)\b' -or
                $normalized -match 'Header missing|invalid new backstep|Error while decoding stream|Error submitting packet to decoder|Invalid frame size|Failed to read frame size|CRC mismatch'

    $hasContainer = $normalized -match 'Invalid data found when processing input|Incorrect BOM value|moov atom not found|Could not find codec parameters|Invalid argument|End of file'

    if ($hasAudio -and $hasArtwork -and $hasContainer) { return "AUDIO+ARTWORK+CONTAINER" }
    if ($hasAudio -and $hasArtwork) { return "AUDIO+ARTWORK" }
    if ($hasAudio -and $hasContainer) { return "AUDIO+CONTAINER" }
    if ($hasArtwork -and $hasContainer) { return "ARTWORK+CONTAINER" }
    if ($hasAudio) { return "AUDIO" }
    if ($hasArtwork) { return "ARTWORK" }
    if ($hasContainer) { return "CONTAINER" }
    return "UNKNOWN"
}


function Get-PrimaryDomainFromSignature {
    param([string]$Signature)

    if ([string]::IsNullOrWhiteSpace($Signature)) {
        return "UNKNOWN"
    }

    switch -Regex ($Signature) {
        '^MP3 audio:'         { return "AUDIO" }
        '^Audio:'             { return "AUDIO" }
        '^PNG artwork:'       { return "ARTWORK" }
        '^JPEG artwork:'      { return "ARTWORK" }
        '^WebP artwork'       { return "ARTWORK" }
        '^GIF artwork'        { return "ARTWORK" }
        '^Container:'         { return "CONTAINER" }
        '^Container/decoder:' { return "CONTAINER" }
        default               { return "UNKNOWN" }
    }
}

function Get-FailureDisposition {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Nullable[double]]$ReportedSeconds,
        [double]$DecodedSeconds,
        [int]$TolerantExitCode
    )

    $ratio = $null
    if ($null -ne $ReportedSeconds -and $ReportedSeconds -gt 0) {
        $ratio = $DecodedSeconds / [double]$ReportedSeconds
    }

    if ($TolerantExitCode -ne 0) {
        return [pscustomobject]@{
            Severity = "Severe"
            Action   = if ($Domain -eq "ARTWORK") { "RepairArtworkThenRetest" } else { "ReplacementReview" }
        }
    }

    if ($null -eq $ratio) {
        return [pscustomobject]@{
            Severity = "DecodableWithErrors"
            Action   = switch ($Domain) {
                "ARTWORK"                 { "RepairArtwork" }
                "CONTAINER"               { "ContainerReview" }
                "AUDIO"                   { "AudioReview" }
                "AUDIO+ARTWORK"           { "ManualReview" }
                "AUDIO+CONTAINER"         { "ManualReview" }
                "ARTWORK+CONTAINER"       { "ManualReview" }
                "AUDIO+ARTWORK+CONTAINER" { "ManualReview" }
                default                   { "ManualReview" }
            }
        }
    }

    if ($ratio -lt 0.95) {
        return [pscustomobject]@{
            Severity = "Severe"
            Action   = if ($Domain -eq "ARTWORK") { "RepairArtworkThenRetest" } else { "ReplacementReview" }
        }
    }

    if ($ratio -lt 0.99) {
        return [pscustomobject]@{
            Severity = "MostlyDecodable"
            Action   = if ($Domain -eq "ARTWORK") { "RepairArtwork" } else { "AudioReview" }
        }
    }

    switch ($Domain) {
        "ARTWORK" {
            return [pscustomobject]@{
                Severity = "AudioCompleteArtworkError"
                Action   = "RepairArtwork"
            }
        }
        "CONTAINER" {
            return [pscustomobject]@{
                Severity = "AudioCompleteContainerError"
                Action   = "ContainerReview"
            }
        }
        "AUDIO" {
            return [pscustomobject]@{
                Severity = "AudioDegradedButComplete"
                Action   = "AudioReview"
            }
        }
        "AUDIO+ARTWORK" {
            return [pscustomobject]@{
                Severity = "AudioCompleteMixedError"
                Action   = "ManualReview"
            }
        }
        "AUDIO+CONTAINER" {
            return [pscustomobject]@{
                Severity = "AudioCompleteMixedError"
                Action   = "ManualReview"
            }
        }
        "ARTWORK+CONTAINER" {
            return [pscustomobject]@{
                Severity = "AudioCompleteMixedError"
                Action   = "ManualReview"
            }
        }
        "AUDIO+ARTWORK+CONTAINER" {
            return [pscustomobject]@{
                Severity = "AudioCompleteMixedError"
                Action   = "ManualReview"
            }
        }
        default {
            return [pscustomobject]@{
                Severity = "AudioCompleteUnknownError"
                Action   = "ManualReview"
            }
        }
    }
}

function Test-ProbeFailureValue {
    param($Value)

    if ($null -eq $Value) { return $false }

    $s = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    if ($s -ieq "False") { return $false }
    if ($s -eq "0") { return $false }

    return $true
}

function Export-AuditFailureClassification {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable]$Tracks,
        [Parameter(Mandatory)]
        [string]$OutputRoot
    )

    $all = @($Tracks)
    $failed = @($all | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" })

    $byExtensionPath = Join-Path $OutputRoot "decode-failures-by-extension.csv"
    $signaturePath = Join-Path $OutputRoot "decode-error-signatures.csv"
    $byAlbumPath = Join-Path $OutputRoot "decode-failures-by-album.csv"
    $crosscheckPath = Join-Path $OutputRoot "audit-crosscheck.csv"

    $byExtension = @(
        $all |
        Group-Object {
            $ext = [string]$_.Extension
            if ([string]::IsNullOrWhiteSpace($ext)) {
                $ext = [System.IO.Path]::GetExtension([string]$_.Path)
            }
            if ([string]::IsNullOrWhiteSpace($ext)) { "(none)" } else { $ext.ToLowerInvariant() }
        } |
        ForEach-Object {
            $items = @($_.Group)
            $decodeFail = @($items | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" })
            $probeFail = @($items | Where-Object { Test-ProbeFailureValue $_.ProbeError })
            $both = @($items | Where-Object {
                $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" -and
                (Test-ProbeFailureValue $_.ProbeError)
            })

            [pscustomobject]@{
                Extension            = $_.Name
                TotalFiles           = $items.Count
                DecodePass           = @($items | Where-Object { $_.SourceDecodeStatus -eq "PASS" }).Count
                DecodeFail           = $decodeFail.Count
                DecodeFailPercent    = if ($items.Count) { [math]::Round(($decodeFail.Count / $items.Count) * 100, 2) } else { 0 }
                ProbeErrors          = $probeFail.Count
                DecodeAndProbeErrors = $both.Count
            }
        } |
        Sort-Object @{Expression="DecodeFail";Descending=$true}, @{Expression="TotalFiles";Descending=$true}, Extension
    )
    $byExtension | Export-Csv -LiteralPath $byExtensionPath -NoTypeInformation -Encoding UTF8

    $signatureRows = @(
        $failed |
        Group-Object { Get-DecodeErrorSignature ([string]$_.SourceDecodeError) } |
        ForEach-Object {
            $items = @($_.Group)
            [pscustomobject]@{
                Signature  = $_.Name
                Files      = $items.Count
                Albums     = @($items.Directory | Where-Object { $_ } | Sort-Object -Unique).Count
                Extensions = (@(
                    $items | ForEach-Object {
                        $ext = [string]$_.Extension
                        if ([string]::IsNullOrWhiteSpace($ext)) {
                            $ext = [System.IO.Path]::GetExtension([string]$_.Path)
                        }
                        if ($ext) { $ext.ToLowerInvariant() }
                    } | Where-Object { $_ } | Sort-Object -Unique
                ) -join "; ")
            }
        } |
        Sort-Object @{Expression="Files";Descending=$true}, Signature
    )
    $signatureRows | Export-Csv -LiteralPath $signaturePath -NoTypeInformation -Encoding UTF8

    $albumRows = @(
        $all |
        Group-Object Directory |
        ForEach-Object {
            $items = @($_.Group)
            $bad = @($items | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" })

            if ($bad.Count -eq 0) { return }

            $pattern =
                if ($bad.Count -eq $items.Count) { "WholeAlbum" }
                elseif ($bad.Count -eq 1) { "IsolatedTrack" }
                elseif (($bad.Count / [math]::Max($items.Count, 1)) -ge 0.5) { "MostlyAlbum" }
                else { "PartialAlbum" }

            [pscustomobject]@{
                AlbumDirectory = $_.Name
                Artist         = Get-DominantValue $items.Artist
                Album          = Get-DominantValue $items.Album
                Tracks         = $items.Count
                DecodeFailures = $bad.Count
                FailurePercent = [math]::Round(($bad.Count / [math]::Max($items.Count, 1)) * 100, 2)
                Pattern        = $pattern
                Extensions     = (@(
                    $items | ForEach-Object {
                        $ext = [string]$_.Extension
                        if ([string]::IsNullOrWhiteSpace($ext)) {
                            $ext = [System.IO.Path]::GetExtension([string]$_.Path)
                        }
                        if ($ext) { $ext.ToLowerInvariant() }
                    } | Where-Object { $_ } | Sort-Object -Unique
                ) -join "; ")
            }
        } |
        Sort-Object @{Expression="DecodeFailures";Descending=$true}, @{Expression="FailurePercent";Descending=$true}, AlbumDirectory
    )
    $albumRows | Export-Csv -LiteralPath $byAlbumPath -NoTypeInformation -Encoding UTF8

    $crosscheckRows = @(
        $all |
        ForEach-Object {
            $decodeFail = $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR"
            $probeFail = Test-ProbeFailureValue $_.ProbeError

            $category =
                if ($decodeFail -and $probeFail) { "Decode+Probe" }
                elseif ($decodeFail) { "DecodeOnly" }
                elseif ($probeFail) { "ProbeOnly" }
                else { "Neither" }

            $ext = [string]$_.Extension
            if ([string]::IsNullOrWhiteSpace($ext)) {
                $ext = [System.IO.Path]::GetExtension([string]$_.Path)
            }

            [pscustomobject]@{
                Category = $category
                Path = $_.Path
                Directory = $_.Directory
                FileName = $_.FileName
                Extension = if ($ext) { $ext.ToLowerInvariant() } else { "(none)" }
                SourceDecodeStatus = $_.SourceDecodeStatus
                DecodeSignature = if ($decodeFail) { Get-DecodeErrorSignature ([string]$_.SourceDecodeError) } else { $null }
                ProbeError = $_.ProbeError
            }
        }
    )
    $crosscheckRows | Export-Csv -LiteralPath $crosscheckPath -NoTypeInformation -Encoding UTF8

    $patternSummary = @(
        $albumRows |
        Group-Object Pattern |
        ForEach-Object {
            [pscustomobject]@{
                Pattern = $_.Name
                Albums = $_.Count
                FailedTracks = [int](@($_.Group | Measure-Object DecodeFailures -Sum).Sum)
            }
        } |
        Sort-Object @{Expression="FailedTracks";Descending=$true}
    )

    $crossSummary = @(
        $crosscheckRows |
        Group-Object Category |
        ForEach-Object {
            [pscustomobject]@{ Category = $_.Name; Files = $_.Count }
        } |
        Sort-Object @{Expression="Files";Descending=$true}
    )

    return [pscustomobject]@{
        FailedTracks     = $failed.Count
        FailureAlbums    = $albumRows.Count
        ByExtension      = $byExtension
        Signatures       = $signatureRows
        AlbumPatterns    = $patternSummary
        Crosscheck       = $crossSummary
        ByExtensionPath  = $byExtensionPath
        SignaturePath    = $signaturePath
        ByAlbumPath      = $byAlbumPath
        CrosscheckPath   = $crosscheckPath
    }
}

function Show-AuditFailureClassification {
    param(
        [Parameter(Mandatory)]
        $Classification
    )

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " SOURCE FAILURE CLASSIFICATION"
    Write-Host ("=" * 72)
    Write-Host "Failed tracks  : $($Classification.FailedTracks)"
    Write-Host "Affected albums: $($Classification.FailureAlbums)"

    Write-Host ""
    Write-Host "Failures by extension:"
    foreach ($row in @($Classification.ByExtension | Where-Object { $_.DecodeFail -gt 0 } | Select-Object -First 12)) {
        Write-Host ("  {0,-8} {1,6} fail / {2,6} total  ({3,6}%)" -f $row.Extension,$row.DecodeFail,$row.TotalFiles,$row.DecodeFailPercent)
    }

    Write-Host ""
    Write-Host "Top decoder signatures:"
    foreach ($row in @($Classification.Signatures | Select-Object -First 12)) {
        Write-Host ("  {0,6}  {1}" -f $row.Files,$row.Signature)
    }

    Write-Host ""
    Write-Host "Failure concentration:"
    foreach ($row in $Classification.AlbumPatterns) {
        Write-Host ("  {0,-14} {1,5} album(s), {2,6} failed track(s)" -f $row.Pattern,$row.Albums,$row.FailedTracks)
    }

    Write-Host ""
    Write-Host "ffprobe / strict-decode cross-check:"
    foreach ($row in $Classification.Crosscheck) {
        Write-Host ("  {0,-14} {1,6}" -f $row.Category,$row.Files)
    }

    Write-Host ""
    Write-Host "Classification reports:"
    Write-Host "  $($Classification.ByExtensionPath)"
    Write-Host "  $($Classification.SignaturePath)"
    Write-Host "  $($Classification.ByAlbumPath)"
    Write-Host "  $($Classification.CrosscheckPath)"
}


function Invoke-AuditFailureRecheck {
    param(
        [Parameter(Mandatory)]
        [string]$TrackReportPath,
        [Parameter(Mandatory)]
        [string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $TrackReportPath -PathType Leaf)) {
        throw "Existing audit report not found: $TrackReportPath`nRun -AuditOnly first."
    }

    $rows = @(Import-Csv -LiteralPath $TrackReportPath)
    $oldFailures = @($rows | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" })
    $reportPath = Join-Path $OutputRoot "audio-only-recheck.csv"

    Write-Host "Existing strict-decode failures: $($oldFailures.Count)"
    Write-Host "Rechecking only those files with non-audio streams disabled..."
    Write-Host ""

    $results = [System.Collections.Generic.List[object]]::new()
    $i = 0

    foreach ($row in $oldFailures) {
        $i++
        Write-Progress -Activity "Audio-only failure recheck" -Status "$i / $($oldFailures.Count)" -PercentComplete (($i / [math]::Max($oldFailures.Count,1)) * 100)

        $path = [string]$row.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results.Add([pscustomobject]@{
                Path             = $path
                FileName         = $row.FileName
                Directory        = $row.Directory
                Extension        = $row.Extension
                PreviousStatus   = $row.SourceDecodeStatus
                RecheckStatus    = "MISSING FILE"
                RecheckExitCode  = $null
                RecheckError     = "File no longer exists."
                PreviousError    = $row.SourceDecodeError
            })
            continue
        }

        $decode = Test-SourceAudioDecode -File (Get-Item -LiteralPath $path)
        $results.Add([pscustomobject]@{
            Path             = $path
            FileName         = $row.FileName
            Directory        = $row.Directory
            Extension        = if ($row.Extension) { $row.Extension } else { [System.IO.Path]::GetExtension($path) }
            PreviousStatus   = $row.SourceDecodeStatus
            RecheckStatus    = if ($decode.Clean) { "PASS" } else { "SOURCE AUDIO ERROR" }
            RecheckExitCode  = $decode.ExitCode
            RecheckError     = $decode.ErrorText
            PreviousError    = $row.SourceDecodeError
        })
    }

    Write-Progress -Activity "Audio-only failure recheck" -Completed

    $results | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

    $pass = @($results | Where-Object { $_.RecheckStatus -eq "PASS" }).Count
    $fail = @($results | Where-Object { $_.RecheckStatus -eq "SOURCE AUDIO ERROR" }).Count
    $missing = @($results | Where-Object { $_.RecheckStatus -eq "MISSING FILE" }).Count

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " AUDIO-ONLY FAILURE RECHECK COMPLETE"
    Write-Host ("=" * 72)
    Write-Host "Previously failed : $($oldFailures.Count)"
    Write-Host "Now PASS          : $pass"
    Write-Host "Still audio error : $fail"
    Write-Host "Missing files     : $missing"
    Write-Host ""
    Write-Host "Report:"
    Write-Host "  $reportPath"
    Write-Host ""
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
}


function Get-ReportedAudioDurationSeconds {
    param([Parameter(Mandatory)][string]$Path)

    $raw = @(
        & ffprobe -v error -select_streams a:0 `
            -show_entries format=duration `
            -of default=noprint_wrappers=1:nokey=1 `
            -- $Path 2>&1
    )

    if ($LASTEXITCODE -ne 0) { return $null }

    $value = 0.0
    if ([double]::TryParse(
        (($raw | Select-Object -First 1) -as [string]),
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [ref]$value
    )) { return $value }

    return $null
}

function Invoke-TolerantAudioDecodeDiagnostic {
    param([Parameter(Mandatory)][string]$Path)

    $output = @(
        & ffmpeg -hide_banner -v error `
            -vn -sn -dn -i $Path `
            -map 0:a:0 -vn -sn -dn `
            -progress pipe:1 -nostats `
            -f null - 2>&1
    )
    $exitCode = $LASTEXITCODE
    $maxOutTimeUs = 0L
    $errorLines = [System.Collections.Generic.List[string]]::new()

    foreach ($lineObj in $output) {
        $line = [string]$lineObj

        if ($line -match '^out_time_us=(\d+)$') {
            $v = 0L
            if ([long]::TryParse($Matches[1], [ref]$v) -and $v -gt $maxOutTimeUs) {
                $maxOutTimeUs = $v
            }
            continue
        }

        if ($line -match '^(progress|bitrate|total_size|out_time_ms|out_time|dup_frames|drop_frames|speed|stream_\d+_\d+_q)=') {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $errorLines.Add($line.Trim())
        }
    }

    $errorText = $errorLines -join " | "

    [pscustomobject]@{
        ExitCode       = $exitCode
        DecodedSeconds = if ($maxOutTimeUs -gt 0) { [math]::Round(($maxOutTimeUs / 1000000.0), 3) } else { 0.0 }
        ErrorText      = $errorText
        ErrorSignature = Get-DecodeErrorSignature $errorText
    }
}



function Invoke-ReclassifyFailureDomains {
    param(
        [Parameter(Mandatory)][string]$ClassificationReportPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $ClassificationReportPath -PathType Leaf)) {
        throw "Existing failure classification report not found: $ClassificationReportPath`nRun -ClassifyAuditFailures first."
    }

    $rows = @(Import-Csv -LiteralPath $ClassificationReportPath)
    if ($rows.Count -eq 0) {
        Write-Host "Existing failure classification report is empty."
        return
    }

    $outPath = Join-Path $OutputRoot "failure-classification-reclassified.csv"
    $summaryPath = Join-Path $OutputRoot "failure-classification-reclassified-summary.csv"
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($row in $rows) {
        $signature = [string]$row.Signature
        $primaryDomain = Get-PrimaryDomainFromSignature $signature

        $evidenceDomain = if ($row.PSObject.Properties.Name -contains "EvidenceDomain" -and $row.EvidenceDomain) {
            [string]$row.EvidenceDomain
        }
        elseif ($row.PSObject.Properties.Name -contains "Domain" -and $row.Domain) {
            [string]$row.Domain
        }
        else {
            Get-DecodeErrorDomain ([string]$row.StrictError)
        }

        $reported = $null
        if ($row.ReportedDurationSeconds -ne "") {
            $tmpReported = 0.0
            if ([double]::TryParse(
                [string]$row.ReportedDurationSeconds,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$tmpReported
            )) {
                $reported = $tmpReported
            }
        }

        $decoded = 0.0
        $tmpDecoded = 0.0
        if ([double]::TryParse(
            [string]$row.DecodedDurationSeconds,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$tmpDecoded
        )) {
            $decoded = $tmpDecoded
        }

        $exitCode = 0
        $tmpExit = 0
        if ([int]::TryParse([string]$row.TolerantExitCode, [ref]$tmpExit)) {
            $exitCode = $tmpExit
        }

        if ([string]$row.Severity -eq "MissingFile") {
            $severity = "MissingFile"
            $action = "LocateFile"
        }
        else {
            $disp = Get-FailureDisposition `
                -Domain $primaryDomain `
                -ReportedSeconds $reported `
                -DecodedSeconds $decoded `
                -TolerantExitCode $exitCode
            $severity = $disp.Severity
            $action = $disp.Action
        }

        $results.Add([pscustomobject]@{
            Path                    = $row.Path
            Directory               = $row.Directory
            FileName                = $row.FileName
            Extension               = $row.Extension
            Signature               = $signature
            PrimaryDomain           = $primaryDomain
            EvidenceDomain          = $evidenceDomain
            Severity                = $severity
            Action                  = $action
            ReportedDurationSeconds = $row.ReportedDurationSeconds
            DecodedDurationSeconds  = $row.DecodedDurationSeconds
            DecodedPercent          = $row.DecodedPercent
            TolerantExitCode        = $row.TolerantExitCode
            TolerantErrorSignature  = $row.TolerantErrorSignature
            TolerantError           = $row.TolerantError
            StrictError             = $row.StrictError
        })
    }

    $results |
        Sort-Object Action, PrimaryDomain, Signature, Directory, FileName |
        Export-Csv -LiteralPath $outPath -NoTypeInformation -Encoding UTF8

    $summaryRows = [System.Collections.Generic.List[object]]::new()
    foreach ($category in @("Action","PrimaryDomain","EvidenceDomain","Severity","Signature")) {
        foreach ($group in ($results | Group-Object $category | Sort-Object Count -Descending)) {
            $summaryRows.Add([pscustomobject]@{
                Category = $category
                Name     = $group.Name
                Count    = $group.Count
            })
        }
    }

    $summaryRows | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " FAILURE DOMAIN RECLASSIFICATION COMPLETE"
    Write-Host ("=" * 72)

    Write-Host ""
    Write-Host "Recommended disposition:"
    foreach ($group in ($results | Group-Object Action | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-26} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By primary domain:"
    foreach ($group in ($results | Group-Object PrimaryDomain | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-24} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By evidence domain:"
    foreach ($group in ($results | Group-Object EvidenceDomain | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-24} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $outPath"
    Write-Host "  $summaryPath"
    Write-Host ""
    Write-Host "Existing decode measurements were reused; no audio was decoded again."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
}

function Invoke-FullFailureClassification {
    param(
        [Parameter(Mandatory)][string]$RecheckReportPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    if (-not (Test-Path -LiteralPath $RecheckReportPath -PathType Leaf)) {
        throw "Audio-only recheck report not found: $RecheckReportPath`nRun -RecheckAuditFailures first."
    }

    $rows = @(
        Import-Csv -LiteralPath $RecheckReportPath |
        Where-Object { $_.RecheckStatus -eq "SOURCE AUDIO ERROR" }
    )

    if ($rows.Count -eq 0) {
        Write-Host "No SOURCE AUDIO ERROR rows exist in the recheck report."
        return
    }

    $reportPath = Join-Path $OutputRoot "failure-classification.csv"
    $summaryPath = Join-Path $OutputRoot "failure-classification-summary.csv"
    $results = [System.Collections.Generic.List[object]]::new()

    Write-Host "Failures to classify : $($rows.Count)"
    Write-Host "This performs a tolerant audio decode of each failed file."
    Write-Host ""

    $i = 0
    foreach ($row in $rows) {
        $i++
        $path = [string]$row.Path
        $signature = Get-DecodeErrorSignature ([string]$row.RecheckError)
        $evidenceDomain = Get-DecodeErrorDomain ([string]$row.RecheckError)
        $primaryDomain = Get-PrimaryDomainFromSignature $signature

        Write-Progress `
            -Activity "Classifying audit failures" `
            -Status "$i / $($rows.Count)" `
            -PercentComplete (($i / [math]::Max($rows.Count,1)) * 100)

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results.Add([pscustomobject]@{
                Path                    = $path
                Directory               = $row.Directory
                FileName                = $row.FileName
                Extension               = $row.Extension
                Signature               = $signature
                PrimaryDomain           = $primaryDomain
                EvidenceDomain          = $evidenceDomain
                Severity                = "MissingFile"
                Action                  = "LocateFile"
                ReportedDurationSeconds = $null
                DecodedDurationSeconds  = $null
                DecodedPercent          = $null
                TolerantExitCode        = $null
                TolerantErrorSignature  = $null
                TolerantError           = "File no longer exists."
                StrictError             = $row.RecheckError
            })
            continue
        }

        $reported = Get-ReportedAudioDurationSeconds -Path $path
        $diag = Invoke-TolerantAudioDecodeDiagnostic -Path $path
        $disposition = Get-FailureDisposition `
            -Domain $primaryDomain `
            -ReportedSeconds $reported `
            -DecodedSeconds $diag.DecodedSeconds `
            -TolerantExitCode $diag.ExitCode

        $percent = $null
        if ($null -ne $reported -and $reported -gt 0) {
            $percent = [math]::Round(($diag.DecodedSeconds / [double]$reported) * 100, 2)
        }

        $results.Add([pscustomobject]@{
            Path                    = $path
            Directory               = $row.Directory
            FileName                = $row.FileName
            Extension               = if ($row.Extension) { $row.Extension } else { [System.IO.Path]::GetExtension($path) }
            Signature               = $signature
            PrimaryDomain           = $primaryDomain
            EvidenceDomain          = $evidenceDomain
            Severity                = $disposition.Severity
            Action                  = $disposition.Action
            ReportedDurationSeconds = $reported
            DecodedDurationSeconds  = $diag.DecodedSeconds
            DecodedPercent          = $percent
            TolerantExitCode        = $diag.ExitCode
            TolerantErrorSignature  = $diag.ErrorSignature
            TolerantError           = $diag.ErrorText
            StrictError             = $row.RecheckError
        })
    }

    Write-Progress -Activity "Classifying audit failures" -Completed

    $results |
        Sort-Object Action, PrimaryDomain, Signature, Directory, FileName |
        Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

    $summaryRows = [System.Collections.Generic.List[object]]::new()

    foreach ($group in ($results | Group-Object Action | Sort-Object Count -Descending)) {
        $summaryRows.Add([pscustomobject]@{
            Category = "Action"
            Name     = $group.Name
            Count    = $group.Count
        })
    }

    foreach ($group in ($results | Group-Object PrimaryDomain | Sort-Object Count -Descending)) {
        $summaryRows.Add([pscustomobject]@{
            Category = "PrimaryDomain"
            Name     = $group.Name
            Count    = $group.Count
        })
    }

    foreach ($group in ($results | Group-Object EvidenceDomain | Sort-Object Count -Descending)) {
        $summaryRows.Add([pscustomobject]@{
            Category = "EvidenceDomain"
            Name     = $group.Name
            Count    = $group.Count
        })
    }

    foreach ($group in ($results | Group-Object Severity | Sort-Object Count -Descending)) {
        $summaryRows.Add([pscustomobject]@{
            Category = "Severity"
            Name     = $group.Name
            Count    = $group.Count
        })
    }

    foreach ($group in ($results | Group-Object Signature | Sort-Object Count -Descending)) {
        $summaryRows.Add([pscustomobject]@{
            Category = "Signature"
            Name     = $group.Name
            Count    = $group.Count
        })
    }

    $summaryRows |
        Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " FULL FAILURE CLASSIFICATION COMPLETE"
    Write-Host ("=" * 72)

    Write-Host ""
    Write-Host "Recommended disposition:"
    foreach ($group in ($results | Group-Object Action | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-26} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By primary domain:"
    foreach ($group in ($results | Group-Object PrimaryDomain | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-24} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By evidence domain:"
    foreach ($group in ($results | Group-Object EvidenceDomain | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-24} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "By severity:"
    foreach ($group in ($results | Group-Object Severity | Sort-Object Count -Descending)) {
        Write-Host ("  {0,-30} {1,6}" -f $group.Name,$group.Count)
    }

    Write-Host ""
    Write-Host "Canonical signatures:"
    foreach ($group in ($results | Group-Object Signature | Sort-Object Count -Descending)) {
        Write-Host ("  {0,6}  {1}" -f $group.Count,$group.Name)
    }

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $reportPath"
    Write-Host "  $summaryPath"
    Write-Host ""
    Write-Host "Classification is diagnostic only; replacement state was not changed."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
}

function Invoke-FailureSeverityAnalysis {
    param(
        [Parameter(Mandatory)][string]$RecheckReportPath,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][int]$SamplesPerSignature
    )

    if (-not (Test-Path -LiteralPath $RecheckReportPath -PathType Leaf)) {
        throw "Audio-only recheck report not found: $RecheckReportPath`nRun -RecheckAuditFailures first."
    }

    $rows = @(
        Import-Csv -LiteralPath $RecheckReportPath |
        Where-Object { $_.RecheckStatus -eq "SOURCE AUDIO ERROR" }
    )

    if ($rows.Count -eq 0) {
        Write-Host "No SOURCE AUDIO ERROR rows exist in the recheck report."
        return
    }

    $withSignature = @(
        foreach ($row in $rows) {
            [pscustomobject]@{
                Row       = $row
                Signature = Get-DecodeErrorSignature ([string]$row.RecheckError)
                Domain    = Get-DecodeErrorDomain ([string]$row.RecheckError)
            }
        }
    )

    $selected = [System.Collections.Generic.List[object]]::new()

    foreach ($group in ($withSignature | Group-Object Signature | Sort-Object Count -Descending)) {
        $albumGroups = @($group.Group | Group-Object { $_.Row.Directory })
        $taken = 0

        foreach ($album in $albumGroups) {
            if ($taken -ge $SamplesPerSignature) { break }
            $selected.Add(@($album.Group | Select-Object -First 1)[0])
            $taken++
        }

        if ($taken -lt $SamplesPerSignature) {
            $already = @{}
            foreach ($s in $selected) {
                if ($s.Signature -eq $group.Name) { $already[[string]$s.Row.Path] = $true }
            }

            foreach ($candidate in $group.Group) {
                if ($taken -ge $SamplesPerSignature) { break }
                if (-not $already.ContainsKey([string]$candidate.Row.Path)) {
                    $selected.Add($candidate)
                    $already[[string]$candidate.Row.Path] = $true
                    $taken++
                }
            }
        }
    }

    $reportPath = Join-Path $OutputRoot "failure-severity-samples.csv"
    $results = [System.Collections.Generic.List[object]]::new()

    Write-Host "Known strict audit failures : $($rows.Count)"
    Write-Host "Canonical signatures        : $(($withSignature | Group-Object Signature).Count)"
    Write-Host "Error domains               : $(($withSignature | Group-Object Domain).Count)"
    Write-Host "Samples per signature       : $SamplesPerSignature"
    Write-Host "Files selected              : $($selected.Count)"
    Write-Host ""

    $i = 0
    foreach ($sample in $selected) {
        $i++
        $row = $sample.Row
        $path = [string]$row.Path

        Write-Progress -Activity "Failure severity analysis" `
            -Status "$i / $($selected.Count)" `
            -PercentComplete (($i / [math]::Max($selected.Count,1)) * 100)

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $results.Add([pscustomobject]@{
                Signature=$sample.Signature; Domain=$sample.Domain
                Severity="MissingFile"; Action="LocateFile"; Path=$path
                Directory=$row.Directory; FileName=$row.FileName; Extension=$row.Extension
                ReportedDurationSeconds=$null; DecodedDurationSeconds=$null; DecodedPercent=$null
                TolerantExitCode=$null; TolerantErrorSignature=$null
                TolerantError="File no longer exists."; StrictError=$row.RecheckError
            })
            continue
        }

        $reported = Get-ReportedAudioDurationSeconds -Path $path
        $diag = Invoke-TolerantAudioDecodeDiagnostic -Path $path
        $disposition = Get-FailureDisposition `
            -Domain $sample.Domain `
            -ReportedSeconds $reported `
            -DecodedSeconds $diag.DecodedSeconds `
            -TolerantExitCode $diag.ExitCode

        $percent = $null
        if ($null -ne $reported -and $reported -gt 0) {
            $percent = [math]::Round(($diag.DecodedSeconds / [double]$reported) * 100, 2)
        }

        $results.Add([pscustomobject]@{
            Signature=$sample.Signature; Domain=$sample.Domain
            Severity=$disposition.Severity; Action=$disposition.Action; Path=$path
            Directory=$row.Directory; FileName=$row.FileName
            Extension=if ($row.Extension) { $row.Extension } else { [System.IO.Path]::GetExtension($path) }
            ReportedDurationSeconds=$reported; DecodedDurationSeconds=$diag.DecodedSeconds
            DecodedPercent=$percent; TolerantExitCode=$diag.ExitCode
            TolerantErrorSignature=$diag.ErrorSignature; TolerantError=$diag.ErrorText
            StrictError=$row.RecheckError
        })
    }

    Write-Progress -Activity "Failure severity analysis" -Completed

    $results | Sort-Object Domain, Signature, Severity, Directory, FileName |
        Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8

    $summary = @(
        $results | Group-Object Severity | ForEach-Object {
            [pscustomobject]@{ Severity=$_.Name; Samples=$_.Count }
        } | Sort-Object Samples -Descending
    )

    $domainSummary = @(
        $results | Group-Object Domain | ForEach-Object {
            [pscustomobject]@{ Domain=$_.Name; Samples=$_.Count }
        } | Sort-Object Samples -Descending
    )

    $actionSummary = @(
        $results | Group-Object Action | ForEach-Object {
            [pscustomobject]@{ Action=$_.Name; Samples=$_.Count }
        } | Sort-Object Samples -Descending
    )

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " FAILURE SEVERITY SAMPLE ANALYSIS"
    Write-Host ("=" * 72)
    foreach ($row in $summary) {
        Write-Host ("  {0,-30} {1,6}" -f $row.Severity,$row.Samples)
    }

    Write-Host ""
    Write-Host "By error domain:"
    foreach ($row in $domainSummary) {
        Write-Host ("  {0,-12} {1,6}" -f $row.Domain,$row.Samples)
    }

    Write-Host ""
    Write-Host "Recommended disposition:"
    foreach ($row in $actionSummary) {
        Write-Host ("  {0,-26} {1,6}" -f $row.Action,$row.Samples)
    }

    Write-Host ""
    Write-Host "Per-signature sample results:"
    foreach ($group in ($results | Group-Object Signature | Sort-Object Count -Descending)) {
        $parts = @($group.Group | Group-Object Severity | ForEach-Object { "$($_.Name)=$($_.Count)" })
        $domain = @($group.Group.Domain | Sort-Object -Unique) -join "+"
        Write-Host ("  {0,6} sample(s)  [{1}] {2}" -f $group.Count,$domain,$group.Name)
        Write-Host ("           " + ($parts -join ", "))
    }

    Write-Host ""
    Write-Host "Report:"
    Write-Host "  $reportPath"
    Write-Host ""
    Write-Host "Classification is diagnostic only; replacement state was not changed."
    Write-Host "No media files were modified."
    Write-Host "Persistent repair state was NOT modified."
}

function Get-FFProbeInfo {
    param([System.IO.FileInfo]$File)
    try {
        $text = & ffprobe -v quiet -print_format json -show_format -show_streams -- $File.FullName
        if ($LASTEXITCODE -ne 0 -or -not $text) { throw "ffprobe failed with exit code $LASTEXITCODE" }
        $json = $text | ConvertFrom-Json
        $tags = $json.format.tags
        $embedded = @($json.streams | Where-Object {
            $_.codec_type -eq "video" -and $null -ne $_.disposition -and $_.disposition.attached_pic -eq 1
        })
        [pscustomobject]@{
            Path=$File.FullName
            Directory=$File.DirectoryName
            FileName=$File.Name
            Extension=$File.Extension.ToLowerInvariant()
            Title=(Get-TagValue $tags @("title"))
            Artist=(Get-TagValue $tags @("artist"))
            AlbumArtist=(Get-TagValue $tags @("album_artist","albumartist","album artist"))
            Album=(Get-TagValue $tags @("album"))
            TrackRaw=(Get-TagValue $tags @("track"))
            Track=(Get-NumberPart (Get-TagValue $tags @("track")))
            DiscRaw=(Get-TagValue $tags @("disc","discnumber"))
            Disc=(Get-NumberPart (Get-TagValue $tags @("disc","discnumber")))
            Date=(Get-TagValue $tags @("date","year"))
            Genre=(Get-TagValue $tags @("genre"))
            EmbeddedCover=($embedded.Count -gt 0)
            CoverCount=$embedded.Count
            ProbeError=$null
        }
    } catch {
        [pscustomobject]@{
            Path=$File.FullName; Directory=$File.DirectoryName; FileName=$File.Name; Extension=$File.Extension.ToLowerInvariant()
            Title=$null; Artist=$null; AlbumArtist=$null; Album=$null; TrackRaw=$null; Track=$null; DiscRaw=$null; Disc=$null
            Date=$null; Genre=$null; EmbeddedCover=$false; CoverCount=0; ProbeError=$_.Exception.Message
        }
    }
}

function Get-DominantValue {
    param($Values)
    $v = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($v.Count -eq 0) { return $null }
    return (($v | Group-Object | Sort-Object Count -Descending | Select-Object -First 1).Name)
}

function Get-PreferredArtwork {
    param([string]$Directory)

    $art = @(
        Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in $ArtworkExtensions }
    )

    if ($art.Count -eq 0) {
        return $null
    }

    $hit = $art |
        Where-Object { $_.Name -ieq "cover.jpg" } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($hit) { return $hit }

    $hit = $art |
        Where-Object { $_.BaseName -match '(?i)\bfront\b' } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($hit) { return $hit }

    $hit = $art |
        Where-Object { $_.Name -ieq "Folder.jpg" } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($hit) { return $hit }

    $hit = $art |
        Where-Object { $_.BaseName -match '(?i)cover|album' } |
        Sort-Object Length -Descending |
        Select-Object -First 1
    if ($hit) { return $hit }

    return ($art | Sort-Object Length -Descending | Select-Object -First 1)
}

function Get-ProposedName {
    param($Track,[string]$ArtistOverride)
    $artist = if ($ArtistOverride) { $ArtistOverride } else { $Track.Artist }
    if ($null -eq $Track.Track -or -not $Track.Title -or -not $artist) { return $null }
    $safeArtist = Get-SafeFileName $artist
    $safeTitle = Get-SafeFileName $Track.Title
    if ($Track.Disc) {
        return ("{0}-{1:D2} - {2} - {3}{4}" -f $Track.Disc,$Track.Track,$safeArtist,$safeTitle,$Track.Extension)
    }
    return ("{0:D2} - {1} - {2}{3}" -f $Track.Track,$safeArtist,$safeTitle,$Track.Extension)
}


function Get-AlbumPlan {
    param($Item)

    if ($state.plans.ContainsKey($Item.Directory)) {
        $existing = $state.plans[$Item.Directory]
        if (-not $existing.ContainsKey("TitleOverrides") -or $null -eq $existing.TitleOverrides) {
            $existing.TitleOverrides = @{}
        }
        if (-not $existing.ContainsKey("AllowMissingCover")) {
            $existing.AllowMissingCover = $false
        }
        if (-not $existing.ContainsKey("CoverSource")) {
            $existing.CoverSource = if ($existing.Cover) { "Existing plan" } else { $null }
        }
        if (-not $existing.ContainsKey("CoverReleaseId")) {
            $existing.CoverReleaseId = $null
        }
        return $existing
    }

    $plan = @{
        Artist      = $Item.PreferredArtist
        AlbumArtist = $Item.PreferredArtist
        Album       = $Item.Album
        Date        = $Item.Date
        Genre       = $Item.Genre
        Cover       = $Item.PreferredArtwork
        CoverSource = if ($Item.PreferredArtwork) { "Local artwork" } else { $null }
        CoverReleaseId = $null
        AllowMissingCover = $false
        TitleOverrides = @{}
    }

    $state.plans[$Item.Directory] = $plan
    return $plan
}

function Show-LocalArtwork {
    param([string]$Directory)

    return @(
        Get-ChildItem -LiteralPath $Directory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in $ArtworkExtensions } |
        Sort-Object Name
    )
}

function Edit-AlbumPlan {
    param($Item, [hashtable]$Plan)

    Write-Host ""
    Write-Host "Edit planned metadata. Press Enter to keep the current value."

    $v = Read-Host "Artist [$($Plan.Artist)]"
    if ($v) { $Plan.Artist = $v }

    $v = Read-Host "Album Artist [$($Plan.AlbumArtist)]"
    if ($v) { $Plan.AlbumArtist = $v }

    $v = Read-Host "Album [$($Plan.Album)]"
    if ($v) { $Plan.Album = $v }

    $v = Read-Host "Date [$($Plan.Date)]"
    if ($v) { $Plan.Date = $v }

    $v = Read-Host "Genre [$($Plan.Genre)]"
    if ($v) { $Plan.Genre = $v }

    $state.plans[$Item.Directory] = $Plan
}


function Get-CoverCacheDirectory {
    $dir = Join-Path $StateRoot "cover-cache"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Test-ImageFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }

    $output = @(
        & ffprobe -v error -select_streams v:0 -show_entries stream=codec_type `
            -of default=noprint_wrappers=1:nokey=1 -- $Path 2>&1
    )
    return ($LASTEXITCODE -eq 0 -and ($output -contains "video"))
}

function Save-ImageAsJpeg {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    & ffmpeg -hide_banner -loglevel error -y -i $Source -frames:v 1 -q:v 2 $Destination
    if ($LASTEXITCODE -ne 0 -or -not (Test-ImageFile $Destination)) {
        throw "Could not create a valid JPEG from artwork source: $Source"
    }
    return $Destination
}

function Get-EmbeddedCoverCandidate {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Tracks
    )

    return @(
        $Tracks |
        Where-Object { $_.Directory -eq $Item.Directory -and $_.EmbeddedCover } |
        Sort-Object Disc, Track, FileName |
        Select-Object -First 1
    ) | Select-Object -First 1
}

function Extract-EmbeddedCover {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$Tracks
    )

    $candidate = Get-EmbeddedCoverCandidate $Item $Tracks
    if (-not $candidate) {
        Write-Warning "No embedded artwork exists in this album."
        return $null
    }

    $cache = Get-CoverCacheDirectory
    $safe = Get-SafeFileName ("{0} - {1} - embedded" -f $Item.PreferredArtist, $Item.Album)
    $target = Join-Path $cache "$safe.jpg"

    & ffmpeg -hide_banner -loglevel error -y -i $candidate.Path `
        -map 0:v:0 -frames:v 1 -q:v 2 $target

    if ($LASTEXITCODE -ne 0 -or -not (Test-ImageFile $target)) {
        Write-Warning "Embedded artwork extraction failed: $($candidate.FileName)"
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        return $null
    }

    Write-Host "Recovered embedded artwork from: $($candidate.FileName)"
    return $target
}

function Search-OnlineCoverArt {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][hashtable]$Plan
    )

    $artist = [string]$Plan.Artist
    $album = [string]$Plan.Album

    if ([string]::IsNullOrWhiteSpace($artist) -or [string]::IsNullOrWhiteSpace($album)) {
        Write-Warning "Artist and album are required for online cover lookup."
        return $null
    }

    $query = 'artist:"{0}" AND release:"{1}"' -f $artist.Replace('"','\"'), $album.Replace('"','\"')
    $encoded = [uri]::EscapeDataString($query)
    $uri = "https://musicbrainz.org/ws/2/release/?query=$encoded&fmt=json&limit=10"

    $headers = @{
        "User-Agent" = "MusicLibraryRepair/$ToolVersion (interactive personal music-library repair tool)"
        "Accept" = "application/json"
    }

    Write-Host ""
    Write-Host "Searching MusicBrainz for:"
    Write-Host "  Artist: $artist"
    Write-Host "  Album : $album"

    try {
        $result = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 30
    }
    catch {
        Write-Warning "MusicBrainz lookup failed: $($_.Exception.Message)"
        return $null
    }

    $candidates = @($result.releases)
    if ($candidates.Count -eq 0) {
        Write-Host "No MusicBrainz release candidates found."
        return $null
    }

    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($release in $candidates) {
        $credit = @(
            $release.'artist-credit' |
            ForEach-Object {
                if ($_.artist) { $_.artist.name }
                elseif ($_.name) { $_.name }
            }
        ) -join ", "

        $trackCount = 0
        foreach ($medium in @($release.media)) {
            if ($null -ne $medium.'track-count') {
                $trackCount += [int]$medium.'track-count'
            }
        }

        $rows.Add([pscustomobject]@{
            Id = [string]$release.id
            Title = [string]$release.title
            Artist = $credit
            Date = [string]$release.date
            Country = [string]$release.country
            Status = [string]$release.status
            Tracks = $trackCount
            Score = $release.score
        })
    }

    Write-Host ""
    Write-Host "MusicBrainz candidates:"
    for ($i=0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        Write-Host ("[{0}] {1} — {2} | {3} | {4} | {5} tracks | score {6}" -f `
            ($i+1), $r.Artist, $r.Title, $r.Date, $r.Country, $r.Tracks, $r.Score)
    }

    Write-Host ""
    $choice = (Read-Host "Choose exact release number (Enter cancels)").Trim()
    if (-not $choice) { return $null }

    $n = 0
    if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $rows.Count) {
        Write-Warning "Invalid release selection."
        return $null
    }

    $selected = $rows[$n-1]
    Start-Sleep -Milliseconds 1100

    $caaUri = "https://coverartarchive.org/release/$($selected.Id)"
    try {
        $caa = Invoke-RestMethod -Uri $caaUri -Headers @{
            "Accept"="application/json"
            "User-Agent"=$headers["User-Agent"]
        } -Method Get -TimeoutSec 30
    }
    catch {
        Write-Warning "No Cover Art Archive entry was available for that exact release."
        return $null
    }

    $front = @($caa.images | Where-Object { $_.front -eq $true } | Select-Object -First 1)
    if ($front.Count -eq 0) {
        Write-Warning "That exact release has no front cover in Cover Art Archive."
        return $null
    }

    $imageUrl = [string]$front[0].image
    if ([string]::IsNullOrWhiteSpace($imageUrl)) {
        Write-Warning "Cover Art Archive returned no downloadable front image."
        return $null
    }

    $cache = Get-CoverCacheDirectory
    $safe = Get-SafeFileName ("{0} - {1} - {2}" -f $artist, $album, $selected.Id)
    $download = Join-Path $cache "$safe.download"
    $target = Join-Path $cache "$safe.jpg"

    try {
        Invoke-WebRequest -Uri $imageUrl -Headers @{ "User-Agent"=$headers["User-Agent"] } `
            -OutFile $download -TimeoutSec 60
        Save-ImageAsJpeg -Source $download -Destination $target | Out-Null
    }
    catch {
        Write-Warning "Cover download/validation failed: $($_.Exception.Message)"
        Remove-Item -LiteralPath $download,$target -Force -ErrorAction SilentlyContinue
        return $null
    }
    finally {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "Downloaded exact-release front cover:"
    Write-Host "  Release : $($selected.Artist) — $($selected.Title)"
    Write-Host "  Date    : $($selected.Date)"
    Write-Host "  Country : $($selected.Country)"
    Write-Host "  MBID    : $($selected.Id)"
    Write-Host "  Cache   : $target"

    return [pscustomobject]@{
        Path = $target
        ReleaseId = $selected.Id
        Source = "MusicBrainz + Cover Art Archive"
    }
}

function Set-ManualCoverPath {
    param([hashtable]$Plan)

    $external = (Read-Host "Image file path").Trim().Trim('"')
    if (-not $external) { return $false }

    if (-not (Test-Path -LiteralPath $external -PathType Leaf)) {
        Write-Warning "Artwork file not found: $external"
        return $false
    }

    $ext = [System.IO.Path]::GetExtension($external).ToLowerInvariant()
    if ($ext -notin $ArtworkExtensions) {
        Write-Warning "Unsupported artwork type: $ext"
        return $false
    }

    if (-not (Test-ImageFile $external)) {
        Write-Warning "The selected file is not a valid readable image."
        return $false
    }

    $Plan.Cover = (Resolve-Path -LiteralPath $external).Path
    $Plan.CoverSource = "Manual file"
    $Plan.CoverReleaseId = $null
    $Plan.AllowMissingCover = $false
    return $true
}

function Choose-AlbumCover {
    param(
        $Item,
        [hashtable]$Plan,
        $Tracks
    )

    $art = @(Show-LocalArtwork $Item.Directory)
    $embeddedCandidate = Get-EmbeddedCoverCandidate $Item $Tracks

    Write-Host ""
    Write-Host "Cover artwork resolver"
    Write-Host "----------------------"

    if ($art.Count -gt 0) {
        Write-Host "Local artwork:"
        for ($i = 0; $i -lt $art.Count; $i++) {
            $selectedName = if ([System.IO.Path]::IsPathRooted([string]$Plan.Cover)) {
                $null
            } else {
                [string]$Plan.Cover
            }
            $mark = if ($art[$i].Name -eq $selectedName) { "*" } else { " " }
            Write-Host ("[{0}] {1} {2} ({3:N0} bytes)" -f ($i + 1), $mark, $art[$i].Name, $art[$i].Length)
        }
        Write-Host ""
    }
    else {
        Write-Host "Local artwork: NONE"
    }

    if ($embeddedCandidate) {
        Write-Host "Embedded artwork: available in at least one track"
    }
    else {
        Write-Host "Embedded artwork: NONE"
    }

    Write-Host ""
    Write-Host "[O] Search MusicBrainz + Cover Art Archive"
    if ($embeddedCandidate) { Write-Host "[E] Recover embedded artwork from album" }
    Write-Host "[P] Use image from another file path"
    Write-Host "[M] Explicitly continue with cover missing"
    Write-Host "[Q] Cancel"

    if ($art.Count -gt 0) {
        Write-Host "[1-$($art.Count)] Choose local artwork above"
    }

    Write-Host ""
    $choice = (Read-Host "Choice").Trim()
    if (-not $choice) { return }

    $upper = $choice.ToUpperInvariant()

    if ($upper -eq "Q") { return }

    if ($upper -eq "P") {
        if (Set-ManualCoverPath $Plan) {
            $state.plans[$Item.Directory] = $Plan
            Write-Host "Planned cover: $($Plan.Cover)"
        }
        return
    }

    if ($upper -eq "E" -and $embeddedCandidate) {
        $recovered = Extract-EmbeddedCover $Item $Tracks
        if ($recovered) {
            $Plan.Cover = $recovered
            $Plan.CoverSource = "Recovered embedded artwork"
            $Plan.CoverReleaseId = $null
            $Plan.AllowMissingCover = $false
            $state.plans[$Item.Directory] = $Plan
            Write-Host "Planned recovered cover: $recovered"
        }
        return
    }

    if ($upper -eq "O") {
        $online = Search-OnlineCoverArt $Item $Plan
        if ($online) {
            $Plan.Cover = $online.Path
            $Plan.CoverSource = $online.Source
            $Plan.CoverReleaseId = $online.ReleaseId
            $Plan.AllowMissingCover = $false
            $state.plans[$Item.Directory] = $Plan
            Write-Host "Planned online cover: $($Plan.Cover)"
        }
        return
    }

    if ($upper -eq "M") {
        $confirm = (Read-Host "Type MISSING to explicitly allow this album without cover art").Trim()
        if ($confirm -ceq "MISSING") {
            $Plan.Cover = $null
            $Plan.CoverSource = "Explicitly missing"
            $Plan.CoverReleaseId = $null
            $Plan.AllowMissingCover = $true
            $state.plans[$Item.Directory] = $Plan
            Write-Warning "Album is explicitly marked to continue without cover artwork."
        }
        else {
            Write-Host "Cover-missing choice cancelled."
        }
        return
    }

    $n = 0
    if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $art.Count) {
        $Plan.Cover = $art[$n - 1].Name
        $Plan.CoverSource = "Local artwork"
        $Plan.CoverReleaseId = $null
        $Plan.AllowMissingCover = $false
        $state.plans[$Item.Directory] = $Plan
        Write-Host "Planned cover: $($Plan.Cover)"
        return
    }

    Write-Warning "Invalid cover-art selection."
}

function Edit-TrackTitles {
    param(
        $Item,
        [hashtable]$Plan,
        $Tracks
    )

    if (-not $Plan.ContainsKey("TitleOverrides") -or $null -eq $Plan.TitleOverrides) {
        $Plan.TitleOverrides = @{}
    }

    $albumTracks = @(
        $Tracks |
        Where-Object { $_.Directory -eq $Item.Directory } |
        Sort-Object Disc, Track, FileName
    )

    Write-Host ""
    Write-Host "Track-title review."
    Write-Host "Press Enter to keep a title unchanged."
    Write-Host "Entering the same title still marks a suspicious title as reviewed."
    Write-Host ""

    foreach ($track in $albumTracks) {
        $current = Get-EffectiveTitle $track $Plan
        $flag = if ($track.SuspiciousTitle -and -not $Plan.TitleOverrides.ContainsKey($track.FileName)) {
            " [POSSIBLE ID3v1 TRUNCATION]"
        } else {
            ""
        }

        Write-Host ("{0}: {1}{2}" -f $track.FileName, $current, $flag)
        $v = Read-Host "New title"
        if ($v) {
            $Plan.TitleOverrides[$track.FileName] = $v
        }
        elseif ($track.SuspiciousTitle -and -not $Plan.TitleOverrides.ContainsKey($track.FileName)) {
            # Explicitly reviewing and pressing Enter means keep it as-is.
            $Plan.TitleOverrides[$track.FileName] = $current
        }
        Write-Host ""
    }

    $state.plans[$Item.Directory] = $Plan
}

function Show-AlbumPlan {
    param($Item, [hashtable]$Plan, $Tracks)

    Write-Host ""
    Write-Host "Planned metadata:"
    Write-Host "  Artist       : $($Plan.Artist)"
    Write-Host "  Album Artist : $($Plan.AlbumArtist)"
    Write-Host "  Album        : $($Plan.Album)"
    Write-Host "  Date         : $($Plan.Date)"
    Write-Host "  Genre        : $($Plan.Genre)"
    $coverText = if ($Plan.Cover) { $Plan.Cover } elseif ($Plan.AllowMissingCover) { "[EXPLICITLY MISSING]" } else { "[UNRESOLVED]" }
    Write-Host "  Cover        : $coverText"
    Write-Host "  Cover Source : $($Plan.CoverSource)"
    if ($Plan.CoverReleaseId) {
        Write-Host "  Cover MBID   : $($Plan.CoverReleaseId)"
    }
    Write-Host ""

    $albumTracks = @(
        $Tracks |
        Where-Object { $_.Directory -eq $Item.Directory } |
        Sort-Object Disc, Track, FileName
    )

    $changesShown = 0
    $notReadyShown = 0

    foreach ($track in $albumTracks) {
        $title = Get-EffectiveTitle $track $Plan
        $proposed = Get-ProposedName ([pscustomobject]@{
            Track=$track.Track
            Title=$title
            Artist=$track.Artist
            Disc=$track.Disc
            Extension=$track.Extension
        }) $Plan.Artist

        $flag = if ($track.SuspiciousTitle -and -not $Plan.TitleOverrides.ContainsKey($track.FileName)) {
            "  [POSSIBLE ID3v1 TRUNCATION]"
        } else {
            ""
        }

        if ($proposed -and $proposed -cne $track.FileName) {
            Write-Host "  $($track.FileName)$flag"
            Write-Host "    -> $proposed"
            $changesShown++
        }
        elseif (-not $proposed) {
            Write-Host "  [NOT READY] $($track.FileName)$flag"
            $notReadyShown++
        }
        elseif ($flag) {
            Write-Host "  $($track.FileName)$flag"
        }
    }

    if ($changesShown -eq 0 -and $notReadyShown -eq 0) {
        Write-Host "  No rename changes proposed for this album."
    }
}


function New-CanonicalCover {
    param(
        [Parameter(Mandatory)][string]$AlbumDirectory,
        [Parameter(Mandatory)][string]$SelectedCover
    )

    $source = if ([System.IO.Path]::IsPathRooted($SelectedCover)) {
        $SelectedCover
    } else {
        Join-Path $AlbumDirectory $SelectedCover
    }

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Selected cover does not exist: $source"
    }

    $target = Join-Path $AlbumDirectory "cover.jpg"

    if ((Resolve-Path -LiteralPath $source).Path -ieq $target) {
        return $target
    }

    $ext = [System.IO.Path]::GetExtension($source).ToLowerInvariant()

    if ($ext -in @(".jpg", ".jpeg")) {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
    else {
        & ffmpeg -hide_banner -loglevel error -y -i $source -frames:v 1 -q:v 2 $target
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Could not convert selected artwork to cover.jpg"
        }
    }

    return $target
}

function Get-FinalTrackNameForPlan {
    param(
        $Track,
        [hashtable]$Plan
    )

    $effectiveTitle = Get-EffectiveTitle $Track $Plan

    if ($null -eq $Track.Track -or -not $effectiveTitle -or -not $Plan.Artist) {
        return $null
    }

    $safeArtist = Get-SafeFileName $Plan.Artist
    $safeTitle = Get-SafeFileName $effectiveTitle

    if ($Track.Disc) {
        return ("{0}-{1:D2} - {2} - {3}{4}" -f `
            $Track.Disc, $Track.Track, $safeArtist, $safeTitle, $Track.Extension)
    }

    return ("{0:D2} - {1} - {2}{3}" -f `
        $Track.Track, $safeArtist, $safeTitle, $Track.Extension)
}

function Test-TempTrack {
    param(
        [Parameter(Mandatory)][string]$TempPath,
        [Parameter(Mandatory)]$Track,
        [Parameter(Mandatory)][hashtable]$Plan,
        [Parameter(Mandatory)][int]$Total,
        [bool]$ExpectCover = $true
    )

    # Full audio decode check.
    # IMPORTANT: ffmpeg can print decoder errors yet still return exit code 0.
    # -xerror makes any decoder error fatal so a "PASS" really means a clean decode.
    $decodeOutput = @(
        & ffmpeg -hide_banner -v error -xerror -err_detect explode `
            -vn -sn -dn -i $TempPath `
            -map 0:a:0 -vn -sn -dn -f null - 2>&1
    )

    if ($LASTEXITCODE -ne 0 -or $decodeOutput.Count -gt 0) {
        if ($decodeOutput.Count -gt 0) {
            Write-Warning ("Decode verification output: " + ($decodeOutput -join " | "))
        }
        return $false
    }

    $probe = Get-FFProbeInfo (Get-Item -LiteralPath $TempPath)

    if ($probe.ProbeError) { return $false }
    if ($ExpectCover -and -not $probe.EmbeddedCover) { return $false }
    if (-not $ExpectCover -and $probe.EmbeddedCover) { return $false }
    $expectedTitle = Get-EffectiveTitle $Track $Plan
    if ($probe.Title -cne $expectedTitle) { return $false }
    if ($probe.Artist -cne $Plan.Artist) { return $false }
    if ($probe.AlbumArtist -cne $Plan.AlbumArtist) { return $false }
    if ($probe.Album -cne $Plan.Album) { return $false }
    if ($probe.Date -cne $Plan.Date) { return $false }
    if ($probe.Genre -cne $Plan.Genre) { return $false }

    $expectedTrack = "$($Track.Track)/$Total"
    if ($probe.TrackRaw -cne $expectedTrack) { return $false }

    return $true
}

function Invoke-ApprovedApply {
    param(
        [switch]$BackupOriginals,
        [switch]$Yes
    )

    $approved = @(
        $state.reviewed.GetEnumerator() |
        Where-Object { $_.Value -eq "Reviewed" } |
        Sort-Object Name
    )

    if ($approved.Count -eq 0) {
        Write-Host ""
        Write-Host "No approved albums are present in state.json."
        return
    }

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " APPLY APPROVED PLANS"
    Write-Host ("=" * 72)
    Write-Host "Approved albums : $($approved.Count)"
    Write-Host "Backup originals: $BackupOriginals"
    Write-Host ""
    Write-Host "This mode WILL rewrite approved MP3 files, replace embedded artwork,"
    Write-Host "normalize metadata, and rename files to the planned naming standard."
    Write-Host "Audio is stream-copied; it is not re-encoded."
    Write-Host ""

    if (-not $Yes) {
        $confirm = Read-Host 'Type APPLY to continue'
        if ($confirm -cne "APPLY") {
            Write-Host "Apply cancelled."
            return
        }
    }

    $applyRows = [System.Collections.Generic.List[object]]::new()
    $ApplyReport = Join-Path $StateRoot "apply-report.csv"

    foreach ($approvedEntry in $approved) {
        $albumDir = [string]$approvedEntry.Name

        Write-Host ""
        Write-Host ("-" * 72)
        Write-Host "Album: $albumDir"

        if (-not $state.plans.ContainsKey($albumDir)) {
            Write-Warning "No saved plan. Skipping."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="No saved plan"})
            continue
        }

        $plan = $state.plans[$albumDir]

        if (-not $plan.ContainsKey("AllowMissingCover")) { $plan.AllowMissingCover = $false }

        $albumTracks = @(
            $tracks |
            Where-Object { $_.Directory -eq $albumDir } |
            Sort-Object Track, FileName
        )

        if (-not $SkipSourceDecodeAudit) {
            $badSource = @($albumTracks | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" })
            if ($badSource.Count -gt 0) {
                Write-Warning "$($badSource.Count) source track(s) fail strict decode. Album will not be modified."
                foreach ($bad in $badSource) {
                    Write-Host "  SOURCE DECODE ERROR: $($bad.FileName)"
                }
                $applyRows.Add([pscustomobject]@{
                    Album=$albumDir
                    Status="SKIPPED"
                    Detail="$($badSource.Count) source decode error(s)"
                })
                continue
            }
        }

        if ($albumTracks.Count -eq 0) {
            Write-Warning "No audio tracks found. Skipping."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="No tracks"})
            continue
        }

        # v0.6 apply remains deliberately MP3-only.
        $unsupported = @($albumTracks | Where-Object { $_.Extension -ne ".mp3" })
        if ($unsupported.Count -gt 0) {
            Write-Warning "v0.6 Apply supports MP3 albums only. Skipping this album."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="Unsupported audio type in v0.6"})
            continue
        }

        $notReady = @($albumTracks | Where-Object {
            $null -eq $_.Track -or -not (Get-EffectiveTitle $_ $plan)
        })

        if ($notReady.Count -gt 0) {
            Write-Warning "One or more tracks lack title/track metadata. Skipping album."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="Track metadata incomplete"})
            continue
        }

        # Ensure final names are unique before touching anything.
        $finalNames = foreach ($track in $albumTracks) {
            Get-FinalTrackNameForPlan $track $plan
        }

        $dupes = @($finalNames | Group-Object | Where-Object { $_.Count -gt 1 })
        if ($dupes.Count -gt 0 -or @($finalNames | Where-Object { -not $_ }).Count -gt 0) {
            Write-Warning "Final filename collision or incomplete name plan. Skipping album."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="Filename collision/incomplete plan"})
            continue
        }

        $coverPath = $null
        if ($plan.Cover) {
            try {
                $coverPath = New-CanonicalCover -AlbumDirectory $albumDir -SelectedCover $plan.Cover
            }
            catch {
                Write-Warning $_.Exception.Message
                $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail=$_.Exception.Message})
                continue
            }
        }
        elseif (-not $plan.AllowMissingCover) {
            Write-Warning "Cover artwork is unresolved. Skipping."
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="SKIPPED";Detail="Cover unresolved"})
            continue
        }

        $work = [System.Collections.Generic.List[object]]::new()
        $albumFailed = $false
        $total = $albumTracks.Count

        # Phase A: build + verify every replacement while originals remain untouched.
        for ($i = 0; $i -lt $albumTracks.Count; $i++) {
            $track = $albumTracks[$i]
            $finalName = $finalNames[$i]
            $finalPath = Join-Path $albumDir $finalName
            $tempPath = Join-Path $albumDir (".__mlr_new_{0}_{1:D3}.mp3" -f ([guid]::NewGuid().ToString("N")), ($i + 1))

            $effectiveTitle = Get-EffectiveTitle $track $plan
            Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $total, $effectiveTitle)

            $args = @(
                "-hide_banner","-loglevel","error","-y",
                "-i",$track.Path
            )

            if ($coverPath) {
                $args += @(
                    "-i",$coverPath,
                    "-map","0:a:0",
                    "-map","1:v:0"
                )
            }
            else {
                $args += @("-map","0:a:0")
            }

            $args += @(
                "-map_metadata","-1",
                "-c:a","copy"
            )

            if ($coverPath) {
                $args += @(
                    "-c:v","mjpeg",
                    "-disposition:v:0","attached_pic"
                )
            }

            $args += @(
                "-id3v2_version","3",
                "-metadata","title=$effectiveTitle",
                "-metadata","artist=$($plan.Artist)",
                "-metadata","album_artist=$($plan.AlbumArtist)",
                "-metadata","album=$($plan.Album)",
                "-metadata","date=$($plan.Date)",
                "-metadata","track=$($track.Track)/$total",
                "-metadata","genre=$($plan.Genre)"
            )

            if ($coverPath) {
                $args += @(
                    "-metadata:s:v:0","title=Album cover",
                    "-metadata:s:v:0","comment=Cover (front)"
                )
            }

            $args += $tempPath

            & ffmpeg @args

            if (-not (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
                Write-Warning "FFmpeg did not create replacement: $($track.FileName)"
                $albumFailed = $true
                break
            }

            if (-not (Test-TempTrack -TempPath $tempPath -Track $track -Plan $plan -Total $total -ExpectCover ([bool]$coverPath))) {
                Write-Warning "Verification failed: $($track.FileName)"
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
                $albumFailed = $true
                break
            }

            $work.Add([pscustomobject]@{
                Source=$track.Path
                OriginalName=$track.FileName
                Final=$finalPath
                FinalName=$finalName
                Temp=$tempPath
                StagedOriginal=$null
            })
        }

        if ($albumFailed) {
            foreach ($row in $work) {
                Remove-Item -LiteralPath $row.Temp -Force -ErrorAction SilentlyContinue
            }
            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="FAILED";Detail="Build/verification failed; originals untouched"})
            continue
        }

        # Optional persistent backup before replacement.
        if ($BackupOriginals) {
            try {
                $relative = [System.IO.Path]::GetRelativePath($Root, $albumDir)
                $backupDir = Join-Path (Join-Path $StateRoot "Backups") $relative
                New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

                foreach ($row in $work) {
                    Copy-Item -LiteralPath $row.Source -Destination (Join-Path $backupDir $row.OriginalName) -Force
                }

                if ($coverPath) {
                    Copy-Item -LiteralPath $coverPath -Destination (Join-Path $backupDir "cover.jpg") -Force
                }
            }
            catch {
                Write-Warning "Backup failed; album will not be modified: $($_.Exception.Message)"
                foreach ($row in $work) {
                    Remove-Item -LiteralPath $row.Temp -Force -ErrorAction SilentlyContinue
                }
                $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="FAILED";Detail="Backup failed; originals untouched"})
                continue
            }
        }

        # Phase B: stage every original under a temporary name.
        $stageFailed = $false
        for ($i = 0; $i -lt $work.Count; $i++) {
            $row = $work[$i]
            $staged = Join-Path $albumDir (".__mlr_original_{0}_{1:D3}.mp3" -f ([guid]::NewGuid().ToString("N")), ($i + 1))

            try {
                Move-Item -LiteralPath $row.Source -Destination $staged -ErrorAction Stop
                $row.StagedOriginal = $staged
            }
            catch {
                Write-Warning "Could not stage original (possibly in use): $($row.OriginalName)"
                $stageFailed = $true
                break
            }
        }

        if ($stageFailed) {
            # Roll back any originals already staged.
            foreach ($row in $work) {
                if ($row.StagedOriginal -and (Test-Path -LiteralPath $row.StagedOriginal)) {
                    try {
                        Move-Item -LiteralPath $row.StagedOriginal -Destination $row.Source -ErrorAction Stop
                    } catch {
                        Write-Warning "ROLLBACK WARNING: could not restore $($row.OriginalName)"
                    }
                }
                Remove-Item -LiteralPath $row.Temp -Force -ErrorAction SilentlyContinue
            }

            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="FAILED";Detail="Locked/staging failure; rollback attempted"})
            continue
        }

        # Phase C: install every verified replacement.
        $installFailed = $false
        $installed = [System.Collections.Generic.List[object]]::new()

        foreach ($row in $work) {
            try {
                Move-Item -LiteralPath $row.Temp -Destination $row.Final -ErrorAction Stop
                $installed.Add($row)
            }
            catch {
                Write-Warning "Could not install replacement: $($row.FinalName)"
                $installFailed = $true
                break
            }
        }

        if ($installFailed) {
            # Remove installed replacements, then restore all originals.
            foreach ($row in $installed) {
                Remove-Item -LiteralPath $row.Final -Force -ErrorAction SilentlyContinue
            }

            foreach ($row in $work) {
                if (Test-Path -LiteralPath $row.Temp) {
                    Remove-Item -LiteralPath $row.Temp -Force -ErrorAction SilentlyContinue
                }
                if ($row.StagedOriginal -and (Test-Path -LiteralPath $row.StagedOriginal)) {
                    try {
                        Move-Item -LiteralPath $row.StagedOriginal -Destination $row.Source -ErrorAction Stop
                    } catch {
                        Write-Warning "ROLLBACK WARNING: could not restore $($row.OriginalName)"
                    }
                }
            }

            $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="FAILED";Detail="Install failed; rollback attempted"})
            continue
        }

        # Phase D: replacements are installed. Remove staged originals.
        foreach ($row in $work) {
            Remove-Item -LiteralPath $row.StagedOriginal -Force -ErrorAction SilentlyContinue
        }

        $state.applied[$albumDir] = @{
            status="Applied"
            appliedAt=(Get-Date).ToString("o")
            tracks=$total
            cover="cover.jpg"
        }

        Write-Host "PASS - $total tracks repaired and verified."
        $applyRows.Add([pscustomobject]@{Album=$albumDir;Status="PASS";Detail="$total tracks applied"})
    }

    $applyRows | Export-Csv -LiteralPath $ApplyReport -NoTypeInformation -Encoding UTF8

    $state.generatedAt=(Get-Date).ToString("o")
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StateFile -Encoding UTF8

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " APPLY COMPLETE"
    Write-Host ("=" * 72)
    Write-Host "Report: $ApplyReport"
    Write-Host "State : $StateFile"
}

if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "Root directory does not exist: $Root" }

$exclusiveModes = @(
    @(
        [bool]$AuditOnly,
        [bool]$AnalyzeAuditReports,
        [bool]$RecheckAuditFailures,
        [bool]$AnalyzeFailureSeverity,
        [bool]$ClassifyAuditFailures,
        [bool]$ReclassifyFailureDomains,
        [bool]$BuildRepairQueue,
        [bool]$AnalyzeReplacementReview,
        [bool]$AnalyzeReplacementEvidence,
        [bool]$ApplyApproved
    ) | Where-Object { $_ }
)

if ($exclusiveModes.Count -gt 1) {
    throw "-AuditOnly, -AnalyzeAuditReports, -RecheckAuditFailures, -AnalyzeFailureSeverity, -ClassifyAuditFailures, -ReclassifyFailureDomains, -BuildRepairQueue, -AnalyzeReplacementReview, -AnalyzeReplacementEvidence, and -ApplyApproved are mutually exclusive modes."
}

if (-not $AnalyzeAuditReports -and -not $RecheckAuditFailures -and -not $AnalyzeFailureSeverity -and -not $ClassifyAuditFailures -and -not $ReclassifyFailureDomains -and -not $BuildRepairQueue -and -not $AnalyzeReplacementReview -and -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffprobe was not found in PATH."
}

if (($RecheckAuditFailures -or $AnalyzeFailureSeverity -or $ClassifyAuditFailures -or $AnalyzeReplacementEvidence) -and -not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg was not found in PATH."
}
if (($AnalyzeFailureSeverity -or $ClassifyAuditFailures) -and -not (Get-Command ffprobe -ErrorAction SilentlyContinue)) {
    throw "ffprobe was not found in PATH."
}

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

# Audit/report-analysis output is intentionally isolated from persistent repair
# state so whole-library analysis cannot overwrite an in-progress review.
$ReportRoot = if ($AuditOnly -or $AnalyzeAuditReports -or $RecheckAuditFailures -or $AnalyzeFailureSeverity -or $ClassifyAuditFailures -or $ReclassifyFailureDomains -or $BuildRepairQueue -or $AnalyzeReplacementReview -or $AnalyzeReplacementEvidence) { Join-Path $StateRoot "audit" } else { $StateRoot }
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$StateFile = Join-Path $StateRoot "state.json"
$TrackReport = Join-Path $ReportRoot "tracks.csv"
$AlbumReport = Join-Path $ReportRoot "albums.csv"
$PlanReport = Join-Path $ReportRoot "rename-plan.csv"
$ReplacementReport = Join-Path $ReportRoot "replacement-needed.csv"
$DecodeReport = Join-Path $ReportRoot "source-decode-audit.csv"
$AudioOnlyRecheckReport = Join-Path $ReportRoot "audio-only-recheck.csv"
$FailureClassificationReport = Join-Path $ReportRoot "failure-classification.csv"
$FailureReclassifiedReport = Join-Path $ReportRoot "failure-classification-reclassified.csv"
$RepairActionQueueReport = Join-Path $ReportRoot "repair-action-queue.csv"
$ReplacementReviewAnalysisReport = Join-Path $ReportRoot "replacement-review-analysis.csv"

Write-Host ""
Write-Host "=== Music Library Repair v$ToolVersion ==="
Write-Host "Root : $Root"
$modeName = if ($ApplyApproved) {
    "APPLY APPROVED"
}
elseif ($AnalyzeReplacementEvidence) {
    "ANALYZE REPLACEMENT EVIDENCE"
}
elseif ($AnalyzeReplacementReview) {
    "ANALYZE REPLACEMENT REVIEW"
}
elseif ($BuildRepairQueue) {
    "BUILD REPAIR QUEUE"
}
elseif ($ReclassifyFailureDomains) {
    "RECLASSIFY FAILURE DOMAINS"
}
elseif ($ClassifyAuditFailures) {
    "CLASSIFY ALL AUDIT FAILURES"
}
elseif ($AnalyzeFailureSeverity) {
    "ANALYZE FAILURE SEVERITY"
}
elseif ($RecheckAuditFailures) {
    "RECHECK AUDIT FAILURES"
}
elseif ($AnalyzeAuditReports) {
    "ANALYZE AUDIT REPORTS"
}
elseif ($AuditOnly) {
    "AUDIT ONLY"
}
else {
    "READ-ONLY discovery/review"
}
Write-Host "Mode : $modeName"
Write-Host ""

if ($AnalyzeReplacementEvidence) {
    Invoke-AnalyzeReplacementEvidence `
        -ReplacementReviewAnalysisPath $ReplacementReviewAnalysisReport `
        -OutputRoot $ReportRoot
    return
}

if ($AnalyzeReplacementReview) {
    Invoke-AnalyzeReplacementReview `
        -RepairQueuePath $RepairActionQueueReport `
        -OutputRoot $ReportRoot
    return
}

if ($BuildRepairQueue) {
    Invoke-BuildRepairQueue `
        -OutputRoot $ReportRoot `
        -ReclassifiedReportPath $FailureReclassifiedReport `
        -ClassificationReportPath $FailureClassificationReport `
        -TrackReportPath $TrackReport
    return
}

if ($ReclassifyFailureDomains) {
    Invoke-ReclassifyFailureDomains `
        -ClassificationReportPath $FailureClassificationReport `
        -OutputRoot $ReportRoot
    return
}

if ($ClassifyAuditFailures) {
    Invoke-FullFailureClassification `
        -RecheckReportPath $AudioOnlyRecheckReport `
        -OutputRoot $ReportRoot
    return
}

if ($AnalyzeFailureSeverity) {
    Invoke-FailureSeverityAnalysis `
        -RecheckReportPath $AudioOnlyRecheckReport `
        -OutputRoot $ReportRoot `
        -SamplesPerSignature $FailureSamplesPerSignature
    return
}

if ($RecheckAuditFailures) {
    Invoke-AuditFailureRecheck -TrackReportPath $TrackReport -OutputRoot $ReportRoot
    return
}

if ($AnalyzeAuditReports) {
    if (-not (Test-Path -LiteralPath $TrackReport -PathType Leaf)) {
        throw "Existing audit report not found: $TrackReport`nRun -AuditOnly first."
    }

    Write-Host "Loading existing audit report:"
    Write-Host "  $TrackReport"

    $existingTracks = @(Import-Csv -LiteralPath $TrackReport)
    Write-Host "Tracks loaded: $($existingTracks.Count)"

    $classification = Export-AuditFailureClassification -Tracks $existingTracks -OutputRoot $ReportRoot
    Show-AuditFailureClassification -Classification $classification

    Write-Host ""
    Write-Host "No media files were decoded or modified."
    Write-Host "Persistent repair state was NOT modified."
    return
}

$files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension.ToLowerInvariant() -in $AudioExtensions })

Write-Host "Audio files discovered: $($files.Count)"
$tracks = [System.Collections.Generic.List[object]]::new()
$sourceDecodeFailures = 0

for ($i=0; $i -lt $files.Count; $i++) {
    $pct = ((($i+1)/[math]::Max($files.Count,1))*100)

    if (($i % 25) -eq 0 -or $i -eq ($files.Count - 1)) {
        Write-Progress -Activity "Reading metadata" -Status "$($i+1) / $($files.Count)" -PercentComplete $pct
    }

    $info = Get-FFProbeInfo $files[$i]

    $decode = [pscustomobject]@{
        Clean = $null
        ExitCode = $null
        ErrorText = $null
    }

    if (-not $SkipSourceDecodeAudit) {
        if (($i % 10) -eq 0 -or $i -eq ($files.Count - 1)) {
            Write-Progress -Activity "Strict source audio audit" -Status "$($i+1) / $($files.Count)" -PercentComplete $pct
        }

        $decode = Test-SourceAudioDecode $files[$i]
        if (-not $decode.Clean) {
            $sourceDecodeFailures++
        }
    }

    $tracks.Add([pscustomobject]@{
        Path=$info.Path
        Directory=$info.Directory
        FileName=$info.FileName
        Extension=$info.Extension
        Title=$info.Title
        Artist=$info.Artist
        AlbumArtist=$info.AlbumArtist
        Album=$info.Album
        TrackRaw=$info.TrackRaw
        Track=$info.Track
        DiscRaw=$info.DiscRaw
        Disc=$info.Disc
        Date=$info.Date
        Genre=$info.Genre
        EmbeddedCover=$info.EmbeddedCover
        CoverCount=$info.CoverCount
        ProbeError=$info.ProbeError
        SuspiciousTitle=(Test-SuspiciousTitle $info.Title)
        SourceDecodeStatus=if ($SkipSourceDecodeAudit) { "NOT CHECKED" } elseif ($decode.Clean) { "PASS" } else { "SOURCE DECODE ERROR" }
        SourceDecodeExitCode=$decode.ExitCode
        SourceDecodeError=$decode.ErrorText
    })
}

Write-Progress -Activity "Reading metadata" -Completed
Write-Progress -Activity "Strict source audio audit" -Completed

if ($SkipSourceDecodeAudit) {
    Write-Host "Source decode audit : SKIPPED"
}
else {
    Write-Host "Source decode audit : $($files.Count - $sourceDecodeFailures) PASS / $sourceDecodeFailures FAIL"
}

$tracks | Export-Csv -LiteralPath $TrackReport -NoTypeInformation -Encoding UTF8
$tracks |
    Select-Object Path,Directory,FileName,SourceDecodeStatus,SourceDecodeExitCode,SourceDecodeError |
    Export-Csv -LiteralPath $DecodeReport -NoTypeInformation -Encoding UTF8

$groups = @($tracks | Group-Object Directory | Sort-Object Name)

$albums = [System.Collections.Generic.List[object]]::new()
$plans = [System.Collections.Generic.List[object]]::new()

foreach ($g in $groups) {
    $ts = @($g.Group | Sort-Object Track,FileName)
    $artist = Get-DominantValue $ts.Artist
    $albumArtist = Get-DominantValue $ts.AlbumArtist
    $preferredArtist = if ($albumArtist) { $albumArtist } else { $artist }
    $art = Get-PreferredArtwork $g.Name
    $renameCount = 0

    foreach ($t in $ts) {
        $proposed = Get-ProposedName $t $preferredArtist
        if ($proposed -and $proposed -cne $t.FileName) { $renameCount++ }
        $plans.Add([pscustomobject]@{
            Directory=$g.Name; Current=$t.FileName; Proposed=$proposed; Ready=[bool]$proposed
        })
    }

    $artCount = @(Get-ChildItem -LiteralPath $g.Name -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLowerInvariant() -in $ArtworkExtensions }).Count

    $albumName = Get-DominantValue $ts.Album
    $albumDate = Get-DominantValue $ts.Date
    $albumGenre = Get-DominantValue $ts.Genre

    $missingTitle = @($ts | Where-Object { -not $_.Title }).Count
    $missingArtist = @($ts | Where-Object { -not $_.Artist }).Count
    $missingAlbum = @($ts | Where-Object { -not $_.Album }).Count
    $missingTrack = @($ts | Where-Object { $null -eq $_.Track }).Count
    $missingAlbumArtist = @($ts | Where-Object { -not $_.AlbumArtist }).Count
    $missingEmbedded = @($ts | Where-Object { -not $_.EmbeddedCover }).Count
    $probeErrors = @($ts | Where-Object { $_.ProbeError }).Count
    $sourceDecodeErrors = @($ts | Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" }).Count
    $suspiciousTitles = @($ts | Where-Object { $_.SuspiciousTitle }).Count

    # v0.2 does not auto-suggest genre from an artist-wide majority.
    # Genre can legitimately vary by release.
    $suggestedGenre = $null

    $metadataWarnings = [System.Collections.Generic.List[string]]::new()

    if ($missingTitle -gt 0)       { $metadataWarnings.Add("$missingTitle track(s) missing title") }
    if ($missingArtist -gt 0)      { $metadataWarnings.Add("$missingArtist track(s) missing artist") }
    if ($missingAlbum -gt 0)       { $metadataWarnings.Add("$missingAlbum track(s) missing album") }
    if ($missingTrack -gt 0)       { $metadataWarnings.Add("$missingTrack track(s) missing track number") }
    if ($missingAlbumArtist -gt 0) { $metadataWarnings.Add("$missingAlbumArtist track(s) missing album artist") }
    if ($probeErrors -gt 0)        { $metadataWarnings.Add("$probeErrors ffprobe error(s)") }
    if ($sourceDecodeErrors -gt 0) { $metadataWarnings.Add("$sourceDecodeErrors SOURCE DECODE ERROR track(s)") }
    if ($suspiciousTitles -gt 0)   { $metadataWarnings.Add("$suspiciousTitles possible ID3v1-truncated title(s)") }

    $status = "READY"
    if ($sourceDecodeErrors -gt 0) {
        $status = "SOURCE ERROR"
    }
    elseif ($probeErrors -gt 0 -or $missingTitle -gt 0 -or $missingArtist -gt 0 -or $missingAlbum -gt 0 -or $missingTrack -gt 0) {
        $status = "INCOMPLETE"
    }
    elseif ($metadataWarnings.Count -gt 0 -or $missingEmbedded -gt 0 -or -not $art) {
        $status = "NEEDS REVIEW"
    }

    $albums.Add([pscustomobject]@{
        Directory=$g.Name
        Status=$status
        Artist=$artist
        AlbumArtist=$albumArtist
        PreferredArtist=$preferredArtist
        Album=$albumName
        Date=$albumDate
        Genre=$albumGenre
        SuggestedGenre=$suggestedGenre
        Tracks=$ts.Count
        MissingTitle=$missingTitle
        MissingArtist=$missingArtist
        MissingAlbum=$missingAlbum
        MissingTrack=$missingTrack
        MissingAlbumArtist=$missingAlbumArtist
        MissingEmbeddedCover=$missingEmbedded
        ArtworkFiles=$artCount
        PreferredArtwork=if ($art) { $art.Name } else { $null }
        RenamesNeeded=$renameCount
        ProbeErrors=$probeErrors
        SourceDecodeErrors=$sourceDecodeErrors
        SuspiciousTitles=$suspiciousTitles
        MetadataWarnings=($metadataWarnings -join "; ")
    })
}

$albums | Export-Csv -LiteralPath $AlbumReport -NoTypeInformation -Encoding UTF8
$plans | Export-Csv -LiteralPath $PlanReport -NoTypeInformation -Encoding UTF8

if ($AuditOnly) {
    $auditReplacementRows = @(
        $tracks |
        Where-Object { $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" } |
        ForEach-Object {
            [pscustomobject]@{
                Status          = "Needed"
                SourcePath      = $_.Path
                AlbumDirectory  = $_.Directory
                Artist          = $_.Artist
                Album           = $_.Album
                Date            = $_.Date
                Disc            = $_.Disc
                Track           = $_.Track
                Title           = $_.Title
                FileName        = $_.FileName
                DecodeExitCode  = $_.SourceDecodeExitCode
                DecodeError     = $_.SourceDecodeError
            }
        }
    )

    $auditReplacementRows |
        Sort-Object AlbumDirectory, Disc, Track, FileName |
        Export-Csv -LiteralPath $ReplacementReport -NoTypeInformation -Encoding UTF8

    $readyCount = @($albums | Where-Object { $_.Status -eq "READY" }).Count
    $reviewCount = @($albums | Where-Object { $_.Status -eq "NEEDS REVIEW" }).Count
    $incompleteCount = @($albums | Where-Object { $_.Status -eq "INCOMPLETE" }).Count
    $sourceErrorCount = @($albums | Where-Object { $_.Status -eq "SOURCE ERROR" }).Count
    $probeErrorTrackCount = @($tracks | Where-Object { $_.ProbeError }).Count
    $suspiciousTitleCount = @($tracks | Where-Object { $_.SuspiciousTitle }).Count
    $missingEmbeddedCount = @($tracks | Where-Object { -not $_.EmbeddedCover }).Count

    Write-Host ""
    Write-Host ("=" * 72)
    Write-Host " AUDIT COMPLETE"
    Write-Host ("=" * 72)
    Write-Host "Audio files          : $($tracks.Count)"
    Write-Host "Album folders        : $($albums.Count)"
    Write-Host "READY                : $readyCount"
    Write-Host "NEEDS REVIEW         : $reviewCount"
    Write-Host "INCOMPLETE           : $incompleteCount"
    Write-Host "SOURCE ERROR         : $sourceErrorCount"
    Write-Host "ffprobe error tracks : $probeErrorTrackCount"
    if ($SkipSourceDecodeAudit) {
        Write-Host "Source decode errors : NOT CHECKED"
    }
    else {
        Write-Host "Source decode errors : $sourceDecodeFailures"
    }
    Write-Host "Suspicious titles    : $suspiciousTitleCount"
    Write-Host "Missing embedded art : $missingEmbeddedCount"

    $classification = Export-AuditFailureClassification -Tracks $tracks -OutputRoot $ReportRoot
    Show-AuditFailureClassification -Classification $classification

    Write-Host ""
    Write-Host "Reports:"
    Write-Host "  $TrackReport"
    Write-Host "  $AlbumReport"
    Write-Host "  $PlanReport"
    Write-Host "  $DecodeReport"
    Write-Host "  $ReplacementReport"
    Write-Host ""
    Write-Host "Persistent repair state was NOT modified."
    return
}

$state = @{ version=$ToolVersion; root=$Root; reviewed=@{}; plans=@{}; applied=@{}; replacements=@{}; generatedAt=(Get-Date).ToString("o") }

# Apply mode must always load the saved review/plan state.
# -Resume remains useful for returning to an interrupted interactive review.
$shouldLoadState = $Resume -or $ApplyApproved
if ($shouldLoadState -and (Test-Path -LiteralPath $StateFile)) {
    try {
        $old = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json -AsHashtable
        if ($old.root -eq $Root -and $old.reviewed) { $state.reviewed = $old.reviewed }
        if ($old.root -eq $Root -and $old.plans) { $state.plans = $old.plans }
        if ($old.root -eq $Root -and $old.ContainsKey("applied") -and $old.applied) { $state.applied = $old.applied }
        if ($old.root -eq $Root -and $old.ContainsKey("replacements") -and $old.replacements) { $state.replacements = $old.replacements }
    } catch {
        Write-Warning "Could not load previous state."
    }
}

Sync-ReplacementQueue -Tracks $tracks -State $state
Export-ReplacementQueue -State $state -Path $ReplacementReport
$state.generatedAt=(Get-Date).ToString("o")
$state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StateFile -Encoding UTF8

$replacementNeededCount = @(
    $state.replacements.Values |
    Where-Object { $_.Status -eq "Needed" }
).Count

if ($ApplyApproved) {
    if (-not $SkipSourceDecodeAudit -and $replacementNeededCount -gt 0) {
        Write-Host "Replacement queue   : $replacementNeededCount needed"
        Write-Host "Replacement report  : $ReplacementReport"
        Write-Host ""
    }
    Invoke-ApprovedApply -BackupOriginals:$BackupOriginals -Yes:$Yes
    return
}

Write-Host ""
Write-Host "Album folders discovered: $($albums.Count)"
Write-Host "Reports:"
Write-Host "  $TrackReport"
Write-Host "  $AlbumReport"
Write-Host "  $PlanReport"
Write-Host "  $DecodeReport"
Write-Host "  $ReplacementReport"
if (-not $SkipSourceDecodeAudit) {
    Write-Host "Replacement queue   : $replacementNeededCount needed"
}
Write-Host ""

for ($a=0; $a -lt $albums.Count; $a++) {
    $item = $albums[$a]

    if ($Resume -and $state.reviewed.ContainsKey($item.Directory)) { continue }

    while ($true) {
        Write-Host ""
        Write-Host ("=" * 72)
        Write-Host ("ALBUM {0}/{1}" -f ($a+1),$albums.Count)
        Write-Host ("=" * 72)
        Write-Host "Status              : $($item.Status)"
        Write-Host "Folder              : $($item.Directory)"
        Write-Host "Artist              : $($item.Artist)"
        Write-Host "Album Artist        : $($item.AlbumArtist)"
        Write-Host "Album               : $($item.Album)"
        Write-Host "Date                : $($item.Date)"
        Write-Host "Genre               : $($item.Genre)"
        if ($item.SuggestedGenre) {
            Write-Host "Suggested genre     : $($item.SuggestedGenre)"
        }
        Write-Host "Tracks              : $($item.Tracks)"
        Write-Host "Missing titles      : $($item.MissingTitle)"
        Write-Host "Missing artists     : $($item.MissingArtist)"
        Write-Host "Missing albums      : $($item.MissingAlbum)"
        Write-Host "Missing tracks      : $($item.MissingTrack)"
        Write-Host "Missing album artist: $($item.MissingAlbumArtist)"
        Write-Host "Missing embedded art: $($item.MissingEmbeddedCover)"
        Write-Host "Loose artwork       : $($item.ArtworkFiles)"
        Write-Host "Preferred artwork   : $($item.PreferredArtwork)"
        Write-Host "Rename candidates   : $($item.RenamesNeeded)"
        Write-Host "ffprobe errors      : $($item.ProbeErrors)"
        if ($SkipSourceDecodeAudit) {
            Write-Host "Source decode errors: NOT CHECKED"
        }
        else {
            Write-Host "Source decode errors: $($item.SourceDecodeErrors)"
            if ($item.SourceDecodeErrors -gt 0) {
                $badFiles = @(
                    $tracks |
                    Where-Object { $_.Directory -eq $item.Directory -and $_.SourceDecodeStatus -eq "SOURCE DECODE ERROR" } |
                    Sort-Object Disc, Track, FileName
                )
                foreach ($bad in $badFiles) {
                    Write-Host "  SOURCE DECODE ERROR -> $($bad.FileName)"
                }
            }
        }

        Write-Host "Suspicious titles   : $($item.SuspiciousTitles)"
        if ($item.SuspiciousTitles -gt 0) {
            $suspectFiles = @(
                $tracks |
                Where-Object { $_.Directory -eq $item.Directory -and $_.SuspiciousTitle } |
                Sort-Object Disc, Track, FileName
            )
            foreach ($suspect in $suspectFiles) {
                Write-Host "  POSSIBLE ID3v1 TRUNCATION -> $($suspect.FileName)"
                Write-Host "    Title: $($suspect.Title)"
            }
        }

        if ($item.MetadataWarnings) {
            Write-Host "Review notes        : $($item.MetadataWarnings)"
        }
        Write-Host ""
        $albumPlanState = Get-AlbumPlan $item

        Write-Host ""
        Write-Host "Planned:"
        Write-Host "  Artist       : $($albumPlanState.Artist)"
        Write-Host "  Album Artist : $($albumPlanState.AlbumArtist)"
        Write-Host "  Album        : $($albumPlanState.Album)"
        Write-Host "  Date         : $($albumPlanState.Date)"
        Write-Host "  Genre        : $($albumPlanState.Genre)"
        $coverText = if ($albumPlanState.Cover) { $albumPlanState.Cover } elseif ($albumPlanState.AllowMissingCover) { "[EXPLICITLY MISSING]" } else { "[UNRESOLVED]" }
        Write-Host "  Cover        : $coverText"
        Write-Host "  Cover Source : $($albumPlanState.CoverSource)"
        if ($albumPlanState.CoverReleaseId) {
            Write-Host "  Cover MBID   : $($albumPlanState.CoverReleaseId)"
        }
        Write-Host ""
        Write-Host "[P] Preview plan  [E] Edit metadata  [T] Track titles  [C] Choose cover"
        Write-Host "[R] Approve/reviewed  [S] Skip  [N] Next  [Q] Save/Quit"
        $choice = (Read-Host "Choice").Trim().ToUpperInvariant()

        if ($choice -eq "P") {
            Show-AlbumPlan $item $albumPlanState $tracks
            continue
        }

        if ($choice -eq "E") {
            Edit-AlbumPlan $item $albumPlanState
            continue
        }

        if ($choice -eq "T") {
            Edit-TrackTitles $item $albumPlanState $tracks
            continue
        }

        if ($choice -eq "C") {
            Choose-AlbumCover $item $albumPlanState $tracks
            continue
        }

        if ($choice -eq "R") {
            if (-not $SkipSourceDecodeAudit -and $item.SourceDecodeErrors -gt 0) {
                Write-Warning "Cannot approve this album: source audio decode errors are present."
                Write-Host "Use [S] Skip or replace the bad source file(s), then rescan."
                continue
            }

            $unreviewedSuspicious = @(
                $tracks |
                Where-Object {
                    $_.Directory -eq $item.Directory -and
                    $_.SuspiciousTitle -and
                    -not $albumPlanState.TitleOverrides.ContainsKey($_.FileName)
                }
            )

            if ($unreviewedSuspicious.Count -gt 0) {
                Write-Warning "$($unreviewedSuspicious.Count) possible ID3v1-truncated title(s) have not been reviewed."
                Write-Host "Use [T] Track titles to review/correct them before approval."
                continue
            }

            if (-not $albumPlanState.Cover -and -not $albumPlanState.AllowMissingCover) {
                Write-Warning "Cover artwork is unresolved."
                Write-Host "Use [C] Choose cover to resolve it, or explicitly mark it missing."
                continue
            }

            $state.reviewed[$item.Directory] = "Reviewed"
            break
        }
        if ($choice -eq "S") { $state.reviewed[$item.Directory] = "Skipped"; break }
        if ($choice -eq "N") { break }
        if ($choice -eq "Q") {
            $state.generatedAt=(Get-Date).ToString("o")
            $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StateFile -Encoding UTF8
            Write-Host "State saved: $StateFile"
            return
        }
    }

    $state.generatedAt=(Get-Date).ToString("o")
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

Write-Host ""
Write-Host "Review complete."
Write-Host "State: $StateFile"
