#!/bin/bash
# ============================================================================
#  生成 Release 正文 —— 自动列出本次【实际编译进去】的插件清单
#
#  用法（必须在 openwrt/ 源码根目录执行）:
#    ./gen-release-notes.sh <输出 markdown 文件>
#
#  依赖的环境变量（由 workflow 注入）:
#    REPO_URL REPO_BRANCH DEVICE_NAME FILE_DATE KERNEL
#    HEAD_SHORT HEAD_DATE HEAD_MSG TRIGGER_REASON CHANGE_FILES
#
#  数据来源（按优先级）:
#    1) bin/targets/<target>/<subtarget>/*.manifest
#       编译产物清单，反映"最终刷进固件的包"，最权威
#    2) .config
#       配置意图。manifest 缺失时兜底（此时无法给出版本号）
#
#  ⚠ 为什么不用 .config：.config 只记录"你勾选了什么"，
#    依赖展开后实际编进去的包、以及自动带上的 target 默认包，
#    只有在 manifest 里才看得到。
# ============================================================================

set -e

OUT="${1:-release-notes.md}"

# ---------------------------------------------------------------------------
# 定位 manifest
# ---------------------------------------------------------------------------
MANIFEST=""
for f in bin/targets/*/*/*.manifest; do
    [ -f "$f" ] && MANIFEST="$f" && break
done

if [ -n "$MANIFEST" ]; then
    SRC="manifest"
    echo "[i] 数据源: $MANIFEST"
else
    SRC="config"
    echo "[!] 未找到 manifest，回退到 .config（版本号将显示为 -）"
fi

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 取某个包的版本（manifest 模式：取该行最后一个字段）
ver_of() {
    local p="$1"
    if [ "$SRC" = "manifest" ]; then
        local v
        v=$(awk -v p="$p" '$1==p {print $NF; exit}' "$MANIFEST" 2>/dev/null)
        echo "${v:--}"
    else
        echo "-"
    fi
}

# 判断某个包是否存在于本次构建
has_pkg() {
    local p="$1"
    if [ "$SRC" = "manifest" ]; then
        awk -v p="$p" '$1==p {found=1; exit} END{exit !found}' "$MANIFEST" 2>/dev/null
    else
        grep -q "^CONFIG_PACKAGE_${p}=y$" .config 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# 输出一个"按前缀匹配"的章节（如 luci-app- / luci-theme-）
# 返回 0 表示该章节有内容，1 表示无内容
# ---------------------------------------------------------------------------
emit_prefix_section() {
    local title="$1"
    local prefix="$2"
    local exclude="$3"   # 空格分隔的排除名单（这些包会在其它章节单独列出）
    local items=""

    if [ "$SRC" = "manifest" ]; then
        items=$(awk -v pre="$prefix" 'index($1, pre)==1 {print $1}' "$MANIFEST" | sort -u)
    else
        items=$(grep -oE "^CONFIG_PACKAGE_${prefix}[A-Za-z0-9._+-]+=y$" .config 2>/dev/null \
                | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort -u)
    fi

    # 去掉需要在其它章节单独展示的包，避免重复
    if [ -n "$exclude" ]; then
        items=$(printf '%s\n' "$items" | grep -v -w -E "$(printf '%s' "$exclude" | tr ' ' '|')" || true)
    fi

    [ -z "$items" ] && return 1

    local n=0
    n=$(printf '%s\n' "$items" | grep -c . || true)

    {
        echo ""
        echo "### ${title}（${n} 个）"
        echo ""
        echo "| 包名 | 版本 |"
        echo "| --- | --- |"
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            echo "| \`${p}\` | \`$(ver_of "$p")\` |"
        done <<< "$items"
    } >> "$OUT"

    return 0
}

# ---------------------------------------------------------------------------
# 输出一个"精确名单"的章节（只列出名单中确实存在的包）
# ---------------------------------------------------------------------------
emit_list_section() {
    local title="$1"
    shift
    local hits=""

    for p in "$@"; do
        if has_pkg "$p"; then
            hits="${hits}${p}"$'\n'
        fi
    done

    [ -z "$hits" ] && return 1

    local n=0
    n=$(printf '%s' "$hits" | grep -c . || true)

    {
        echo ""
        echo "### ${title}（${n} 个）"
        echo ""
        echo "| 包名 | 版本 |"
        echo "| --- | --- |"
        while IFS= read -r p; do
            [ -z "$p" ] && continue
            echo "| \`${p}\` | \`$(ver_of "$p")\` |"
        done <<< "$hits"
    } >> "$OUT"

    return 0
}

# ---------------------------------------------------------------------------
# 收集统计信息
# ---------------------------------------------------------------------------
KERNEL_VER="${KERNEL:-}"
if [ -z "$KERNEL_VER" ]; then
    KERNEL_VER=$(grep -m1 '^LINUX_VERSION-6\.6 =' include/kernel-6.6 2>/dev/null | awk '{print $3}')
fi
[ -z "$KERNEL_VER" ] && KERNEL_VER="未知"

SYSUP=""
for f in bin/targets/*/*/*"${DEVICE_NAME}"*sysupgrade*.bin; do
    [ -f "$f" ] && SYSUP="$f" && break
done

if [ -n "$SYSUP" ]; then
    FW_NAME=$(basename "$SYSUP")
    FW_SIZE=$(du -h "$SYSUP" 2>/dev/null | cut -f1)
    FW_SHA=$(sha256sum "$SYSUP" 2>/dev/null | awk '{print $1}')
else
    FW_NAME="immortalwrt-mediatek-filogic-${DEVICE_NAME}-squashfs-sysupgrade.bin"
    FW_SIZE="未知"
    FW_SHA=""
fi

# 总包数
if [ "$SRC" = "manifest" ]; then
    TOTAL_PKGS=$(grep -c . "$MANIFEST" 2>/dev/null || echo 0)
    LUCI_APPS=$(awk 'index($1,"luci-app-")==1' "$MANIFEST" 2>/dev/null | wc -l)
    THEMES=$(awk 'index($1,"luci-theme-")==1' "$MANIFEST" 2>/dev/null | wc -l)
else
    TOTAL_PKGS=$(grep -c '^CONFIG_PACKAGE_.*=y$' .config 2>/dev/null || echo 0)
    LUCI_APPS=$(grep -cE '^CONFIG_PACKAGE_luci-app-[A-Za-z0-9._+-]+=y$' .config 2>/dev/null || echo 0)
    THEMES=$(grep -cE '^CONFIG_PACKAGE_luci-theme-[A-Za-z0-9._+-]+=y$' .config 2>/dev/null || echo 0)
fi

# ---------------------------------------------------------------------------
# 生成正文
# ---------------------------------------------------------------------------
: > "$OUT"

cat >> "$OUT" <<EOF
## 固件信息

| 项目 | 值 |
| --- | --- |
| 源码 | [\`${REPO_URL}\`](${REPO_URL}) |
| 分支 | \`${REPO_BRANCH}\` |
| 上游提交 | \`${HEAD_SHORT}\` |
| 提交时间 | ${HEAD_DATE} |
| 提交说明 | ${HEAD_MSG} |
| 机型 | CMCC XR30 eMMC / RAX3000M eMMC 算力版 |
| 设备目标 | \`${DEVICE_NAME}\` |
| Linux 内核 | ${KERNEL_VER} |
| 构建时间 | ${FILE_DATE}（UTC+8） |
| 触发方式 | ${TRIGGER_REASON} |
| 收录包总数 | ${TOTAL_PKGS} |

## 刷入的文件

\`\`\`
${FW_NAME}
\`\`\`

- 文件大小：${FW_SIZE}
EOF

if [ -n "$FW_SHA" ]; then
    echo "- SHA256：\`${FW_SHA}\`" >> "$OUT"
fi

cat >> "$OUT" <<'EOF'

该文件为 **sysupgrade-tar** 格式，需配合 **hanwckf bl-mt798x 单分区 U-Boot（带 WebUI）** 刷入。
不能用主线 all-in-fit U-Boot 或官方 `.itb` 流程。

默认后台：`http://192.168.6.1` · 用户 `root` · **默认无密码**（首次登录后务必设置）。
默认主题：**Argon**。

EOF

# ---- 插件清单 ----
echo "## 本次编译的插件清单" >> "$OUT"

SECTION_COUNT=0

# MTK 专用组件会在下方单独成章，这里排除以免重复
# iStore 与 ddns-go 也会在下方单独成章，一并排除
emit_prefix_section "LuCI 应用" "luci-app-" \
    "luci-app-mtwifi-cfg luci-app-turboacc-mtk luci-app-eqos-mtk \
     luci-app-store luci-app-ddns-go" && SECTION_COUNT=$((SECTION_COUNT+1))
emit_prefix_section "LuCI 主题" "luci-theme-" && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "代理核心" \
    xray-core v2ray-core sing-box shadowsocks-rust shadowsocks-libev \
    shadowsocksr-libev trojan trojan-go trojan-plus hysteria naiveproxy \
    tuic-client tuic-server brook shadow-tls 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "分流 / DNS / 规则数据" \
    chinadns-ng dns2socks dns2tcp dnsproxy mosdns microsocks ipt2socks \
    tcping v2ray-geoip v2ray-geosite geoview dnsmasq-full \
    ddns-go luci-app-ddns-go ca-bundle 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

# iStore 应用商店：luci-app-store 及其依赖链
# 注：iStore 没有标准 po/ 目录，不存在 luci-i18n-store-zh-cn 包
emit_list_section "iStore 应用商店" \
    luci-app-store luci-lib-taskd luci-lib-xterm taskd \
    mount-utils script-utils 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "代理插件与 Obfs" \
    simple-obfs v2ray-plugin xray-plugin kcptun-client redsocks2 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "MTK 闭源驱动与硬件加速" \
    kmod-mt_wifi kmod-mediatek_hnat kmod-warp mtk-smp mtkhqos_util mii_mgr \
    wifi-dats datconf mt7981-wo-firmware kmod-mt7981-firmware \
    kmod-conninfra 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "MTK 专用 LuCI 组件" \
    luci-app-mtwifi-cfg luci-app-turboacc-mtk luci-app-eqos-mtk 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

emit_list_section "常用工具" \
    htop nano tcpdump ethtool iw iwinfo curl wget-ssl unzip jq \
    openssh-sftp-server openssl-util 2>/dev/null && SECTION_COUNT=$((SECTION_COUNT+1))

if [ "$SECTION_COUNT" -eq 0 ]; then
    echo "" >> "$OUT"
    echo "_（未检测到匹配的插件）_" >> "$OUT"
fi

# ---- 配置变更 ----
if [ -n "$CHANGE_FILES" ]; then
    {
        echo ""
        echo "## 触发本次构建的配置变更"
        echo ""
        echo '```'
        echo "$CHANGE_FILES"
        echo '```'
    } >> "$OUT"
fi

# ---- 固定提示 ----
cat >> "$OUT" <<'EOF'

---

## 注意事项

1. **硬件加速与代理插件冲突**：MT7981 的 HNAT/PPE 会让流量绕过 CPU 转发，
   导致 ssr-plus / passwall 的透明代理失效或异常。使用代理插件时，
   请在 `luci-app-turboacc-mtk` 中关闭「硬件流量分载」，仅保留 BBR + 全锥形 NAT。
2. **ssr-plus 与 passwall 建议二选一**：编译上可以共存，
   但同时运行会争抢 chinadns-ng 等本地端口。
3. **先确认是 eMMC 版**：机身标签 `CH **EC** CMIIT ID` 才是 eMMC（算力版）。
   只有 `CH CMIIT ID` 的是 NAND 版，刷此固件会变砖。

完整配置见 `full.config`，校验值见 `sha256sums`。
EOF

echo "[✓] Release 正文已生成: $OUT"
echo "    收录包 ${TOTAL_PKGS} 个 / LuCI 应用 ${LUCI_APPS} 个 / 主题 ${THEMES} 个"
