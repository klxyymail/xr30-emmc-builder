# XR30 eMMC · ImmortalWrt 24.10 (kernel 6.6)

在 GitHub Actions 上为 **CMCC XR30 eMMC**（RAX3000Z 增强版）编译
[padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)
`openwrt-24.10-6.6` 分支固件（MTK 闭源 WiFi + 硬件加速）。

默认后台 `192.168.6.1` · root · 无密码 · 主题 Argon。

## 刷机

⚠️ **先确认是 eMMC 版**：机身标签 `CH **EC** CMIIT ID` 才是。
只有 `CH CMIIT ID` 的是 NAND 版，刷此固件**会变砖**。

产物是 sysupgrade-tar 格式，需 **hanwckf bl-mt798x 单分区 U-Boot（带 WebUI）** 刷入，
不能用主线 all-in-fit U-Boot。

```
immortalwrt-mediatek-filogic-cmcc_rax3000m-emmc-mtk-squashfs-sysupgrade.bin   ← 刷这个
immortalwrt-mediatek-filogic-cmcc_rax3000m-emmc-mtk-initramfs-kernel.bin      ← 救砖用
```
