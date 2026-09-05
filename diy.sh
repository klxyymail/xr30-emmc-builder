#!/bin/bash
# ============================================================================
#  可选的高级定制脚本 —— 在配置文件应用之后、编译之前执行
#  工作目录为 openwrt/ 源码根目录
#
#  ⚠ 简单的定制【不要写在这里】，直接在机型配置文件的 ## [custom] 段改：
#       lan_ip / hostname / timezone / zonename / theme
#    改配置文件即可，无需碰脚本，也不用改 workflow。
#
#  本文件只放【配置文件表达不了】的复杂 shell 逻辑。
#  不需要就删除，workflow 会自动跳过。
# ============================================================================

set -e

echo "===== diy.sh 开始执行 ====="

# --------------------------------------------------------------
# 示例 1：替换 WiFi EEPROM 以提升发射功率（可选，有风险）
#   lgs2007m 的 RAX3000M eMMC 项目使用 H3C NX30 Pro 提取的 eeprom
#   原厂 2.4G 23dBm / 5G 22dBm → 替换后 25dBm / 24dBm
#   ⚠ eMMC 设备读取 eeprom 的方式与 NAND 不同，操作前先备份原厂分区
# --------------------------------------------------------------
 EEPROM_DIR="feeds/mtk/mtk_wifi/files/lib/firmware"
 if [ -d "$EEPROM_DIR" ]; then
   cp "$GITHUB_WORKSPACE/eeprom/mt7981_eeprom.bin" \
      "$EEPROM_DIR/mt7981_eeprom_mt7976_dbdc.bin"
   echo "已替换 eeprom"
 fi


# --------------------------------------------------------------
# 示例 2：调整 eMMC 闪存频率
#   XR30-eMMC 可跑 52MHz（RAX3000M-eMMC 为 26MHz），速率翻倍
#   ⚠ 部分机器体质不佳，52MHz 可能出现 I/O 报错甚至无法启动
# --------------------------------------------------------------
 sed -i 's/max-frequency = <26000000>/max-frequency = <52000000>/' \
     target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-mtk.dts


# --------------------------------------------------------------
# 示例 3：追加额外软件包（能放配置文件的尽量放配置文件）
# --------------------------------------------------------------
# cat >> .config <<'EOF'
# CONFIG_PACKAGE_luci-app-upnp=y
# CONFIG_PACKAGE_luci-app-samba4=y
# EOF
# make defconfig


# --------------------------------------------------------------
# 示例 4：修正 XR30 的 LED 定义
#   用 cmcc_rax3000m-emmc-mtk 编译时，LED 沿用 RAX3000M 的定义。
#   已知差异：XR30-eMMC 比 RAX3000M-eMMC 少一个 LED，
#             XR30 是白色灯接 GPIO 34（低电平点亮）
#   若你发现 LED 不亮或颜色不对，在这里按实际硬件调整 DTS
# --------------------------------------------------------------
 DTS="target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-mtk.dts"
 [ -f "$DTS" ] && sed -i 's/gpio = <[0-9]* GPIO_ACTIVE_HIGH>/gpio = <34 GPIO_ACTIVE_LOW>/' "$DTS"


echo "===== diy.sh 执行完毕（当前未启用任何定制项）====="
