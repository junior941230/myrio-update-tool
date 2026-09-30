[CmdletBinding()]
param(
    [string]$IPAddress,
    [string]$Version,
    [switch]$Deploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$releases = Join-Path $PSScriptRoot 'fiimware'

if (-not $Deploy) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'myRIO 本地部署'
    $form.Size = New-Object Drawing.Size(430, 205)
    $form.StartPosition = 'CenterScreen'

    $ipLabel = New-Object Windows.Forms.Label
    $ipLabel.Text = 'myRIO IP'
    $ipLabel.SetBounds(20, 23, 90, 25)
    $form.Controls.Add($ipLabel)
    $ipBox = New-Object Windows.Forms.TextBox
    $ipBox.Text = '172.22.11.2'
    $ipBox.SetBounds(115, 20, 275, 25)
    $form.Controls.Add($ipBox)

    $versionLabel = New-Object Windows.Forms.Label
    $versionLabel.Text = '部署版本'
    $versionLabel.SetBounds(20, 68, 90, 25)
    $form.Controls.Add($versionLabel)
    $versionBox = New-Object Windows.Forms.ComboBox
    $versionBox.DropDownStyle = 'DropDownList'
    $versionBox.SetBounds(115, 65, 275, 25)
    Get-ChildItem -LiteralPath $releases -Directory | Sort-Object Name -Descending | ForEach-Object { [void]$versionBox.Items.Add($_.Name) }
    if ($versionBox.Items.Count -gt 0) { $versionBox.SelectedIndex = 0 }
    $form.Controls.Add($versionBox)

    $button = New-Object Windows.Forms.Button
    $button.Text = '部署（開啟終端機）'
    $button.SetBounds(115, 112, 275, 32)
    $form.Controls.Add($button)
    $button.Add_Click({
        try {
            $address = [Net.IPAddress]::Parse($ipBox.Text.Trim())
            if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw '請輸入 IPv4 位址。' }
            if (-not $versionBox.SelectedItem) { throw '請選擇版本。' }
            $selected = [string]$versionBox.SelectedItem
            $arguments = '-NoExit -ExecutionPolicy Bypass -File "{0}" -Deploy -IPAddress {1} -Version {2}' -f $PSCommandPath, $address, $selected
            Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, '無法部署') | Out-Null
        }
    })
    [void]$form.ShowDialog()
    return
}

$address = $null
if (-not [Net.IPAddress]::TryParse($IPAddress, [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Invalid IPv4 address.' }
if ($Version -notmatch '^\d{8}T\d{6}Z$') { throw 'Invalid version.' }
$release = Join-Path $releases $Version
if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "Version not found: $Version" }

$expected = @('libydlidar_lv.so', 'libydlidar_lv.so.1.2.0', 'libmyrio_nav.so', 'libmyrio_nav.so.1.0.0', 'myrio-runtime.tar.gz')
$seen = @{}
foreach ($line in Get-Content -LiteralPath (Join-Path $release 'SHA256SUMS')) {
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw "Invalid SHA256SUMS line: $line" }
    $name = $Matches[2]
    if ($name -notin $expected -or $seen.ContainsKey($name)) { throw "Unexpected checksum entry: $name" }
    $seen[$name] = $true
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $release $name)).Hash
    if ($actual -ne $Matches[1]) { throw "Checksum mismatch: $name" }
}
foreach ($name in $expected) {
    if (-not $seen.ContainsKey($name)) { throw "Missing checksum entry: $name" }
}

$remote = "admin@$address"
$archive = Join-Path $release 'myrio-runtime.tar.gz'
$remoteArchive = '/tmp/myrio-runtime-{0}.tar.gz' -f [guid]::NewGuid().ToString('N')
Write-Host "Uploading $Version to $remote ..."
& scp.exe -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $archive "${remote}:$remoteArchive"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed.' }

$remoteScript = @'
set -eu
runtime=$(mktemp -d /tmp/myrio-runtime.XXXXXX)
tar -xzf __ARCHIVE__ -C "$runtime"
rm -f __ARCHIVE__
cd "$runtime"
ln -s libydlidar_lv.so.1.2.0 libydlidar_lv.so.1
ln -s libmyrio_nav.so.1.0.0 libmyrio_nav.so.1
export LD_LIBRARY_PATH="$runtime"
for test in ydlidar_lv_smoke myrio_nav_smoke myrio_nav_core_test myrio_nav_replay_test myrio_nav_trace_test myrio_nav_performance_test; do
    "./$test"
done
mkdir -p /usr/local/lib /usr/local/include /usr/local/bin
cp libydlidar_lv.so.1.2.0 libmyrio_nav.so.1.0.0 /usr/local/lib/
chmod 0755 /usr/local/lib/libydlidar_lv.so.1.2.0 /usr/local/lib/libmyrio_nav.so.1.0.0
ln -sfn libydlidar_lv.so.1.2.0 /usr/local/lib/libydlidar_lv.so.1
ln -sfn libydlidar_lv.so.1 /usr/local/lib/libydlidar_lv.so
ln -sfn libmyrio_nav.so.1.0.0 /usr/local/lib/libmyrio_nav.so.1
ln -sfn libmyrio_nav.so.1 /usr/local/lib/libmyrio_nav.so
cp ydlidar_lv.h myrio_nav.h /usr/local/include/
cp ydlidar_lv_probe ydlidar_lv_restart_probe myrio_nav_smoke /usr/local/bin/
chmod 0755 /usr/local/bin/ydlidar_lv_probe /usr/local/bin/ydlidar_lv_restart_probe /usr/local/bin/myrio_nav_smoke
LD_LIBRARY_PATH=/usr/local/lib /usr/local/bin/myrio_nav_smoke
echo "Deployment complete. Test artifacts retained at $runtime"
'@
$remoteScript = $remoteScript.Replace('__ARCHIVE__', $remoteArchive)
$remoteScript = $remoteScript -replace "`r`n", "`n"
& ssh.exe -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new $remote $remoteScript
if ($LASTEXITCODE -ne 0) { throw 'Target test or installation failed.' }
