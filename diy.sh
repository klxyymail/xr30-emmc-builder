#!/bin/bash
# ============================================================================
#  自定义脚本 —— 在插件配置载入之后、编译之前执行
#  工作目录为 openwrt/ 源码根目录
#
#  ⚠ 本脚本在 plugins.config 之后执行，因此这里的配置优先级最高，可覆盖前者。
#    代理类插件（ssr-plus / passwall / argon）请统一在 plugins.config 里管理，
#    本脚本只放"与机型/个人偏好相关"的定制。
# ============================================================================

set -e

echo "===== diy.sh 开始执行 ====="

# --------------------------------------------------------------
# 1. 设置 Argon 为默认主题  【默认生效】
#
#    原理：修改 luci-base 内置的默认配置文件。该文件会作为 /etc/config/luci
#    打进固件，因此：
#      · 全新刷机 / 重置配置  → 默认 Argon ✅
#      · 保留配置升级         → 保持你当前选择的主题（不会被强行改回）✅
#
#    这里刻意【不用】uci-defaults 脚本 —— 那种方式会在每次启动时覆盖
#    /etc/config/luci，导致你手动切换的主题在系统升级后被重置。
# --------------------------------------------------------------
echo "--- 设置 Argon 为默认主题 ---"

LUCI_CFG=""
for cand in \
    "feeds/luci/modules/luci-base/root/etc/config/luci" \
    "package/feeds/luci/luci-base/root/etc/config/luci"; do
    [ -f "$cand" ] && LUCI_CFG="$cand" && break
done

# 上面路径都不中就用 find 兜底（不同版本布局可能有差异）
if [ -z "$LUCI_CFG" ]; then
    LUCI_CFG=$(find feeds package -type f -path '*luci-base*' -name 'luci' \
               -path '*etc/config*' 2>/dev/null | head -1)
fi

if [ -n "$LUCI_CFG" ] && [ -f "$LUCI_CFG" ]; then
    echo "  配置文件: $LUCI_CFG"
    echo "  修改前: $(grep -m1 'mediaurlbase' "$LUCI_CFG" || echo '（无 mediaurlbase 行）')"

    if grep -q 'mediaurlbase' "$LUCI_CFG"; then
        # 无论原先是什么主题，一律替换为 argon
        sed -i "s|option mediaurlbase .*|option mediaurlbase '/luci-static/argon'|" "$LUCI_CFG"
    else
        # 没有该配置项则追加到 config core 'main' 段落
        sed -i "/config core 'main'/a\\\toption mediaurlbase '/luci-static/argon'" "$LUCI_CFG"
    fi

    echo "  修改后: $(grep -m1 'mediaurlbase' "$LUCI_CFG")"
else
    echo "  [警告] 未找到 luci 配置文件，默认主题未修改，将保持 bootstrap"
fi

# 确认 argon 主题确实被编入（避免默认主题指向一个不存在的目录）
if ! grep -q '^CONFIG_PACKAGE_luci-theme-argon=y' .config 2>/dev/null; then
    echo "  [警告] .config 中未启用 luci-theme-argon，正在补上"
    echo "CONFIG_PACKAGE_luci-theme-argon=y" >> .config
    make defconfig
else
    echo "  [OK] luci-theme-argon 已在 .config 中启用"
fi


# --------------------------------------------------------------
# 2. 修改默认 LAN IP（237 仓库默认 192.168.6.1）
#    XR30/RAX3000M 原厂后台多为 192.168.10.1，改成同网段便于过渡
# --------------------------------------------------------------
# sed -i 's/192\.168\.6\.1/192.168.10.1/g' package/base-files/files/bin/config_generate


# --------------------------------------------------------------
# 3. 修改主机名 / 时区
# --------------------------------------------------------------
# sed -i "s/hostname='ImmortalWrt'/hostname='XR30'/" package/base-files/files/bin/config_generate
# sed -i "s/timezone='UTC'/timezone='CST-8'/" package/base-files/files/bin/config_generate
# sed -i "s/zonename='UTC'/zonename='Asia\/Shanghai'/" package/base-files/files/bin/config_generate


# --------------------------------------------------------------
# 4. 追加额外软件包（plugins.config 之外的补充）
#    修改后需要重新 make defconfig 才能生效
# --------------------------------------------------------------
# cat >> .config <<'EOF'
# CONFIG_PACKAGE_luci-app-upnp=y
# CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y
# CONFIG_PACKAGE_luci-app-wolplus=y
# CONFIG_PACKAGE_luci-app-autoreboot=y
# CONFIG_PACKAGE_luci-app-ttyd=y
# CONFIG_PACKAGE_luci-app-samba4=y
# CONFIG_PACKAGE_htop=y
# CONFIG_PACKAGE_nano=y
# CONFIG_PACKAGE_tcpdump=y
# EOF
# make defconfig


# --------------------------------------------------------------
# 5. MT7981 硬件加速相关（237 仓库的 mt7981 defconfig 多数已内置）
#    luci-app-mtwifi-cfg    闭源 WiFi 驱动配置页
#    luci-app-turboacc-mtk  硬件加速开关（HNAT / PPE / WED）
#    luci-app-eqos-mtk      硬件 QoS（MTK 适配版）
#
#    ⚠ 重要：硬件加速（HNAT/PPE）与 ssr-plus / passwall 的透明代理存在冲突。
#      开启硬件加速时，流量绕过 CPU 转发，代理插件的透明代理会失效或异常。
#      使用代理插件时建议在 turboacc 里关闭 "软件/硬件流量分载"，
#      或在 luci-app-turboacc-mtk 中仅保留 BBR + 全锥形 NAT。
# --------------------------------------------------------------

echo "===== diy.sh 执行完毕 ====="
