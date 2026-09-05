#!/bin/bash
# ============================================================================
#  高级定制脚本（在配置应用之后、编译之前执行）
#  工作目录：openwrt/ 源码根目录
#
#  ⚠ 重要：本脚本只在【完整编译】时执行，组装模式（ImageBuilder）不执行。
#    但这些改动会固化进 ImageBuilder（内核/DTS），
#    所以后续组装出的固件依然带有这些改动 —— 前提是生成 IB 那次跑过本脚本。
#
#  简单的定制（IP / 主机名 / 主题）在 workflow 的 env 段改，不用写在这里。
#
#  ⚠ 以下两项均已启用。每项都做了存在性检查：
#     条件不满足 → 打印警告并跳过，绝不会中断构建（脚本开头有 set -e）。
# ============================================================================

set -e
echo "===== diy.sh 开始 ====="

DTS="target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc-mtk.dts"

# --------------------------------------------------------------
# 一、替换 WiFi EEPROM（提升发射功率）
#
#   背景：原厂 2.4G 23dBm / 5G 22dBm，替换 eeprom 后可到 25dBm / 24dBm
#
#   ⚠ 需要你自备 eeprom 文件，放到仓库的 eeprom/ 目录：
#        eeprom/mt7981_eeprom.bin
#     来源通常是同芯片其它机型（如 H3C NX30 Pro）提取的校准数据。
#
#   ⚠ 刷错 eeprom 会导致 WiFi 无法启动或功率异常，请先备份原厂分区。
#     没有提供文件时本段会安全跳过，不影响构建。
# --------------------------------------------------------------
echo "--- [1/2] WiFi EEPROM ---"
EEPROM_SRC="$GITHUB_WORKSPACE/eeprom/mt7981_eeprom.bin"
EEPROM_DST="feeds/mtk/mtk_wifi/files/lib/firmware/mt7981_eeprom_mt7976_dbdc.bin"

if [ ! -f "$EEPROM_SRC" ]; then
    echo "  [跳过] 未提供 $EEPROM_SRC"
    echo "         如需替换，把 eeprom 文件放到仓库 eeprom/ 目录后重新完整编译"
elif [ ! -d "$(dirname "$EEPROM_DST")" ]; then
    echo "  [跳过] 目标目录不存在: $(dirname "$EEPROM_DST")"
else
    cp -f "$EEPROM_SRC" "$EEPROM_DST"
    echo "  [已替换] $(basename "$EEPROM_DST")"
fi

# --------------------------------------------------------------
# 二、修正 LED 定义（XR30 eMMC 专用）
#
#   背景：当前设备目标是 cmcc_rax3000m-emmc-mtk，
#         DTS 里定义了三个 LED（绿 GPIO9 / 蓝 GPIO12 / 红 GPIO35），
#         但 XR30 eMMC 硬件上【只有一个白色灯，接 GPIO 34，低电平点亮】。
#
#   不改的后果：系统注册三个不存在的灯，GPIO 9/12/35 在 XR30 上可能
#               未连接或连着其它器件，导致灯不亮甚至误触发。
#
#   本段做三件事：
#     1. 主灯 led-0 → GPIO 34 + 白色（对应 XR30 唯一的物理灯）
#     2. 禁用 led-1 / led-2（硬件上不存在）
#     3. aliases 中的 led-boot/failsafe 原本指向 red_led，
#        现改指主灯，否则禁用红灯后启动/故障指示会失效
#
#   ⚠ 如果你的机器实际是 RAX3000M 而非 XR30，或灯的表现不对，
#     把 LED_FIX 改成 0 关闭本段。
#
#   注：eMMC 频率项已移除 —— 源码该 DTS 本就是 52MHz（52000000），
#       原示例的 26000000→52000000 替换属空操作。
#       若需降频（部分机器 52MHz 不稳），自行在下方加：
#         sed -i 's/max-frequency = <52000000>/max-frequency = <26000000>/' "$DTS"
# --------------------------------------------------------------
echo "--- [2/2] LED 定义 ---"
LED_FIX=1

if [ "$LED_FIX" != "1" ]; then
    echo "  [已关闭] LED_FIX=0"
elif [ ! -f "$DTS" ]; then
    echo "  [跳过] 未找到 DTS: $DTS"
else
    # 1) 主灯改 GPIO34 + 白色
    sed -i '/green_led: led-0 {/,/};/{
        s/&pio 9/\&pio 34/
        s/LED_COLOR_ID_GREEN/LED_COLOR_ID_WHITE/
    }' "$DTS"

    # 2) 禁用硬件上不存在的两个灯
    #    先判断是否已处理过，避免重复执行时插入多行 status
    if grep -q 'status = "disabled"' "$DTS"; then
        echo "  (检测到已禁用过，跳过重复插入)"
    else
        perl -0pi -e 's/(led-1 \{[^}]*?gpios = <[^>]*>;)/$1\n\t\t\tstatus = "disabled";/s' "$DTS"
        perl -0pi -e 's/(red_led: led-2 \{[^}]*?gpios = <[^>]*>;)/$1\n\t\t\tstatus = "disabled";/s' "$DTS"
    fi

    # 3) 启动/故障指示改指主灯
    sed -i 's/led-boot = &red_led;/led-boot = \&green_led;/' "$DTS"
    sed -i 's/led-failsafe = &red_led;/led-failsafe = \&green_led;/' "$DTS"

    echo "  [已完成] 主灯=GPIO34(白)，led-1/led-2 已禁用，启动指示改指主灯"
fi

echo "===== diy.sh 结束 ====="
