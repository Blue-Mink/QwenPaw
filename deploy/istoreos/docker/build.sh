#!/bin/sh
# QwenPaw Docker 镜像一键构建脚本
set -e

IMAGE_NAME="qwenpaw:1.1.12"
DOCKERFILE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================="
echo "构建 QwenPaw Docker 镜像"
echo "镜像名称: ${IMAGE_NAME}"
echo "Dockerfile: ${DOCKERFILE_DIR}/Dockerfile"
echo "========================================="

if ! command -v docker >/dev/null 2>&1; then
    echo "错误: 请先安装 Docker"
    exit 1
fi

echo ""
echo "开始构建..."
docker build -t "${IMAGE_NAME}" "${DOCKERFILE_DIR}"

echo ""
echo "构建完成！"
echo ""
docker images "${IMAGE_NAME}" --format "{{.Repository}}:{{.Tag}} ({{.Size}})"
echo ""
echo "启动容器:"
echo "  docker run -d \\"
echo "    --name qwenpaw \\"
echo "    --network host \\"
echo "    --privileged \\"
echo "    --restart always \\"
echo "    -v /ext_overlay/qwenpaw_data:/root/.qwenpaw \\"
echo "    ${IMAGE_NAME}"
