#!/bin/sh
# QwenPaw 一键部署脚本（iStoreOS Docker 版）
# 使用方法: sh deploy_qwenpaw.sh
set -e

echo "========================================="
echo "QwenPaw 一键部署脚本"
echo "========================================="

# 1. 检查 Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "错误: Docker 未安装"
    exit 1
fi

# 2. 检查镜像是否存在，不存在则构建
if ! docker images qwenpaw:1.1.12 | grep -q qwenpaw; then
    echo "未找到 qwenpaw:1.1.12 镜像，开始构建..."
    SCRIPT_DIR="$(cd "$(dirname "$0")/../docker" && pwd)"
    if [ -f "${SCRIPT_DIR}/build.sh" ]; then
        sh "${SCRIPT_DIR}/build.sh"
    else
        echo "错误: 未找到 build.sh"
        exit 1
    fi
fi

# 3. 创建数据目录
mkdir -p /ext_overlay/qwenpaw_data

# 4. 停止并删除旧容器（如果存在）
docker stop qwenpaw 2>/dev/null || true
docker rm qwenpaw 2>/dev/null || true

# 5. 创建并启动新容器
echo ""
echo "创建 QwenPaw 容器..."
docker run -d \
    --name qwenpaw \
    --network host \
    --privileged \
    --restart always \
    -v /ext_overlay/qwenpaw_data:/root/.qwenpaw \
    qwenpaw:1.1.12 \
    qwenpaw app --host 0.0.0.0 --port 19093 --log-level info

echo ""
echo "等待服务启动..."
sleep 5

# 6. 健康检查
echo "健康检查..."
for i in 1 2 3 4 5; do
    code=$(curl -so /dev/null -w "%{http_code}" http://127.0.0.1:19093/ 2>/dev/null || echo "000")
    if [ "$code" = "200" ]; then
        echo "HTTP 状态: $code ✅"
        break
    fi
    echo "等待... (第${i}次, HTTP ${code})"
    sleep 3
done

echo ""
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
echo "QwenPaw: http://本机IP:19093/"
echo "LuCI:    http://本机IP/cgi-bin/luci/admin/services/qwenpaw"
echo ""
echo "查看日志: docker logs -f qwenpaw"
