#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Root,
    [string]$Report = (Join-Path $HOME "Downloads\Music-Library-Repair\strict-decode-audit.csv")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$exts = @(".mp3",".flac",".m4a",".aac",".ogg",".opus",".wav",".wma",".aiff",".aif",".ape",".wv",".m4b")
$files = @(
    Get-ChildItem -LiteralPath $Root -Recurse -File |
    Where-Object { $_.Extension.ToLowerInvariant() -in $exts } |
    Sort-Object FullName
)

Write-Host "Strict audio decode audit"
Write-Host "Root : $Root"
Write-Host "Files: $($files.Count)"
Write-Host ""

$rows = [System.Collections.Generic.List[object]]::new()

for ($i = 0; $i -lt $files.Count; $i++) {
    $file = $files[$i]
    Write-Host ("[{0}/{1}] {2}" -f ($i + 1), $files.Count, $file.FullName)

    $output = @(
        & ffmpeg -hide_banner -v error -xerror -err_detect explode `
            -i $file.FullName -map 0:a:0 -f null - 2>&1
    )
    $exit = $LASTEXITCODE
    $status = if ($exit -eq 0 -and $output.Count -eq 0) { "PASS" } else { "FAIL" }

    $rows.Add([pscustomobject]@{
        File = $file.FullName
        Status = $status
        ExitCode = $exit
        DecoderOutput = ($output -join " | ")
    })
}

$dir = Split-Path -Parent $Report
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$rows | Export-Csv -LiteralPath $Report -NoTypeInformation -Encoding UTF8

$failed = @($rows | Where-Object Status -eq "FAIL")
Write-Host ""
Write-Host "PASS : $($rows.Count - $failed.Count)"
Write-Host "FAIL : $($failed.Count)"
Write-Host "Report: $Report"

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed files:"
    $failed | ForEach-Object { Write-Host "  $($_.File)" }
    exit 2
}
