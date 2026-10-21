#!/bin/bash
#
# OpenWrt DIY script part 2（feeds install 之后、make defconfig 之前执行）
#
# 仓库里的 .config 是 2022 年的存档，直接交给当前的 Lean 源码有三处硬伤，
# 不改的话要么编译失败，要么编译成功但功能缺失：
#
#   1. vsftpd-alt 与 luci-app-vsftpd 冲突（2026-10-21 构建失败的直接原因）
#      luci-app-vsftpd 硬依赖 vsftpd（feeds/packages/net/vsftpd），而 vsftpd-alt
#      没有声明 Provides/Conflicts，两个包会同时被选中。它们都要装
#      /etc/init.d/vsftpd 与 /usr/sbin/vsftpd，opkg 在 package/install 阶段报
#      check_data_file_clashes，整个编译以 exit 2 结束。
#
#   2. samba36-server 已从软件源移除，luci-app-samba 的依赖不再成立
#      → SMB 共享改用内核态 ksmbd（体积只有几百 KB，samba4 塞不进 16MB flash）
#
#   3. LuCI 中文语言包的命名有两套，写反了 defconfig 会静默丢掉全部中文包
#      → i18n 包名后缀归 luci.mk 的 LUCI_LC_ALIAS 管（本项目源码是 zh-cn），
#        CONFIG_LUCI_LANG_* 菜单符号跟 po 目录走（本项目源码是 zh_Hans）。
#      两者不一致是常态，所以这里分别探测，不硬编码。
#
# 只做定点修正，改完仍交给 make defconfig 归一化。
#

set -e

CFG=.config
if [ ! -f "$CFG" ]; then
    echo "找不到 $CFG，跳过适配"
    exit 0
fi

echo ">>> [1/4] LuCI 中文语言包命名（按 luci.mk / po 目录实测，不硬编码）"
# i18n 包名后缀：luci.mk 里 LUCI_LC_ALIAS.zh_Hans=zh-cn 表示 po 目录叫 zh_Hans、
# 但生成的包名是 luci-i18n-<app>-zh-cn
PKG_LANG=zh_Hans
if grep -qE '^LUCI_LC_ALIAS\.zh_Hans=zh-cn' feeds/luci/luci.mk 2>/dev/null; then
    PKG_LANG=zh-cn
elif ls -d feeds/luci/*/*/po/zh-cn >/dev/null 2>&1; then
    PKG_LANG=zh-cn
fi
# CONFIG_LUCI_LANG_* 符号：跟 LUCI_LANG.<lang> 的定义走
LANG_SYM=zh-cn
if grep -qE '^LUCI_LANG\.zh_Hans=' feeds/luci/luci.mk 2>/dev/null; then
    LANG_SYM=zh_Hans
fi
OTHER_PKG=zh_Hans
[ "$PKG_LANG" = "zh_Hans" ] && OTHER_PKG=zh-cn
OTHER_SYM=zh_Hans
[ "$LANG_SYM" = "zh_Hans" ] && OTHER_SYM=zh-cn
echo "    i18n 包名后缀=$PKG_LANG，LANG 符号=$LANG_SYM"
sed -i -E "s|^(# )?CONFIG_PACKAGE_(luci-i18n-[a-z0-9._-]+)-${OTHER_PKG}=|\1CONFIG_PACKAGE_\2-${PKG_LANG}=|" "$CFG"
sed -i -E "s|^(# )?CONFIG_LUCI_LANG_${OTHER_SYM}=|\1CONFIG_LUCI_LANG_${LANG_SYM}=|" "$CFG"

echo ">>> [2/4] SMB 实现：samba36 -> ksmbd"
sed -i \
    -e 's|^CONFIG_PACKAGE_luci-app-samba=y|# CONFIG_PACKAGE_luci-app-samba is not set|' \
    -e 's|^CONFIG_PACKAGE_samba36-server=y|# CONFIG_PACKAGE_samba36-server is not set|' \
    -e 's|^# CONFIG_PACKAGE_ksmbd-server is not set|CONFIG_PACKAGE_ksmbd-server=y|' \
    "$CFG"

for pkg in luci-app-ksmbd "luci-i18n-ksmbd-${PKG_LANG}"; do
    if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" "$CFG"; then
        echo "CONFIG_PACKAGE_${pkg}=y" >> "$CFG"
        echo "    新增 $pkg"
    fi
done

echo ">>> [3/4] FTP：luci-app-vsftpd 与 vsftpd-alt 只能留一个"
if grep -qE '^CONFIG_PACKAGE_luci-app-vsftpd=y' "$CFG" && grep -qE '^CONFIG_PACKAGE_vsftpd-alt=y' "$CFG"; then
    echo "    检测到冲突组合，关闭 vsftpd-alt（保留 luci-app-vsftpd + vsftpd）"
    sed -i \
        -e 's|^CONFIG_PACKAGE_vsftpd-alt=y|# CONFIG_PACKAGE_vsftpd-alt is not set|' \
        -e 's|^# CONFIG_PACKAGE_vsftpd is not set|CONFIG_PACKAGE_vsftpd=y|' \
        "$CFG"
fi

echo ">>> [4/4] 校验修正结果"
FAIL=0
for key in luci-app-ksmbd ksmbd-server "luci-i18n-ksmbd-${PKG_LANG}"; do
    if grep -q "^CONFIG_PACKAGE_${key}=y" "$CFG"; then
        echo "    OK   $key"
    else
        echo "    缺失 $key"
        FAIL=1
    fi
done
if grep -q '^CONFIG_PACKAGE_samba36-server=y' "$CFG"; then
    echo "    samba36-server 仍在配置中"
    FAIL=1
fi
if grep -qE "^CONFIG_PACKAGE_luci-i18n-.*-${OTHER_PKG}=y" "$CFG"; then
    echo "    仍有使用 ${OTHER_PKG} 命名的语言包"
    FAIL=1
fi
# 两个 vsftpd 同时开 = 必挂，提前拦住，别等编译 70 分钟
if grep -q '^CONFIG_PACKAGE_vsftpd=y' "$CFG" && grep -q '^CONFIG_PACKAGE_vsftpd-alt=y' "$CFG"; then
    echo "    vsftpd 与 vsftpd-alt 同时启用，会争抢 /usr/sbin/vsftpd"
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "配置适配失败，终止编译"
    exit 1
fi
echo "    配置适配完成"
