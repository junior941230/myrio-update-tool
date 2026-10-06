回復倒車功能加入前的版本。

來源：myrio-codex commit 7e987e3086aae35e91ec64918ba10d7d97afa767（0828，2026-08-28）。發布時的 src、include、tests 與 CMakeLists.txt 已確認與該版本一致。

本版回復到新增退回／倒車復原功能前的導航行為；同批加入的定位修正與新診斷欄位也一併回復。

建置：NI Linux Host SDK 6.0（GCC 6.3.0），Cortex-A9／VFPv3／softfp，ELF32 ARM。libydlidar_lv 為 1.2.0，libmyrio_nav 為 1.0.0。封包包含對應版本的六項測試、probe 程式及 C ABI headers。

驗證：回復後的 WSL Release 本機建置成功，CTest 六項測試全部通過；ARM 交叉編譯成功，發布檔案的 SHA-256 與封包內容已驗證。尚未部署至 myRIO，亦尚未在實機執行 ARM 測試或驗證移動。
