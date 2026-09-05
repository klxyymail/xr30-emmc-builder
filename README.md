# XR30 eMMC · ImmortalWrt 24.10 (kernel 6.6) 在线构建

用 GitHub Actions 为 **CMCC XR30 eMMC**（RAX3000Z 增强版）编译
[padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)
的 `openwrt-24.10-6.6` 分支固件（MTK 闭源 WiFi 驱动 + 硬件加速）。

内置插件：**luci-app-ssr-plus** + **PassWall** + **Argon 主题** + **iStore 应用商店** + **ddns-go**
（Argon 已设为默认主题）。

## 核心特性

| 特性 | 说明 |
| --- | --- |
| **Release 正文自动生成** | 从编译产物 manifest 提取**实际编入**的插件清单，含版本号 |
| **配置变更自动重编** | 改 `plugins.config` / `diy.sh` 等文件推送后自动触发构建 |
| **固件永久保留** | Release 附件永久存储，无任何自动清理逻辑 |
| **配置自动归档** | 每次 Release 附带 `full.config` 与当次 `plugins.config` / `diy.sh` |

---

## 文件结构

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/build-xr30-emmc.yml` | 构建主流程 |
| `plugins.config` | **插件配置**：ssr-plus / passwall / argon 及其依赖 |
| `diy.sh` | 个人定制（默认主题、IP、主机名、额外插件），优先级高于 plugins.config |
| `gen-release-notes.sh` | **自动生成 Release 正文**（提取实际编入的插件清单） |
| `README.md` | 本说明 |

---

## 刷机前必读

**先确认你的机器是 eMMC 版，不是 NAND 版。** XR30 存在两种硬件，刷错变砖：

| 版本 | 机身标签特征 | 对应设备名 |
| --- | --- | --- |
| eMMC 版（算力版 / RAX3000Z 增强版） | `CH **EC** CMIIT ID: xxxx` | 本配置适用 |
| NAND 版 | `CH CMIIT ID: xxxx` | **勿用**，会变砖 |

设备目标为 **`cmcc_rax3000m-emmc-mtk`**（XR30 eMMC 与 RAX3000M eMMC 算力版硬件相同，
上游仓库没有 `cmcc_xr30-emmc` 这个目标，只有 `cmcc_xr30-nand` / `cmcc_xr30-stock`）。

产出为 **sysupgrade-tar 格式** `.bin`，需搭配 **hanwckf bl-mt798x 单分区 U-Boot（带 WebUI）** 刷入，
不能用主线 all-in-fit U-Boot 或官方 `.itb` 流程。

---

## 一、Release 正文自动生成

每次构建后自动从 `bin/targets/mediatek/filogic/*.manifest` 提取插件清单，生成带版本号的表格。

**为什么用 manifest 而不是 .config**：`.config` 只记录"你勾选了什么"，
而依赖展开后实际编进去的包、以及 target 自动带上的默认包，只有在 manifest 里才看得到。
manifest 反映的是最终刷进固件的真实内容。

生成的正文包含：

- 固件信息表（源码提交、内核版本、触发方式、收录包总数）
- 刷入文件 + 大小 + SHA256
- **插件清单**（分章节：LuCI 应用 / 主题 / 代理核心 / 分流 DNS / MTK 驱动 / 常用工具）
- push 触发时额外列出本次改了哪些文件
- 固定注意事项

manifest 缺失时自动回退到 `.config`（版本号显示为 `-`），不会中断构建。

## 二、配置变更自动触发

推送以下文件的变更即自动重新编译：

```
plugins.config          diy.sh
gen-release-notes.sh    .github/workflows/build-xr30-emmc.yml
```

> workflow 用 `GITHUB_TOKEN` 回写 `.upstream-commit` **不会**触发新的 workflow
> —— GitHub 有意这样设计以防止递归，所以不会自激。

## 三、固件永久保留

| 存储位置 | 保留时长 |
| --- | --- |
| **Release 附件** | **永久** |
| Artifacts | 90 天（GitHub 上限，仅作短期镜像） |

- Release 是固件的永久存储位置，GitHub 不会自动删除 Release 及其附件
- **本仓库刻意不配置任何清理旧 Release 的流程**，请勿另行添加
  `delete-older-releases` 类动作
- 每次 Release 附带的 `full.config` / `plugins.config` / `diy.sh` 可用于复现该固件

> ⚠ **容量提醒**：单个 Release 约 35–40 MB（sysupgrade + initramfs + 配置）。
> 每周自动构建一年约 2 GB，会触碰 GitHub 的仓库体积建议上限（1 GB）。
> 若不需要每周追新，可注释掉 workflow 里的 `schedule` 仅保留手动触发；
> 或定期把旧 Release 附件转存到网盘后再删除。

## 四、Argon 默认主题

`diy.sh` 会修改 `luci-base` 内置的默认配置文件，将 `mediaurlbase` 指向 `/luci-static/argon`。

**为什么不用 uci-defaults**：uci-defaults 脚本在每次系统启动时执行，
会覆盖 `/etc/config/luci`，导致你手动切换的主题在系统升级后被重置。
改编译期默认值则只在**全新刷机 / 重置配置**时生效，保留配置升级不会动你的选择。

| 场景 | 结果 |
| --- | --- |
| 全新刷机 | 默认 Argon |
| 恢复出厂 / 重置配置 | 默认 Argon |
| 保留配置升级 | **保持你当前选择的主题** |

脚本含边界处理：配置文件中无 `mediaurlbase` 行时自动追加；
`.config` 未启用 argon 时自动补上并重新 `make defconfig`；
配置文件完全找不到时仅告警，不中断构建。

---

## 插件核查结论（2026-09-05 实测）

### 源码来源与是否需加源

| 插件 | 版本 | 来源 | 是否需加源 |
| --- | --- | --- | --- |
| `luci-app-passwall` | 25.12.16 | `immortalwrt/luci` @openwrt-24.10 | ❌ 官方已内置 |
| `luci-theme-argon` | 2.4.3 (20250722) | `immortalwrt/luci` @openwrt-24.10 | ❌ 官方已内置 |
| `luci-app-argon-config` | — | `immortalwrt/luci` @openwrt-24.10 | ❌ 官方已内置 |
| `luci-app-ddns-go` | — | `immortalwrt/luci` @openwrt-24.10 | ❌ 官方已内置 |
| `ddns-go` | 6.11.2 | `immortalwrt/packages` net/ | ❌ 官方已内置 |
| `luci-app-ssr-plus` | 196 | `fw876/helloworld` @**dev** | ✅ **需加 helloworld 源** |
| `luci-app-store` | 0.2.1-r1 | `linkease/istore` @main | ✅ **需加 istore 源** |

> `fw876/helloworld` 默认分支是 **dev**（不是 master）。dev 版本 196，
> 且声明 `default Nftables_Transparent_Proxy if PACKAGE_firewall4`，原生适配 fw4。
>
> `linkease/istore` 的包藏在 **`luci/` 子目录**下，不在仓库顶层。
> `include/scan.mk` 用 `find -L $(SCAN_DIR) -mindepth 1 -name Makefile` 递归扫描、
> 无 `maxdepth` 限制，因此仍能被正确发现。

### 为什么必须加 helloworld

以下包在 `immortalwrt/packages` @openwrt-24.10 中**不存在**，只有 helloworld 提供：

- `luci-app-ssr-plus`
- `shadowsocksr-libev`（ssr-plus 硬依赖其 `ssr-check`）
- `shadowsocks-libev`
- `mosdns` / `dnsproxy` / `dns2socks-rust` / `gn`

### 为什么必须加 istore

`luci-app-store` 及其依赖链 `luci-lib-taskd` / `luci-lib-xterm` / `taskd`
官方源均**不存在**，只有 `linkease/istore` 提供。

完整依赖链（已逐条验证，全部可满足）：

```
luci-app-store
  ├─ curl / tar / libuci-lua          base 自带
  ├─ mount-utils                      util-linux 子包
  └─ luci-lib-taskd (>=1.0.19)  ── istore 源
       ├─ luci-lib-xterm        ── istore 源
       └─ taskd (>=1.0.3)       ── istore 源（纯 shell，基于 procd，非 Go）
            └─ procd / script-utils / coreutils / coreutils-stty
```

**`taskd` 是纯 shell 脚本，不是 Go 程序**，不增加编译负担。

### ⚠ 两个"看似缺失实则存在"的子包（易踩坑）

`script-utils` 与 `mount-utils` 在源码树里**没有独立目录**——
按 `package/utils/script-utils` 这样的路径去找会 404，在
`immortalwrt/packages` 的 326 个包里也搜不到。

它们实际是 **`package/utils/util-linux` 内部定义的子包**：

```makefile
define Package/script-utils    # → /usr/bin/script, scriptreplay
define Package/mount-utils     # → /usr/bin/mount, umount ...
```

这与上一轮 `v2ray-geoip` / `v2ray-geosite` 的情形**完全同构**
（它们也是 `net/v2ray-geodata` 的内部子包）。依赖能被自动解析，无需干预。

配置里已显式写出二者，便于 `make defconfig` 校验依赖完整性。

### ⚠ `luci-i18n-store-zh-cn` 不存在

iStore **没有标准的 `po/` 目录**，因此 LuCI 的 i18n 包不会自动生成。
它的中文由 istore-ui 前端自带（仓库 `translations/zh-cn/app.po`）。

**切勿在配置里写 `CONFIG_PACKAGE_luci-i18n-store-zh-cn=y`**，会被静默丢弃。

`luci-app-ddns-go` 则有正常 po 文件，`luci-i18n-ddns-go-zh-cn` 可用。

### 依赖核查：全部可满足

**PassWall 必需依赖**：coreutils / curl / chinadns-ng / dns2socks / ip-full /
libuci-lua / lua / luci-compat / luci-lib-jsonc / microsocks / resolveip /
tcping / unzip / ipt2socks / kmod-nft-socket / kmod-nft-tproxy / kmod-nft-nat
→ 全部确认存在。其中 `luci-compat` 位于 `luci/modules/luci-compat`（不在 `libs/` 下，易误判）。

**一个易踩的坑**：PassWall 的 `INCLUDE_V2ray_Geodata` 依赖 `v2ray-geoip` 和 `v2ray-geosite`，
在 `immortalwrt/packages` 里**没有这两个独立目录**（直接找会 404）。
它们实际是在 `net/v2ray-geodata` 包的 Makefile 内部定义的子包。
**不需要**为此添加 `xiaorouji/openwrt-passwall-packages` 源。

**ssr-plus 必需依赖**：coreutils / dns2tcp / **dnsmasq-full** / jq / ip-full / lua /
lua-neturl / libuci-lua / microsocks / tcping / resolveip /
shadowsocksr-libev-ssr-check / curl / **nping**（由 `packages/net/nmap` 提供）

### feeds 优先级设计

`scripts/feeds` 的 `lookup_package()` 按 `feeds.conf` 书写顺序取第一个命中的源，
**靠前的优先级更高**，先安装者不被后者覆盖。

因此 workflow 把两个第三方源都**追加到最后**：

```
src-git packages   ...    ← 官方源，优先级高
src-git luci       ...
src-git routing    ...
src-git telephony  ...
src-git helloworld ...;dev     ← 优先级低，仅作补充
src-git istore     ...;main    ← 优先级低，仅作补充
```

官方源优先，避免第三方源覆盖与 24.10 匹配的官方包版本。

两个第三方源**无任何同名包**（helloworld 27 个 vs istore 4 个），
因此彼此的先后顺序不影响结果。

### 兼容性：均适配 fw4 (nftables)

| 项 | 结论 |
| --- | --- |
| PassWall 25.12.16 | 显式依赖 `kmod-nft-socket/tproxy/nat`，nftables 原生 |
| ssr-plus 196 | `default Nftables_Transparent_Proxy if PACKAGE_firewall4` |
| Argon 2.4.3 | 纯 LuCI 主题，与内核无关 |

配置中已显式指定 ssr-plus 走 **Nftables_Transparent_Proxy** 并关闭 iptables 模式。

---

## ⚠ 两个运行时注意事项

**1. ssr-plus 的 "NONE" 陷阱（已处理）**

官方 defconfig 预置三行 `INCLUDE_NONE_*=y`，含义是"不装任何核心"。
**不显式关掉，编出来的 ssr-plus 会是个空壳。**
`plugins.config` 已先把它们置为 `is not set`，再开启 Xray / SSR 内核。

**2. 硬件加速与代理插件冲突**

MT7981 的 HNAT/PPE 会让流量绕过 CPU 转发，导致透明代理失效。
使用 ssr-plus / passwall 时，请在 `luci-app-turboacc-mtk` 中关闭「硬件流量分载」，
仅保留 BBR + 全锥形 NAT。

另外 ssr-plus 与 passwall **建议只启用其中一个**（二者会争抢 chinadns-ng 等本地端口）。

---

## 使用方法

1. 把本仓库文件推到你自己的 GitHub 仓库。
2. **Settings → Actions → General → Workflow permissions** 选 **Read and write permissions**。
3. **Actions** → 选 `Build ImmortalWrt 24.10 (k6.6) for CMCC XR30 eMMC` → **Run workflow**。
4. 等待编译（**首次约 3–5 小时**；有 ccache 后约 1–2 小时）。
5. 在 **Releases** 下载固件，正文即为本次编译的完整插件清单。

> ⏱ **超时风险**：GitHub 免费账号单 job 上限 6 小时，已设 `timeout-minutes: 350`。
>
> 当前 Go 程序有 `xray-core` 与 `ddns-go`（共享 `golang/host` 工具链，
> 首次构建工具链约 15–30 分钟，之后每个 Go 包约 3–10 分钟）。
> `plugins.config` 默认关闭了 SingBox / shadowsocks-rust / Hysteria / NaiveProxy 等
> 更重量级的 Go/Rust 组件。如需开启，建议分批编译。

## 触发方式对照

| 触发方式 | 行为 |
| --- | --- |
| 手动 `workflow_dispatch` | 无条件编译 |
| 推送 `push`（配置变更） | 无条件编译 |
| 定时 `schedule`（每周二约 10:00 CST） | 比对上游 HEAD，有变化才编译 |

已构建的提交号记录在 `.upstream-commit`，**仅在构建成功后更新**；
失败则不写，下个周期自动重试同一提交。想强制重跑：删除该文件，或手动触发。

> GitHub 会在仓库连续 60 天无活动后**静默禁用定时任务**。若定时没跑，
> 去 Actions 页面手动触发一次即可恢复。

## 刷入的文件

```
immortalwrt-mediatek-filogic-cmcc_rax3000m-emmc-mtk-squashfs-sysupgrade.bin   ← 主固件
immortalwrt-mediatek-filogic-cmcc_rax3000m-emmc-mtk-initramfs-kernel.bin      ← 内存版，救砖用
```

默认后台：`http://192.168.6.1` · 用户 `root` · **默认无密码**（首次登录后务必设置）· 默认主题 **Argon**。

## 自定义

- **改插件**：编辑 `plugins.config`（代理类插件统一在此管理，推送后自动重编）
- **改 IP / 主机名 / 默认主题**：编辑 `diy.sh`（优先级高于 plugins.config）
- **改机型 / 分支 / 定时**：编辑 workflow 顶部 `env` 与 `schedule`
