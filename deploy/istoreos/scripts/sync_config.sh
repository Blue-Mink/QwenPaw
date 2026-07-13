#!/bin/bash
# QwenPaw 配置同步脚本（模板）
# 从主 QwenPaw 实例同步配置到旁路由
# 使用方法:
#   同步:   bash sync_config.sh
#   回滚:   bash sync_config.sh --restore
#   列表:   bash sync_config.sh --list
set -e

# ====== 配置（请根据实际情况修改）=======
REMOTE_HOST="192.168.3.x"           # 旁路由 IP
REMOTE_USER="root"
REMOTE_PASS="your_ssh_password"     # SSH 密码（建议改用密钥认证）
REMOTE_DATA_DIR="/ext_overlay/qwenpaw_data"
BACKUP_DIR="/ext_overlay/qwenpaw_backups"
MAX_BACKUPS=5
# ====================================

LOCAL_QWENPAW_DIR="$HOME/.qwenpaw"
if [ ! -d "$LOCAL_QWENPAW_DIR" ]; then
    echo "错误: 未找到本地 QwenPaw 配置目录 ($LOCAL_QWENPAW_DIR)"
    exit 1
fi

# 检查 sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    echo "错误: 请安装 sshpass"
    exit 1
fi

# 工具函数
remote_exec() {
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no \
        "${REMOTE_USER}@${REMOTE_HOST}" "$*" 2>/dev/null
}

remote_scp_to() {
    sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no \
        "$1" "${REMOTE_USER}@${REMOTE_HOST}:$2" 2>/dev/null
}

backup_remote() {
    local ts=$(date +%Y%m%d_%H%M%S)
    local name="qwenpaw_backup_${ts}.tar.gz"
    echo "备份旁路由配置..."
    remote_exec "mkdir -p ${BACKUP_DIR}" || return 1
    remote_exec "cd ${REMOTE_DATA_DIR} && tar czf ${BACKUP_DIR}/${name} \
        --exclude='qwenpaw.log*' --exclude='token_usage.json' \
        --exclude='sessions/*' --exclude='chats.json' --exclude='jobs.json' \
        --exclude='venv' . 2>/dev/null" || return 1
    echo "备份完成: ${name}"
    remote_exec "ls -t ${BACKUP_DIR}/qwenpaw_backup_*.tar.gz 2>/dev/null | \
        tail -n +$((MAX_BACKUPS+1)) | xargs -r rm -f" 2>/dev/null
}

restore_backup() {
    echo "========== 回滚 =========="
    local latest=$(remote_exec "ls -t ${BACKUP_DIR}/qwenpaw_backup_*.tar.gz 2>/dev/null | head -1")
    [ -z "$latest" ] && { echo "没有备份"; exit 5; }
    echo "使用备份: $(basename $latest)"
    remote_exec "cd ${REMOTE_DATA_DIR} && tar xzf ${latest}" || exit 6
    remote_exec "docker restart qwenpaw" || exit 7
    sleep 5
    remote_exec "docker exec -d qwenpaw sh -c 'nohup qwenpaw app --host 0.0.0.0 \
        --port 19093 --log-level info > /root/.qwenpaw/qwenpaw.log 2>&1 &'" 2>/dev/null
    local code=""
    for i in 1 2 3 4 5; do
        sleep 3
        code=$(remote_exec "docker exec qwenpaw curl -so /dev/null -w '%{http_code}' \
            http://127.0.0.1:19093/" 2>/dev/null)
        [ "$code" = "200" ] && break
    done
    [ "$code" = "200" ] && echo "回滚成功 ✅" || echo "回滚失败 ❌"
}

main() {
    echo "开始同步 QwenPaw 配置..."

    # 1. 备份
    backup_remote || { echo "备份失败"; exit 4; }

    # 2. 打包
    local pkg="/tmp/qwenpaw_sync_$(date +%Y%m%d%H%M%S).tar.gz"
    cd "$LOCAL_QWENPAW_DIR" || exit 1
    tar czf "$pkg" \
        --exclude='qwenpaw.log*' --exclude='token_usage.json' \
        --exclude='HEARTBEAT.md' --exclude='.qwenpaw_restore.lock' \
        --exclude='sessions/*' --exclude='chats.json' --exclude='jobs.json' \
        config.json skill_pool/ plugins/ workspaces/ 2>/dev/null || true

    # 3. 传输
    echo "传输到旁路由..."
    remote_scp_to "$pkg" "/tmp/qwenpaw_sync_latest.tar.gz" || { echo "传输失败"; rm -f "$pkg"; exit 2; }

    # 4. 解压 + 重启
    echo "解压并重启容器..."
    remote_exec "cd ${REMOTE_DATA_DIR} && tar xzf /tmp/qwenpaw_sync_latest.tar.gz && docker restart qwenpaw" || {
        echo "解压失败，自动回滚..."; restore_backup; rm -f "$pkg"; exit 3
    }

    # 5. 验证
    echo "验证服务..."
    remote_exec "docker exec -d qwenpaw sh -c 'nohup qwenpaw app --host 0.0.0.0 \
        --port 19093 --log-level info > /root/.qwenpaw/qwenpaw.log 2>&1 &'" 2>/dev/null
    local code=""
    for i in 1 2 3 4 5 6; do
        sleep 3
        code=$(remote_exec "docker exec qwenpaw curl -so /dev/null -w '%{http_code}' \
            http://127.0.0.1:19093/" 2>/dev/null)
        [ "$code" = "200" ] && break
        echo "等待... (第${i}次, HTTP ${code})"
    done

    if [ "$code" = "200" ]; then
        echo "同步成功！HTTP ${code} ✅"
    else
        echo "验证失败，自动回滚..."; restore_backup; rm -f "$pkg"; exit 4
    fi
    rm -f "$pkg"
    echo "完成！备份: ${REMOTE_HOST}:${BACKUP_DIR}/"
}

case "${1:-}" in
    --restore|-r) restore_backup ;;
    --list|-l)    echo "备份列表:"; remote_exec "ls -lh ${BACKUP_DIR}/" 2>/dev/null ;;
    --help|-h)    echo "用法: $0 [--restore|--list|--help]";;
    *)            main ;;
esac
