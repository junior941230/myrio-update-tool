[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ChatGPT\myrio-codex'),
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = $PSScriptRoot
$releases = Join-Path $repo 'fiimware'
$dist = Join-Path $SourceRoot 'dist\myrio-armv7'
$files = @(
    'libydlidar_lv.so', 'libydlidar_lv.so.1.2.0',
    'libmyrio_nav.so', 'libmyrio_nav.so.1.0.0',
    'myrio-runtime.tar.gz', 'SHA256SUMS'
)

if (-not $SkipBuild) {
    & (Join-Path $SourceRoot 'scripts\Build-MyRio.ps1')
    if (-not $?) { throw 'Cross compilation failed.' }
}

foreach ($name in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $dist $name) -PathType Leaf)) {
        throw "Missing build output: $name"
    }
}
foreach ($line in Get-Content -LiteralPath (Join-Path $dist 'SHA256SUMS')) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Invalid SHA256SUMS line: $line" }
    $name = $Matches[2]
    if ($name -notin $files) { throw "Unexpected checksum entry: $name" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dist $name)).Hash
    if ($actual -ne $Matches[1]) { throw "Checksum mismatch: $name" }
}

$old = Get-ChildItem -LiteralPath $releases -Directory | Sort-Object Name -Descending | Select-Object -First 1
if ($old) {
    $unchanged = $true
    foreach ($name in @('libydlidar_lv.so.1.2.0', 'libmyrio_nav.so.1.0.0')) {
        $previous = Join-Path $old.FullName $name
        if (-not (Test-Path -LiteralPath $previous) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $previous).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dist $name)).Hash) {
            $unchanged = $false
        }
    }
    if ($unchanged) {
        Write-Host "Libraries unchanged; current version is $($old.Name)."
        return
    }
}

$version = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$target = Join-Path $releases $version
if (Test-Path -LiteralPath $target) { throw "Version already exists: $version" }
New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $dist $name) -Destination (Join-Path $target $name) -ErrorAction Stop
}

& git -C $repo add -- "fiimware/$version"
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git -C $repo commit -m "myRIO firmware $version"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
& git -C $repo push -u origin main
if ($LASTEXITCODE -ne 0) { throw "GitHub push failed; version $version remains committed locally. Retry with: git push -u origin main" }
Write-Host "Published $version to GitHub."
