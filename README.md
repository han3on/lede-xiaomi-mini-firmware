# lede-xiaomi-mini-firmware

小米路由器 mini（R1CM）的 OpenWrt 固件，用 GitHub Actions 云端编译，源码来自 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede)（Lean 的 LEDE）。

这台机器目前的实际用途是**家里的副路由**：负责科学上网 + USB 外挂硬盘当轻量 NAS。所以固件是按这个场景裁剪的——不带多余插件，把宝贵的 16MB flash 留给真正在用的功能。

![Build OpenWrt](https://github.com/han3on/lede-xiaomi-mini-firmware/actions/workflows/build-openwrt.yml/badge.svg)

## 硬件规格

| 项目 | 参数 |
|---|---|
| 型号 | 小米路由器 mini（R1CM） |
| SoC | MediaTek MT7620A，MIPS 24KEc @ 580MHz |
| 内存 | 128MB DDR2 |
| 闪存 | 16MB SPI NOR |
| 无线 | 2.4GHz 802.11n 2×2，最高 300Mbps（**无 5GHz**） |
| 有线 | 1× WAN + 2× LAN，均为百兆 |
| 接口 | USB 2.0 ×1、microSD ×1 |
| 原厂系统 | 基于 OpenWrt 的 MiWiFi |

两个先天限制要有心理准备：百兆网口决定了 USB 硬盘共享最快也就 **11MB/s 左右**；只有 2.4G 单频，跑满 300Mbps 需要信号干净且终端支持 2×2。

## 固件里有什么

基于 Lean LEDE，内核随源码走。ramips 目标目前的 `KERNEL_PATCHVER` 是 **5.10**（历史存档配置写的是 5.4，`make defconfig` 会自动纠正到源码实际支持的版本）。

**LuCI 应用**

| 插件 | 用途 |
|---|---|
| `luci-app-ssr-plus` | 科学上网（SS/SSR/V2Ray/Trojan 客户端） |
| `luci-app-ksmbd` + `ksmbd-server` | USB 硬盘 SMB 共享（内核态实现） |
| `luci-app-aria2` + `ariang` | 离线下载 + 网页前端 |
| `luci-app-vsftpd` | FTP 访问硬盘 |
| `luci-app-ddns` | 动态域名 |
| `luci-app-turboacc` | 软件加速（flow offload 等） |
| `luci-app-filetransfer` | LuCI 内直接上传/下载文件 |
| `luci-app-arpbind` | IP/MAC 绑定 |
| `luci-app-autoreboot` | 定时重启 |
| `luci-theme-bootstrap` | 默认主题 |

**存储相关依赖**：`kmod-usb-storage`、`kmod-usb-storage-extras`、`kmod-fs-ext4`、`kmod-fs-vfat`、`kmod-fs-exfat`、`kmod-fs-ntfs3`、`block-mount`、`automount`、`kmod-fs-cifsd`（ksmbd 的内核模块）

**注意 SMB 实现已更换**：Lean 的软件源里 `samba36-server` 已经不存在了，旧的 `luci-app-samba` 依赖它，会直接变成不可选。因此改用内核态的 `ksmbd`——体积只有几百 KB（samba4 要好几 MB，16MB flash 塞不下），MT7620 这种弱 CPU 上吞吐也更好。界面位置仍是 **网络存储 → 网络共享**，新固件上原来 samba 的配置不会保留，需要重新添加共享目录。

**相比 Lean 默认配置删掉的**：`luci-app-accesscontrol`、`luci-app-nlbwmon`、`luci-app-upnp`、`luci-app-vlmcsd`、`luci-app-wol` —— 都是些边角功能，省下来的空间留给上面这些。

**默认参数**：LAN `192.168.1.1`，无 root 密码（首次登录请立刻设置），`dnsmasq-full`，`dropbear`，时间区 `Asia/Shanghai`。

装完固件约 **11.2MB**，设备在源码里的 `IMAGE_SIZE` 是 `15872k`（约 15.5MB），刷进去后 overlay 还能剩 4MB 左右。

## 仓库结构

```
.
├── .config                     # 默认编译配置（不含阿里云盘）
├── withaliyun.config           # 在 .config 基础上增加 aliyundrive-webdav
├── feeds.conf.default          # Lean 官方源 + helloworld 源
├── diy-part1.sh                # feeds update 之前执行的自定义脚本（当前为空壳）
├── diy-part2.sh                # defconfig 之前修正 .config，适配当前源码
└── .github/workflows
    ├── build-openwrt.yml           # 默认配置，编译并发布 Release
    ├── build-openwrt-withaliyun.yml # 阿里云盘版本
    └── update-checker.yml          # 源码更新检查（手动触发）
```

`diy-part1.sh` 目前是空壳（模板内容全部注释掉），想加第三方软件源在这里写。

`diy-part2.sh` 会在 `make defconfig` 之前修正 `.config` 里两处与当前源码不符的地方：SMB 实现从 samba36 换成 ksmbd、语言包 `zh-cn` 改名为 `zh_Hans`。脚本末尾有自检，改不成功会直接中止编译，不会产出一个缺功能的固件。

## 自己编译

不需要本地装交叉编译环境，全部在 GitHub 上跑，单次约 2–3 小时。

1. Fork 或直接使用本仓库
2. 进 **Actions** → 左侧选 `Build OpenWrt` → **Run workflow**
3. 需要调试可以在 `ssh` 输入框填 `true`，构建过程中会给出 SSH 连接命令（仅仓库所有者可用）
4. 想固定源码版本，在 `source_ref` 填分支/标签/提交号，留空则用 `master`
5. 编译完成后到 **Releases** 下载 `openwrt-ramips-mt7620-xiaomi_miwifi-mini-squashfs-sysupgrade.bin`

两个工作流的区别只有一个：`Build OpenWrt With Aliyun` 使用 `withaliyun.config`，额外编入阿里云盘 WebDAV（配 `luci-app-aliyundrive-webdav`），代价是固件变大、跑起来更吃内存，128MB 内存的机器上不建议常开。

编译完成后会自动：生成带 sha256 校验值的 Release → 只保留最近 3 个版本，更早的连同 tag 一起删除。

### 关于 `.config` 的版本漂移

仓库里的 `.config` 是 2022 年存档下来的一份完整配置，直接喂给当前 LEDE master 会有“引用了已不存在的包”的情况。工作流里专门加了 `Align configuration with current source` 一步：

1. 先 `make defconfig` 对齐，把被剔除的配置项打印到日志
2. **校验目标设备**是否仍是 `xiaomi_miwifi-mini`，被改掉就直接失败
3. **校验核心插件** `luci-app-ssr-plus`、`luci-app-ksmbd` 是否还在，缺一个就直接失败

这两道校验的意义是：让构建在几分钟内失败，而不是跑满 2–3 小时后产出一个“能刷但功能不全”的固件。Summary 里能看到实际设备、源码提交、内核版本，以及对齐前后启用的包数量。

如果某些老插件在新源码里确实没了，需要重新在 `make menuconfig` 里选一遍（可以用 SSH 调试模式进容器生成），或者把 `source_ref` 指到更早的提交上先跑通。

## 刷机

> ⚠️ 刷机有变砖风险。开始前请确认：手上有原厂固件备份、路由器没在刷写中途断电、你接受后果自负。

### 前提：拿到 SSH

小米 mini 出厂固件不允许直接刷第三方固件，常规路径是先刷官方**开发版**固件，再用小米的「开放 SSH 工具」开启 SSH。开启后 root 密码由 SN 计算得出，登录地址就是路由器本身。

已经刷了 OpenWrt / Breed 的机器可以跳过这一步。

### 方式一：命令行（推荐）

```bash
# 1. 把固件传到路由器
scp openwrt-ramips-mt7620-xiaomi_miwifi-mini-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/

# 2. 登录后校验（可选，但建议）
ssh root@192.168.1.1
sha256sum /tmp/openwrt-*sysupgrade.bin

# 3. 刷写，-n 表示不保留配置
sysupgrade -n /tmp/openwrt-ramips-mt7620-xiaomi_miwifi-mini-squashfs-sysupgrade.bin
```

原厂固件没有 `sysupgrade` 时，改用 `mtd`：

```bash
mtd -r write /tmp/openwrt-ramips-mt7620-xiaomi_miwifi-mini-squashfs-sysupgrade.bin firmware
```

### 方式二：Web 界面

已经是 OpenWrt 的机器，进 LuCI → **系统 → 备份/升级 → 刷写新固件**，选 `sysupgrade.bin`，**取消勾选“保留配置”**（跨版本、跨配置升级更要取消）。

刷完自动重启，访问 `http://192.168.1.1`，无密码，先设置 root 密码。

## 刷完之后

### 当副路由 / AP

两种接法，按需要选：

**A. 二级路由（独立网段，推荐给“科学上网”场景）**
主路由 LAN → 小米 mini 的 **WAN** 口。mini 上保持默认 DHCP，网段仍是 192.168.1.1。ssr-plus 只管自己网段内的设备，不影响主网络，出问题也好回滚。

**B. 同级 AP（同一网段）**
主路由 LAN → mini 的 **LAN** 口，mini 上关掉 DHCP（网络 → 接口 → LAN → 忽略此接口），LAN IP 改成主网段里没被占用的地址（比如 192.168.31.2）。此时 mini 只当交换机和无线 AP，ssr-plus 需要走“绕过大陆 IP”模式，且对主路由下的设备不生效。

顺手建议：`网络 → 无线` 里把 2.4G 信道固定成 1/6/11 中较干净的一个，别用自动。

### 外挂硬盘当 NAS

1. 插上硬盘（机械盘务必用**带独立供电**的硬盘盒，mini 的 USB 口带不动 2.5 寸机械盘，容易掉盘甚至重启）
2. LuCI → **系统 → 挂载点**，确认识别到设备，格式建议 **ext4**（NTFS/exFAT 能读但写入性能和 CPU 占用都更差）
3. 挂到 `/mnt/sda1`，勾选“启用”
4. **网络存储 → 网络共享**，添加共享目录 `/mnt/sda1`，设好允许用户（ksmbd 首次进入需要先设一个 SMB 用户密码）

访问方式：`\\192.168.1.1`（Windows）或 `smb://192.168.1.1`（macOS/手机）。

### aria2 离线下载

LuCI → **服务 → Aria2**，下载目录填 `/mnt/sda1/aria2`（记得先在挂载点里建好目录并给权限），RPC 密钥自己设一个。网页前端走 **服务 → AriaNg**，默认端口 6800。

### ssr-plus

LuCI → **服务 → SSR Plus**，订阅链接填进去更新节点，用**绕过中国大陆 IP** 模式最省心。百兆口 + MT7620 的加解密能力有限，AES-128-GCM 之类硬件友好的加密方式能明显减轻 CPU 压力；cha20 系列跑满百兆基本没戏。

## 常见问题

**Q：刷完进不去后台？**
先确认网线插对了口（WAN/LAN 别搞混），本机改成自动获取 IP，等 2–3 分钟。原厂固件刷过来时，网段可能还是 192.168.31.1，试试这个地址。

**Q：提示固件太大刷不进去？**
16MB flash 装 11MB 固件已经很紧。要加插件就得先减插件，别指望塞满。

**Q：overlay 可用空间一点点变少？**
`/overlay` 只有 4MB 左右，日志和 opkg 缓存都会吃它。可以 `opkg clean`，或者把日志目录挂到硬盘上。

**Q：Actions 编译失败了怎么看？**
工作流保留了构建历史（以前的版本会每天清理 run，现在不再清了）。失败时先看 `Align configuration` 和 `Compile the firmware` 两步的日志，`make -j1 V=s` 会打印出具体是哪个包挂掉。

**Q：runner 版本？**
现在固定 `ubuntu-24.04`。如果遇到宿主工具（host tools）编译报错，把工作流里 `runs-on` 改成 `ubuntu-22.04` 试一次——老版本的 LEDE 在新工具链上偶有兼容问题。

## 维护记录

**2026-10-21 修复编译阻断问题**

- `samba36-server` 已从 Lean 源移除，旧的 `luci-app-samba` 依赖不成立 → SMB 共享改用 `luci-app-ksmbd` + `ksmbd-server`（内核态，体积小）。不改的话 defconfig 会静默丢掉整个共享功能
- LuCI 语言包命名由 `zh-cn` 改为 `zh_Hans`，同步修正，避免中文界面丢失
- 上述两项在 `diy-part2.sh` 里做定点修正（`.config` 是 6800 行存档，不值得整体重写），脚本带自检，改不动就中止
- `source_ref` 支持填提交号（原来只支持分支，`git clone -b <sha>` 会失败）
- 目标设备与核心插件增加硬校验，缺失即失败
- 编译失败后不再继续执行打包 / 发 Release，避免拿空目录发布
- 上传产物改为 `if-no-files-found: error`，没产物就是失败
- 两个工作流的并发组加上工作流名，互不顶掉
- 磁盘清理增加 CodeQL、Swift、JVM、boost、docker 镜像

**2026-10 重构**

- `runs-on` 从 `ubuntu-20.04` 改为 `ubuntu-24.04`（20.04 镜像已于 2025-04-15 退役，原工作流直接启动失败）
- 依赖安装不再依赖 `git.io` 短链（该服务已停），改为显式 apt 包列表
- `::set-output` 全部换成 `$GITHUB_OUTPUT` / `$GITHUB_ENV`
- `actions/checkout`、`actions/upload-artifact`、`action-gh-release` 升级到 v4 / v4 / v2
- 旧 Release 清理从第三方 action 改为 `gh` CLI，并显式声明 `permissions: contents: write`
- 不再每天删除构建记录，保留日志便于排查
- Release 说明里加上源码提交、目标设备、文件 sha256
- 新增 `source_ref` 输入，可指定源码版本
- SSH 调试从 `P3TERX/ssh2actions` 换成 `mxschmitt/action-tmate`，并限制仅仓库所有者可连
- README 按实际用途重写

## 免责声明

固件按“现状”提供，不保证适配你的具体硬件批次。刷机导致的一切后果由使用者自行承担。仓库里的配置只针对小米路由器 mini（R1CM），别往别的机器上刷。

## License

[MIT](LICENSE)，继承自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)。
