# myRIO update tool

`fiimware/<版本>/` 保存每次更新的 ARM `.so`、測試／安裝封包、SHA-256 清單和 `RELEASE_NOTES.md` 更新說明。版本用 UTC 建置時間命名；已有版本永不覆蓋。兩個 `.so` 內容未變時不會建立重複版本。

## 編譯並發布到 GitHub

在 Windows PowerShell 執行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Publish-MyRio.ps1 -ReleaseNotes "本版修正了..."
```

預設從 `Documents\ChatGPT\myrio-codex` 呼叫 WSL／NI SDK 交叉編譯，成功後驗證 SHA-256、建立新版本、Git commit 並 push 到 `origin/main`。每個新版本須提供 `-ReleaseNotes`；未提供時會提示輸入。可用 `-SourceRoot` 指定其他原始碼位置。若已單獨完成編譯，可加 `-SkipBuild`。push 失敗時版本和 commit 會保留在本機，網路恢復後重新執行發布腳本即可重試推送。

## 本地部署

雙擊 `Deploy-MyRio.cmd`，或在 PowerShell 執行：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Deploy-MyRio.ps1
```

輸入 myRIO IPv4、SSH 密碼並選版本，介面會顯示該版本更新說明。上次的 IP 和密碼會保存在本機 `.local/`；密碼使用 Windows DPAPI 加密，只有同一台電腦的同一個 Windows 使用者可解密，且 `.local/` 不會加入 Git。按「Git pull／重新整理」會以 fast-forward 方式從 GitHub 更新本機版本清單。按部署後，內建 OpenSSH 會透過本機 askpass 程式讀取加密密碼，不需在終端機再次輸入。腳本上傳選定封包，在 myRIO 跑六項 ARM 測試；全部通過才安裝到 `/usr/local` 並做安裝後 smoke test。裝置需能以 `admin` SSH 連線。

按「查看裝置 Trace」會從 myRIO 的 `/tmp/myrio_nav_trace.csv` 下載最新診斷資料，保存在本機 `.local/traces/`，並以可搜尋的表格開啟。trace 由導航程式在到點、故障或取消後寫出；若 myRIO 尚未產生此檔案，下載會顯示錯誤。
