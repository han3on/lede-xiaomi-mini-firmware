#!/bin/bash
#
# OpenWrt DIY script part 2（feeds install 之后、make defconfig 之前执行）
#
# 仓库里的 .config 是 2022 年的存档，直接交给当前的 Lean 源码有两处硬伤，
# 不修的话 make defconfig 会把相关功能静默丢掉（编译照样成功，但固件少东西）：
#
#   1. samba36-server 已从软件源移除，luci-app-samba 的依赖不再成立
#      → SMB 共享改用内核态 ksmbd（体积只有几百 KB，samba4 塞不进 16MB flash）
#   2. LuCI 的语言包目录由 zh-cn 改名为 zh_Hans
#      → 旧写法会让 defconfig 丢掉中文语言包，界面回退英文
#
# 这里做定点修正，改完仍交给 make defconfig 归一化。
#

set -e

CFG=.config
if [ ! -f "$CFG" ]; then
    echo "找不到 $CFG，跳过适配"
    exit 0
fi

echo ">>> [1/3] SMB 实现：samba36 -> ksmbd"
sed -i \
    -e 's|^CONFIG_PACKAGE_luci-app-samba=y|# CONFIG_PACKAGE_luci-app-samba is not set|' \
    -e 's|^CONFIG_PACKAGE_samba36-server=y|# CONFIG_PACKAGE_samba36-server is not set|' \
    -e 's|^# CONFIG_PACKAGE_ksmbd-server is not set|CONFIG_PACKAGE_ksmbd-server=y|' \
    "$CFG"

for pkg in luci-app-ksmbd luci-i18n-ksmbd-zh_Hans; do
    if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" "$CFG"; then
        echo "CONFIG_PACKAGE_${pkg}=y" >> "$CFG"
        echo "    新增 $pkg"
    fi
done

echo ">>> [2/3] LuCI 语言包命名：zh-cn -> zh_Hans"
sed -i -E 's|^(# )?CONFIG_PACKAGE_(luci-i18n-[a-z0-9._-]+)-zh-cn=y|\1CONFIG_PACKAGE_\2-zh_Hans=y|' "$CFG"
sed -i -E 's|^(# )?CONFIG_LUCI_LANG_zh-cn=y|\1CONFIG_LUCI_LANG_zh_Hans=y|' "$CFG"

echo ">>> [3/3] 校验修正结果"
FAIL=0
for key in luci-app-ksmbd ksmbd-server luci-i18n-ksmbd-zh_Hans; do
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
if grep -qE '^CONFIG_PACKAGE_luci-i18n-.*-zh-cn=y' "$CFG"; then
    echo "    仍存在 zh-cn 语言包写法"
    FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
    echo "配置适配失败，终止编译"
    exit 1
fi
echo "    配置适配完成"
