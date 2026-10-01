[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ChatGPT\myrio-codex'),
    [string]$ReleaseNotes,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = $PSScriptRoot
$releases = Join-Path $repo 'fiimware'
$dist = Join-Path $SourceRoot 'dist\myrio-armv7'
# Versioned library names change between source versions, so the release is
# whatever SHA256SUMS lists, limited to these name patterns.
$allowedName = '^(lib(ydlidar_lv|myrio_nav)\.so(\.\d+)*|myrio-runtime\.tar\.gz)$'
$required = @('libydlidar_lv.so', 'libmyrio_nav.so', 'myrio-runtime.tar.gz')

if (-not $SkipBuild) {
    & (Join-Path $SourceRoot 'scripts\Build-MyRio.ps1') -SkipPublish
    if (-not $?) { throw 'Cross compilation failed.' }
}

$sums = Join-Path $dist 'SHA256SUMS'
if (-not (Test-Path -LiteralPath $sums -PathType Leaf)) { throw 'Missing build output: SHA256SUMS' }
$seen = @{}
foreach ($line in Get-Content -LiteralPath $sums) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Invalid SHA256SUMS line: $line" }
    $expectedHash = $Matches[1]
    $name = $Matches[2]
    # -notmatch overwrites $Matches, so the hash is captured above.
    if ($name -notmatch $allowedName -or $seen.ContainsKey($name)) { throw "Unexpected checksum entry: $name" }
    $path = Join-Path $dist $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing build output: $name" }
    $seen[$name] = $true
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    if ($actual -ne $expectedHash) { throw "Checksum mismatch: $name" }
}
foreach ($name in $required) {
    if (-not $seen.ContainsKey($name)) { throw "Missing checksum entry: $name" }
}
$files = @($seen.Keys | Sort-Object) + 'SHA256SUMS'

$old = Get-ChildItem -LiteralPath $releases -Directory | Sort-Object Name -Descending | Select-Object -First 1
if ($old) {
    $unchanged = $true
    # Unversioned copies exist in every release layout.
    foreach ($name in @('libydlidar_lv.so', 'libmyrio_nav.so')) {
        $previous = Join-Path $old.FullName $name
        if (-not (Test-Path -LiteralPath $previous) -or
            (Get-FileHash -Algorithm SHA256 -LiteralPath $previous).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dist $name)).Hash) {
            $unchanged = $false
        }
    }
    if ($unchanged) {
        Write-Host "Libraries unchanged; current version is $($old.Name)."
        & git -C $repo push -u origin main
        if ($LASTEXITCODE -ne 0) { throw 'GitHub push failed; retry when the network is available.' }
        return
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $sourceName = Split-Path -Leaf $SourceRoot
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot '.git'))) {
        $ReleaseNotes = "Automatic cross build from $sourceName (not a git repository)"
    } else {
        $commit = (& git -C $SourceRoot rev-parse --short HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit for release notes.' }
        $subject = (& git -C $SourceRoot log -1 --format=%s).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read source commit subject.' }
        $changes = @(& git -C $SourceRoot status --short --untracked-files=normal -- src include CMakeLists.txt)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source changes for release notes.' }
        $ReleaseNotes = "Automatic cross build from $sourceName commit $commit`n$subject"
        if ($changes.Count -gt 0) {
            $ReleaseNotes += "`nUncommitted source changes at build time:`n" + ($changes -join "`n")
        }
    }
}

$version = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$target = Join-Path $releases $version
if (Test-Path -LiteralPath $target) { throw "Version already exists: $version" }
New-Item -ItemType Directory -Path $target -ErrorAction Stop | Out-Null
foreach ($name in $files) {
    Copy-Item -LiteralPath (Join-Path $dist $name) -Destination (Join-Path $target $name) -ErrorAction Stop
}
Set-Content -LiteralPath (Join-Path $target 'RELEASE_NOTES.md') -Encoding UTF8 -Value $ReleaseNotes

& git -C $repo add -- "fiimware/$version"
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git -C $repo commit -m "myRIO firmware $version"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
& git -C $repo push -u origin main
if ($LASTEXITCODE -ne 0) { throw "GitHub push failed; version $version remains committed locally. Retry with: git push -u origin main" }
Write-Host "Published $version to GitHub."
