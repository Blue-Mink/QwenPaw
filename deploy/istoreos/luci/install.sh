#!/bin/sh
# QwenPaw LuCI 界面安装脚本
# 适用于 iStoreOS / OpenWrt
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LUCI_DIR="/usr/lib/lua/luci"

echo "========================================="
echo "安装 QwenPaw LuCI 界面"
echo "========================================="

# 检查权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请以 root 权限运行此脚本"
    exit 1
fi

# 检查 LuCI
if [ ! -d "${LUCI_DIR}" ]; then
    echo "错误: 未找到 LuCI 目录，请确认系统为 OpenWrt/iStoreOS"
    exit 1
fi

# 创建视图目录
mkdir -p "${LUCI_DIR}/view/qwenpaw"

# 安装控制器
echo "安装控制器..."
cp "${SCRIPT_DIR}/controller.lua" "${LUCI_DIR}/controller/qwenpaw.lua"
chmod 644 "${LUCI_DIR}/controller/qwenpaw.lua"

# 安装 CBI 模型
echo "安装 CBI 模型..."
cp "${SCRIPT_DIR}/cbi_model.lua" "${LUCI_DIR}/model/cbi/qwenpaw.lua"
chmod 644 "${LUCI_DIR}/model/cbi/qwenpaw.lua"

# 安装视图
echo "安装视图..."
cp "${SCRIPT_DIR}/status_view.htm" "${LUCI_DIR}/view/qwenpaw/qwenpaw_status.htm"
cp "${SCRIPT_DIR}/log_view.htm" "${LUCI_DIR}/view/qwenpaw/qwenpaw_log.htm"
chmod 644 "${LUCI_DIR}/view/qwenpaw/"*.htm

# 检查 UCI 配置
if [ ! -f "/etc/config/qwenpaw" ]; then
    echo "安装 UCI 配置..."
    cp "${SCRIPT_DIR}/../config/qwenpaw" "/etc/config/qwenpaw"
    chmod 644 "/etc/config/qwenpaw"
else
    echo "UCI 配置已存在，跳过"
fi

# 刷新 LuCI 缓存
echo "刷新 LuCI 缓存..."
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true

# 重启 uhttpd
echo "重启 uhttpd..."
/etc/init.d/uhttpd restart 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true

echo ""
echo "安装完成！"
echo ""
echo "访问地址: http://路由器IP/cgi-bin/luci/admin/services/qwenpaw"
echo "（请确保 qwenpaw Docker 容器已运行）"
