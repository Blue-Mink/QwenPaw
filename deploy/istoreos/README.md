# iStoreOS / OpenWrt 部署 QwenPaw 完整包

> 本包包含在 iStoreOS（OpenWrt）旁路由上通过 Docker 部署 QwenPaw AI 智能体所需的全部文件。

## 目录结构

```
deploy/istoreos/
├── README.md              # 本文件
├── docker/
│   ├── Dockerfile         # QwenPaw 镜像构建文件
│   └── build.sh           # 一键构建镜像脚本
├── luci/
│   ├── controller.lua     # LuCI 控制器（菜单 + API）
│   ├── cbi_model.lua      # CBI 表单模型（配置界面）
│   ├── status_view.htm    # 状态面板视图（AJAX 实时刷新）
│   ├── log_view.htm       # 日志查看器视图
│   └── install.sh         # LuCI 界面安装脚本
├── scripts/
│   ├── deploy_qwenpaw.sh  # 完整自动化部署脚本
│   └── sync_config.sh     # 配置同步脚本模板
└── config/
    └── qwenpaw            # UCI 配置文件模板
```

## 快速开始

### 1. 构建 Docker 镜像

```bash
cd docker
chmod +x build.sh
./build.sh
```

### 2. 创建并启动容器

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

### 3. 安装 LuCI 界面

```bash
cd luci
chmod +x install.sh
./install.sh
```

然后浏览器访问：`http://你的旁路由IP/cgi-bin/luci/admin/services/qwenpaw`

## 依赖

- Docker（已安装并运行）
- LuCI（OpenWrt/iStoreOS 自带）
- 基础镜像：`python:3.10-slim`
- Python 包：`qwenpaw==1.1.12.post3`（通过阿里云 PyPI 源安装）

## 注意事项

- Docker 根目录需迁移到持久化分区（如 `/ext_overlay/docker`），避免重启丢失
- 容器使用 `--restart always` 策略，系统重启后自动恢复
- 数据目录 `/ext_overlay/qwenpaw_data` 需手动创建
