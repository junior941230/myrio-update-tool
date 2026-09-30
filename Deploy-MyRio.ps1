[CmdletBinding()]
param(
    [string]$IPAddress,
    [string]$Version,
    [switch]$Deploy,
    [switch]$Trace
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Security
$releases = Join-Path $PSScriptRoot 'fiimware'
$local = Join-Path $PSScriptRoot '.local'
$ipFile = Join-Path $local 'last-ip.txt'
$passwordFile = Join-Path $local 'password.dpapi'

if ($Deploy -and $Trace) { throw 'Choose either deployment or trace.' }

if (-not $Deploy -and -not $Trace) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'myRIO 本地部署'
    $form.ClientSize = New-Object Drawing.Size(600, 445)
    $form.StartPosition = 'CenterScreen'

    $ipLabel = New-Object Windows.Forms.Label
    $ipLabel.Text = 'myRIO IP'
    $ipLabel.SetBounds(20, 23, 90, 25)
    $form.Controls.Add($ipLabel)
    $ipBox = New-Object Windows.Forms.TextBox
    $ipBox.Text = '172.22.11.2'
    if (Test-Path -LiteralPath $ipFile) { $ipBox.Text = (Get-Content -LiteralPath $ipFile -Raw -Encoding UTF8).Trim() }
    $ipBox.SetBounds(115, 20, 465, 25)
    $form.Controls.Add($ipBox)

    $passwordLabel = New-Object Windows.Forms.Label
    $passwordLabel.Text = 'SSH 密碼'
    $passwordLabel.SetBounds(20, 68, 90, 25)
    $form.Controls.Add($passwordLabel)
    $passwordBox = New-Object Windows.Forms.TextBox
    $passwordBox.UseSystemPasswordChar = $true
    $passwordBox.SetBounds(115, 65, 465, 25)
    if (Test-Path -LiteralPath $passwordFile) {
        try {
            $encrypted = [Convert]::FromBase64String((Get-Content -LiteralPath $passwordFile -Raw).Trim())
            $plain = [Security.Cryptography.ProtectedData]::Unprotect($encrypted, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
            try { $passwordBox.Text = [Text.Encoding]::UTF8.GetString($plain) }
            finally { [Array]::Clear($plain, 0, $plain.Length) }
        } catch {
            [Windows.Forms.MessageBox]::Show('已儲存的密碼無法解密，請重新輸入。', 'myRIO') | Out-Null
        }
    }
    $form.Controls.Add($passwordBox)

    $saveSettings = {
        $address = $null
        if (-not [Net.IPAddress]::TryParse($ipBox.Text.Trim(), [ref]$address) -or
            $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw '請輸入有效的 IPv4 位址。' }
        if (-not (Test-Path -LiteralPath $local)) { New-Item -ItemType Directory -Path $local | Out-Null }
        if ($passwordBox.Text.Length -gt 0) {
            $bytes = [Text.Encoding]::UTF8.GetBytes($passwordBox.Text)
            try {
                $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
                [IO.File]::WriteAllText($passwordFile, [Convert]::ToBase64String($encrypted), [Text.Encoding]::ASCII)
            } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
        } elseif (Test-Path -LiteralPath $passwordFile) {
            Remove-Item -LiteralPath $passwordFile
        }
        [IO.File]::WriteAllText($ipFile, $address.ToString(), [Text.Encoding]::UTF8)
    }
    $form.Add_FormClosing({
        try { & $saveSettings }
        catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '設定未儲存') | Out-Null }
    })

    $versionLabel = New-Object Windows.Forms.Label
    $versionLabel.Text = '部署版本'
    $versionLabel.SetBounds(20, 108, 90, 25)
    $form.Controls.Add($versionLabel)
    $versionBox = New-Object Windows.Forms.ComboBox
    $versionBox.DropDownStyle = 'DropDownList'
    $versionBox.SetBounds(115, 105, 300, 25)
    $form.Controls.Add($versionBox)

    $pullButton = New-Object Windows.Forms.Button
    $pullButton.Text = 'Git pull／重新整理'
    $pullButton.SetBounds(425, 104, 155, 27)
    $form.Controls.Add($pullButton)

    $notesLabel = New-Object Windows.Forms.Label
    $notesLabel.Text = '版本更新內容'
    $notesLabel.SetBounds(20, 148, 150, 25)
    $form.Controls.Add($notesLabel)
    $notesBox = New-Object Windows.Forms.TextBox
    $notesBox.Multiline = $true
    $notesBox.ReadOnly = $true
    $notesBox.ScrollBars = 'Vertical'
    $notesBox.SetBounds(20, 175, 560, 200)
    $form.Controls.Add($notesBox)

    $showNotes = {
        if ($versionBox.SelectedItem) {
            $path = Join-Path (Join-Path $releases ([string]$versionBox.SelectedItem)) 'RELEASE_NOTES.md'
            $notesBox.Text = if (Test-Path -LiteralPath $path -PathType Leaf) {
                Get-Content -LiteralPath $path -Raw -Encoding UTF8
            } else {
                '此版本尚無更新說明。'
            }
        } else {
            $notesBox.Clear()
        }
    }
    $versionBox.Add_SelectedIndexChanged($showNotes)
    $refreshVersions = {
        $selected = [string]$versionBox.SelectedItem
        $versionBox.Items.Clear()
        Get-ChildItem -LiteralPath $releases -Directory | Sort-Object Name -Descending | ForEach-Object { [void]$versionBox.Items.Add($_.Name) }
        if ($versionBox.Items.Contains($selected)) {
            $versionBox.SelectedItem = $selected
        } elseif ($versionBox.Items.Count -gt 0) {
            $versionBox.SelectedIndex = 0
        }
        & $showNotes
    }
    & $refreshVersions

    $traceButton = New-Object Windows.Forms.Button
    $traceButton.Text = '查看裝置 Trace'
    $traceButton.SetBounds(20, 395, 270, 32)
    $form.Controls.Add($traceButton)

    $button = New-Object Windows.Forms.Button
    $button.Text = '部署（開啟終端機）'
    $button.SetBounds(310, 395, 270, 32)
    $form.Controls.Add($button)
    $pullButton.Add_Click({
        $pullButton.Enabled = $false
        $form.UseWaitCursor = $true
        try {
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $output = (& git -C $PSScriptRoot pull --ff-only 2>&1 | Out-String).Trim()
                $exitCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $savedPreference
            }
            if ($exitCode -ne 0) { throw "Git pull 失敗：`n$output" }
            & $refreshVersions
            [Windows.Forms.MessageBox]::Show($output, 'Git pull 完成') | Out-Null
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Git pull 失敗') | Out-Null
        } finally {
            $form.UseWaitCursor = $false
            $pullButton.Enabled = $true
        }
    })
    $button.Add_Click({
        try {
            $address = [Net.IPAddress]::Parse($ipBox.Text.Trim())
            if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw '請輸入 IPv4 位址。' }
            if ([string]::IsNullOrEmpty($passwordBox.Text)) { throw '請輸入 SSH 密碼。' }
            if (-not $versionBox.SelectedItem) { throw '請選擇版本。' }
            & $saveSettings
            $selected = [string]$versionBox.SelectedItem
            $arguments = '-NoExit -ExecutionPolicy Bypass -File "{0}" -Deploy -IPAddress {1} -Version {2}' -f $PSCommandPath, $address, $selected
            Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, '無法部署') | Out-Null
        }
    })
    $traceButton.Add_Click({
        try {
            $address = [Net.IPAddress]::Parse($ipBox.Text.Trim())
            if ($address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw '請輸入 IPv4 位址。' }
            if ([string]::IsNullOrEmpty($passwordBox.Text)) { throw '請輸入 SSH 密碼。' }
            & $saveSettings
            $arguments = '-NoExit -ExecutionPolicy Bypass -File "{0}" -Trace -IPAddress {1}' -f $PSCommandPath, $address
            Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, '無法查看 Trace') | Out-Null
        }
    })
    [void]$form.ShowDialog()
    return
}

$address = $null
if (-not [Net.IPAddress]::TryParse($IPAddress, [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Invalid IPv4 address.' }
if ($Deploy) {
    if ($Version -notmatch '^\d{8}T\d{6}Z$') { throw 'Invalid version.' }
    $release = Join-Path $releases $Version
    if (-not (Test-Path -LiteralPath $release -PathType Container)) { throw "Version not found: $Version" }
}
if (-not (Test-Path -LiteralPath $passwordFile -PathType Leaf)) { throw 'Save the SSH password in the UI first.' }
if (-not (Test-Path -LiteralPath $ipFile -PathType Leaf) -or
    (Get-Content -LiteralPath $ipFile -Raw -Encoding UTF8).Trim() -ne $address.ToString()) {
    throw 'The selected IP differs from the saved credential. Save it in the UI first.'
}

$askpass = Join-Path $local 'AskPass.exe'
$askpassSource = Join-Path $PSScriptRoot 'AskPass.cs'
if (-not (Test-Path -LiteralPath $askpass) -or
    (Get-Item -LiteralPath $askpassSource).LastWriteTimeUtc -gt (Get-Item -LiteralPath $askpass).LastWriteTimeUtc) {
    if (Test-Path -LiteralPath $askpass) { Remove-Item -LiteralPath $askpass }
    Add-Type -Path $askpassSource -OutputAssembly $askpass -OutputType ConsoleApplication -ReferencedAssemblies 'System.Security.dll'
}
$env:SSH_ASKPASS = $askpass
$env:SSH_ASKPASS_REQUIRE = 'force'
$env:DISPLAY = 'myrio'
$env:MYRIO_PASSWORD_FILE = $passwordFile

$remote = "admin@$address"
if ($Trace) {
    $traceDir = Join-Path $local 'traces'
    if (-not (Test-Path -LiteralPath $traceDir)) { New-Item -ItemType Directory -Path $traceDir | Out-Null }
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $traceFile = Join-Path $traceDir ('myrio_nav_trace_{0}_{1}_{2}.csv' -f $address, $stamp, [guid]::NewGuid().ToString('N').Substring(0, 6))
    & scp.exe -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 "${remote}:/tmp/myrio_nav_trace.csv" $traceFile
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $traceFile) { Remove-Item -LiteralPath $traceFile }
        throw 'Trace download failed. The trace is written after navigation ends or is cancelled.'
    }
    $rows = @(Get-Content -LiteralPath $traceFile -Encoding UTF8 | Where-Object { $_ -and -not $_.StartsWith('#') } | ConvertFrom-Csv)
    if ($rows.Count -eq 0) { throw "Trace has no samples: $traceFile" }
    Write-Host "Saved $($rows.Count) trace samples to $traceFile"
    $rows | Out-GridView -Wait -Title "myRIO Trace $address ($stamp)"
    return
}

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

$archive = Join-Path $release 'myrio-runtime.tar.gz'
$remoteArchive = '/tmp/myrio-runtime-{0}.tar.gz' -f [guid]::NewGuid().ToString('N')
Write-Host "Uploading $Version to $remote ..."
& scp.exe -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 $archive "${remote}:$remoteArchive"
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
& ssh.exe -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1 $remote $remoteScript
if ($LASTEXITCODE -ne 0) { throw 'Target test or installation failed.' }
