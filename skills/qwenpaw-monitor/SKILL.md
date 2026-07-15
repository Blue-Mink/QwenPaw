---
name: qwenpaw-monitor
description: "QwenPaw 状态巡检 Skill（旁路由专用）: 检查容器状态、端口、配置、QQ频道、自启动和保活机制。" 
metadata:
  qwenpaw:
    emoji: "🔍"
    requires:
      bins: ["python3", "docker"]
      envs: []
  version: "1.0.0"
---

# QwenPaw 状态巡检 Skill

用于在 iStoreOS 旁路由上全面巡检 QwenPaw 的运行状态、配置正确性、自启动配置和永保活机制。

## 功能清单

- ✅ 容器状态与重启策略检查
- ✅ 端口监听与 HTTP 健康检查
- ✅ 数据卷挂载与持久化检查
- ✅ 核心配置验证（active_model.json、cc_switch.db）
- ✅ NVIDIA provider 配置检查
- ✅ QQ 频道状态与掉线重连机制验证
- ✅ 自启动配置检查（Docker restart always、rc.local、crontab）
- ✅ 日志错误关键词扫描
- ✅ 生成结构化巡检报告（JSON + 可读文本）

## 使用方法

```bash
# 在 QwenPaw 容器内运行（推荐）
docker exec qwenpaw python /root/.qwenpaw/skill_pool/qwenpaw-monitor/monitor.py

# 或在宿主机直接运行（需相同环境）
python /ext_overlay/qwenpaw_data/skill_pool/qwenpaw-monitor/monitor.py
```

## 输出

- `stdout`: 可读的巡检报告（带颜色标记）
- JSON 格式输出到 `stdout`（`--json` 参数）
- 日志文件：`/root/.qwenpaw/qwenpaw-monitor.log`

## 依赖

- Python 3.10+（容器内已满足）
- `docker` CLI（可选，用于容器命令检查，若无则使用 ps 替代）
- `sqlite3`（用于检查 cc_switch.db）

## 部署

Skill 已经部署到旁路由 QwenPaw 容器内：
- 路径：`/ext_overlay/qwenpaw_data/skill_pool/qwenpaw-monitor/`
- 可通过调用 `qwenpaw-monitor` 触发（如 crontab 或 LuCI 界面集成）

## 注意事项

- 本 Skill 专为 iStoreOS 旁路由环境设计，依赖固定路径 `/ext_overlay/qwenpaw_data`
- 检查 QQ 频道状态会读取 `/root/.qwenpaw/config.json` 和容器日志
- 自动重连机制由 QwenPaw 内置 client 处理，本 Skill 仅验证配置
- 巡检失败项目会标记为 ❌ 并给出修复建议
