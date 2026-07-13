# iStoreOS 旁路由部署 QwenPaw 完整教程（Docker 方式）

> **文档版本**: 2.0 | **最后更新**: 2026-07-14
> **适用环境**: iStoreOS 24.10.7 + Docker + QwenPaw 1.1.12.post3（python:3.10-slim）

---

## 目录

1. [环境说明](#1-环境说明)
2. [Docker 持久化存储配置](#2-docker-持久化存储配置)
3. [构建 QwenPaw 镜像](#3-构建-qwenpaw-镜像)
4. [创建并启动容器](#4-创建并启动容器)
5. [配置与验证](#5-配置与验证)
6. [从 NAS 同步配置（可选）](#6-从-nas-同步配置可选)
7. [常见问题排查](#7-常见问题排查)
8. [附录：完整命令速查](#8-附录完整命令速查)

---

## 1. 环境说明

### 拓扑
```
互联网 → 主路由(192.168.3.1) → NAS服务器
                               → iStoreOS旁路由(192.168.3.125)
                                       ↓
                                 Docker容器(qwenpaw:1.1.12)
                                 端口19093 (host网络)
```

### 最终技术栈
| 组件 | 版本/类型 | 说明 |
|------|----------|------|
| 旁路由系统 | iStoreOS 24.10.7 (OpenWrt LEDE) | LuCI + Dropbear |
| 容器引擎 | Docker (dockerd) | 开机自启 OK |
| Docker 根目录 | `/ext_overlay/docker` | 持久化 ext4 分区，重启不丢失 |
| 基础镜像 | `python:3.10-slim` | QwenPaw 不支持 Python 3.14，故不用 Alpine |
| QwenPaw 镜像 | `qwenpaw:1.1.12`（自定义） | 基于 python:3.10-slim 构建，126MB |
| QwenPaw 版本 | 1.1.12.post3 | pip 阿里云源安装 |
| 网络模式 | host | 容器直接使用宿主机网络 |
| 数据目录 | `/ext_overlay/qwenpaw_data/` → 容器内 `/root/.qwenpaw/` | 持久化 |
| 缓存目录 | `/root/.cache/qwenpaw/`（容器内） | 挂载到宿主机持久化 |
| 备份目录 | `/ext_overlay/qwenpaw_backups/` | 保留最近 5 份 |
| 开机自启 | Docker `--restart always` + `S99dockerd` | 系统重启后容器自动恢复 |

### 设计要点
- **为什么用 python:3.10-slim？** QwenPaw 在 Alpine（Python 3.14）上因缺失依赖包无法运行，必须用 Debian 系的 slim 镜像
- **为什么提交自定义镜像？** 避免每次重建容器都要重新 pip install（网络慢），且 Alpine 镜像拉取过多浪费磁盘
- **为什么 Docker 根目录要迁移？** iStoreOS 默认 Docker 数据在 tmpfs，系统重启后容器和镜像全部丢失

---

## 2. Docker 持久化存储配置

> ⚠️ **关键步骤**：iStoreOS 默认将 Docker 数据存储在 `/tmp/lib/docker`（tmpfs），重启即丢失。
> 必须迁移到持久化分区。

### 2.1 确认持久化分区

```bash
# 查看分区列表
block info | grep -o 'sda[0-9]*'

# 确认 ext4 分区（如 sda4）
mount | grep /ext_overlay
# 输出: /dev/sda4 on /ext_overlay type ext4 (rw,noatime)
```

推荐使用 `/ext_overlay/docker`（ext4 分区，与 overlay 文件系统同一分区）。

### 2.2 迁移 Docker 根目录

```bash
# 1. 停止 Docker 服务
/etc/init.d/dockerd stop

# 2. 创建持久化目录
mkdir -p /ext_overlay/docker

# 3. 修改 Docker 配置
cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/ext_overlay/docker",
  "storage-driver": "overlay2"
}
EOF

# 4. 迁移现有数据（如果之前已有）
# mv /tmp/lib/docker/* /ext_overlay/docker/ 2>/dev/null
# 或直接重启 Docker，自动创建空目录

# 5. 启动 Docker
/etc/init.d/dockerd start

# 6. 确认
docker info | grep "Docker Root Dir"
# 应输出: Docker Root Dir: /ext_overlay/docker
```

### 2.3 确保 Docker 开机自启

```bash
ls -la /etc/rc.d/S99dockerd
# 如不存在则:
/etc/init.d/dockerd enable
```

---

## 3. 构建 QwenPaw 镜像

> 先准备 Python 基础镜像，再在容器内安装 QwenPaw，最后提交为自定义镜像。
> 这样后续只需 `docker start qwenpaw` 即可，无需重复安装。

### 3.1 拉取 Python 基础镜像

```
旁路由本身无 Docker Hub 加速，可借助 NAS 上已有的 kspeeder 加速器：

**方式 A：NAS 上拉取并传输（推荐）**
```bash
# 在 NAS 上拉取 python:3.10-slim（通过 kspeeder 加速）
docker pull 127.0.0.1:5443/library/python:3.10-slim

# 重新打标签
docker tag 127.0.0.1:5443/library/python:3.10-slim python:3.10-slim

# 导出为 tar
docker save python:3.10-slim | gzip > python310slim.tar.gz

# SCP 传输到旁路由
scp python310slim.tar.gz root@192.168.3.125:/tmp/

# 在旁路由上加载
ssh root@192.168.3.125 "docker load < /tmp/python310slim.tar.gz"
```

**方式 B：旁路由直连备用源**
```bash
docker pull docker.1ms.run/library/python:3.10-slim
docker tag docker.1ms.run/library/python:3.10-slim python:3.10-slim
```

### 3.2 启动临时容器安装 QwenPaw

```bash
# 创建数据目录（持久化）
mkdir -p /ext_overlay/qwenpaw_data

# 启动临时容器（使用阿里云镜像源加速）
docker run -d --name qwenpaw_build \
  --network host \
  -v /ext_overlay/qwenpaw_data:/root/.qwenpaw \
  python:3.10-slim \
  sleep infinity

# 进入容器
docker exec -it qwenpaw_build bash
```

### 3.3 在容器内安装 QwenPaw

```bash
# 容器内执行：

# 更新 pip 并安装 QwenPaw（阿里云 PyPI 源加速）
pip install --upgrade pip -i https://mirrors.aliyun.com/pypi/simple/
pip install qwenpaw==1.1.12.post3 -i https://mirrors.aliyun.com/pypi/simple/

# 安装 cloudpaw 插件依赖（可选，但推荐）
pip install iac-code -i https://mirrors.aliyun.com/pypi/simple/

# 验证安装
qwenpaw --version
# 输出: QwenPaw, version 1.1.12.post3
```

> ⚠️ **注意**：安装过程可能需要 2-5 分钟。阿里云源比官方 pypi.org 快数十倍。
> 官方源实测可能超时 600 秒。

### 3.4 提交为自定义镜像

```bash
# 退出容器
exit

# 提交容器为镜像（约 126MB）
docker commit qwenpaw_build qwenpaw:1.1.12

# 停止并删除临时容器
docker stop qwenpaw_build && docker rm qwenpaw_build
```

### 3.5 清理基础镜像（可选）

```bash
# 删除基础镜像以节省空间（qwenpaw:1.1.12 已包含全部内容）
docker rmi python:3.10-slim
docker rmi docker.1ms.run/library/python:3.10-slim
docker image prune -f  # 清理 dangling 镜像
```

---

## 4. 创建并启动容器

### 4.1 创建最终容器

```bash
docker run -d \
  --name qwenpaw \
  --network host \
  --privileged \
  --restart always \
  -v /ext_overlay/qwenpaw_data:/root/.qwenpaw \
  qwenpaw:1.1.12 \
  qwenpaw app --host 0.0.0.0 --port 19093 --log-level info
```

**参数详解：**

| 参数 | 说明 |
|------|------|
| `--network host` | 使用宿主机网络，容器内 19093 端口直接在 `192.168.3.125:19093` 上监听 |
| `--privileged` | 特权模式，部分插件（如 Docker-in-Docker）需要 |
| `--restart always` | 容器退出后自动重启（含系统重启后 Docker 启动时） |
| `-v ...` | 挂载持久化数据目录 |
| `qwenpaw app ...` | **容器启动命令**，直接运行 QwenPaw 服务，无需额外拉起 |

> **与旧版（ubuntu:22.04）的关键区别**：旧版容器启动命令是 `tail -f /dev/null`，需要额外手动拉起 QwenPaw。
> 新版容器启动命令直接就是 `qwenpaw app ...`，容器启动即自动运行 QwenPaw，无需二次拉起。

### 4.2 确认容器运行

```bash
docker ps --filter name=qwenpaw --format "{{.Names}} {{.Status}}"
# 输出: qwenpaw Up About a minute
```

---

## 5. 配置与验证

### 5.1 健康检查

```bash
# 本地测试
curl -so /dev/null -w "%{http_code}" http://127.0.0.1:19093/
# 返回 200 表示正常

# 局域网测试
curl -so /dev/null -w "%{http_code}" http://192.168.3.125:19093/
```

### 5.2 查看启动日志

```bash
docker logs qwenpaw --tail 20
```

正常启动日志应包含：
```
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:19093
```

### 5.3 准备配置文件

首次启动时 QwenPaw 会在 `/root/.qwenpaw/` 下自动生成默认配置。
您也可以从已有实例同步配置（见第 6 节）。

配置文件结构：
```
/root/.qwenpaw/          ← 即挂载卷 /ext_overlay/qwenpaw_data/
├── config.json            主配置文件（API Key、模型、Agent 等）
├── skill_pool/            技能池
├── plugins/               插件
├── workspaces/            工作区
│   ├── default/
│   ├── cloud-orchestrator/
│   ├── cloud-executor/
│   └── ...
├── sessions/              会话历史
├── chats.json             聊天记录
└── jobs.json              任务记录
```

### 5.4 （可选）配置 QQ 频道机器人

编辑 `/ext_overlay/qwenpaw_data/config.json`，在 `qq_bot` 字段中：
```json
{
  "qq_bot": {
    "type": "qq_channel",
    "enabled": true,
    "app_id": "你的 app_id",
    "client_secret": "你的 client_secret",
    "max_reconnect_attempts": -1
  }
}
```

修改后需重启容器：
```bash
docker restart qwenpaw
```

---

## 6. 从 NAS 同步配置（可选）

如果 NAS 上已有 QwenPaw 实例，可以通过同步脚本将配置复制到旁路由。

### 6.1 同步脚本

创建 `/path/to/sync_qwenpaw_config.sh`（完整脚本参见 v1 文档附录），核心流程：

```
执行流程：
  ① 备份旁路由当前配置 → ② 打包本机(NAS)配置
  → ③ SCP 传输到旁路由 → ④ 解压并重启容器
  → ⑤ 拉起 QwenPaw → ⑥ 重试验证(HTTP 200)

自动回滚条件：
  ❌ 解压配置失败
  ❌ 容器重启失败
  ❌ QwenPaw 启动超时（HTTP 非 200）

备份保留：最近 5 份，位于旁路由 /ext_overlay/qwenpaw_backups/
```

### 6.2 设置定时同步（cron）

```bash
crontab -e
# 添加：
0 */6 * * * /path/to/sync_qwenpaw_config.sh > /dev/null 2>&1
```

---

## 7. 常见问题排查

### 7.1 容器启动了但 HTTP 无法访问

**原因：** 防火墙拦截
```bash
# 临时放行
iptables -I INPUT -p tcp --dport 19093 -j ACCEPT

# 持久化（LuCI 面板 网络→防火墙→自定义规则）
# 添加: iptables -I INPUT -p tcp --dport 19093 -j ACCEPT
```

### 7.2 Docker 重启后容器没起来

检查 Docker 服务是否开机自启：
```bash
ls -la /etc/rc.d/S99dockerd
```
如果不存在：
```bash
/etc/init.d/dockerd enable
```

确认容器 restart 策略：
```bash
docker inspect qwenpaw --format '{{.HostConfig.RestartPolicy.Name}}'
# 应为: always
```

### 7.3 镜像拉取慢 / 拉取失败

使用代理或备用镜像源：
```bash
# 如果有 kspeeder 加速器
docker pull 127.0.0.1:5443/library/python:3.10-slim

# 备用公共加速源
docker pull docker.1ms.run/library/python:3.10-slim

# 或从 NAS 导出导入（推荐）
# NAS: docker save python:3.10-slim | gzip > /tmp/py310.tar.gz
# NAS → 旁路由: scp /tmp/py310.tar.gz root@192.168.3.125:/tmp/
# 旁路由: docker load < /tmp/py310.tar.gz
```

### 7.4 pip 安装 QwenPaw 报错

**错误：Python 3.14 not supported**
```
原因：使用了 Alpine 镜像（Python 3.14），QwenPaw 只支持到 3.10-3.12
解决：必须使用 python:3.10-slim 或 python:3.11-slim 基础镜像
```

**错误：超时 / 找不到版本**
```
原因：官方 pypi.org 源在国内极慢
解决：始终使用阿里云源:
  pip install qwenpaw -i https://mirrors.aliyun.com/pypi/simple/
```

### 7.5 容器内无法使用中文 / 中文乱码

```bash
# 安装中文字体支持（python:3.10-slim 需要）
apt-get update && apt-get install -y locales
locale-gen zh_CN.UTF-8
```

### 7.6 SSH 无法登录旁路由

如果误关了 RootPasswordAuth：
- 通过 LuCI Web 面板恢复: `http://192.168.3.125` → 系统 → 管理 → SSH 访问
- 勾选 "RootPasswordAuth"，保存&应用

---

## 8. 附录：完整命令速查

### Docker 操作
```bash
# 容器管理
docker start qwenpaw
docker stop qwenpaw
docker restart qwenpaw
docker logs -f qwenpaw
docker exec -it qwenpaw bash

# 删除重建（保留数据）
docker stop qwenpaw && docker rm qwenpaw
docker run -d --name qwenpaw --network host --privileged --restart always \
  -v /ext_overlay/qwenpaw_data:/root/.qwenpaw \
  qwenpaw:1.1.12 \
  qwenpaw app --host 0.0.0.0 --port 19093 --log-level info
```

### 健康检查
```bash
curl -so /dev/null -w "%{http_code}" http://127.0.0.1:19093/
# 返回 200 即正常
```

### 查看 QwenPaw 日志
```bash
docker logs qwenpaw --tail 50 -f
```

### 配置同步
```bash
# 查看备份列表
bash sync_qwenpaw_config.sh --list

# 回滚到最近备份
bash sync_qwenpaw_config.sh --restore
```

### QwenPaw 版本升级
```bash
# 1. 进入容器
docker exec -it qwenpaw bash

# 2. 升级包
pip install --upgrade qwenpaw -i https://mirrors.aliyun.com/pypi/simple/

# 3. 退出容器后重启
exit
docker restart qwenpaw

# 4. 验证
curl -s http://127.0.0.1:19093/ | grep -o '"version":"[^"]*"'
```

---

> **文档版本**: 2.0 | **最后更新**: 2026-07-14
> **主要变更**: 改用 python:3.10-slim 基础镜像 + 自定义 qwenpaw:1.1.12 镜像；
>             容器启动命令直接运行 QwenPaw，无需二次拉起；
>             Docker 根目录迁移到 `/ext_overlay/docker` 持久化。
