#!/usr/bin/env python3
"""
QwenPaw 巡检工具（容器内 V4）
特性：纯 Python 实现，无外部依赖；安全只读；适合 iStoreOS 旁路由容器环境
"""

import os, sys, json, subprocess, datetime, time, re, shutil
from pathlib import Path

C = type('C', (), {
    'OK': '\033[92m', 'WARN': '\033[93m', 'FAIL': '\033[91m', 'END': '\033[0m', 'BOLD': '\033[1m'
})

def log(msg, level='info'):
    sym = {'ok': f'{C.OK}✓{C.END}', 'warn': f'{C.WARN}⚠{C.END}', 'fail': f'{C.FAIL}✗{C.END}'}
    print(f"{sym.get(level,'')} {msg}")

def run(cmd, timeout=5):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip()
    except: return ""

def read_json(path):
    try:
        with open(path, 'r') as f: return json.load(f)
    except: return None

def file_exists(path):
    try:
        return Path(path).exists()
    except: return False

def file_size(path):
    try:
        return os.path.getsize(path)
    except: return 0

def check_http_health():
    try:
        import urllib.request
        with urllib.request.urlopen("http://127.0.0.1:19093/", timeout=5) as resp:
            if resp.status == 200:
                log("HTTP 健康检查通过 (200)", "ok")
                return True
            else:
                log(f"HTTP 健康检查失败 (status={resp.status})", "fail")
                return False
    except Exception as e:
        log(f"HTTP 健康检查失败 ({e})", "fail")
        return False

def check_data_dir():
    p = Path("/root/.qwenpaw")
    if p.exists():
        log("数据目录 /root/.qwenpaw 存在", "ok")
        return True
    log("数据目录不存在", "fail")
    return False

def check_active_model():
    path = "/root/.qwenpaw/.qwenpaw.secret/providers/active_model.json"
    data = read_json(path)
    if not data:
        log("未找到 active_model.json", "warn")
        return {"provider": None, "model": None}
    llm = data.get("active_llm", {})
    provider = llm.get("provider_id")
    model = llm.get("model")
    if provider:
        log(f"默认模型: provider={provider}, model={model or 'N/A'}", "ok")
    else:
        log("active_model.json 未配置 provider", "warn")
    return {"provider": provider, "model": model}

def check_nvidia_provider():
    active = check_active_model()
    if active["provider"] == "nvidia":
        log("默认 provider 为 NVIDIA (通过 active_model.json)", "ok")
        return True
    log("默认 provider 非 NVIDIA 或未配置", "warn")
    return False

def check_qq_channel():
    cfg = read_json("/root/.qwenpaw/config.json") or {}
    qq = cfg.get("channels", {}).get("qq", {})
    enabled = qq.get("enabled", False)
    app_id = qq.get("app_id")
    secret = qq.get("client_secret")
    if enabled and app_id and secret:
        log(f"QQ 频道已启用 (app_id={app_id})", "ok")
        return {"enabled": True, "app_id": app_id}
    log("QQ 频道未配置或不完整", "warn")
    return {"enabled": False}

def check_qq_log_online():
    logf = "/root/.qwenpaw/qwenpaw.log"
    if not file_exists(logf):
        log("日志文件不存在", "warn")
        return False
    # 使用 Python 直接读取最后 2000 行，避免依赖 tail
    try:
        with open(logf, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        tail = ''.join(lines[-2000:])  # 最后 2000 行
    except Exception as e:
        log(f"读取日志失败: {e}", "warn")
        return False
    if "qq ready session_id=" in tail or "qq session resumed" in tail:
        log("日志中检测到 QQ 频道连接成功", "ok")
        return True
    log("日志中未发现 QQ 频道连接成功", "warn")
    return False

def check_log_file_size(max_mb=50):
    logf = "/root/.qwenpaw/qwenpaw.log"
    if not file_exists(logf):
        log("日志文件不存在", "warn")
        return True
    sz = file_size(logf) / 1024 / 1024
    if sz < max_mb:
        log(f"日志大小: {sz:.1f} MB", "ok")
        return True
    log(f"日志大小: {sz:.1f} MB (超过 {max_mb}MB，建议轮转)", "warn")
    return False

def check_commands():
    """检查关键命令是否可用"""
    cmds = ["curl", "tail", "cat"]
    missing = [c for c in cmds if not shutil.which(c)]
    if missing:
        log(f"缺失命令: {', '.join(missing)}", "warn")
        return False
    log("关键命令检查通过", "ok")
    return True

def check_recent_errors(minutes=60):
    logf = "/root/.qwenpaw/qwenpaw.log"
    if not file_exists(logf):
        log("日志文件不存在", "warn")
        return []
    sz = file_size(logf)
    with open(logf, 'rb') as f:
        f.seek(max(0, sz - 1024 * 100))  # 读最后100KB
        tail = f.read().decode('utf-8', errors='ignore')
    # 匹配时间戳（简化：匹配 HH:MM:SS 格式）
    now = datetime.datetime.now()
    errors = []
    for line in tail.splitlines():
        if any(k in line for k in ["ERROR", "FATAL", "panic", "exception", "Traceback"]):
            # 尝试提取时间并判断是否在最近 N 分钟内
            m = re.search(r'(\d{2}):(\d{2}):(\d{2})', line)
            if m:
                h, mnt, s = map(int, m.groups())
                log_time = now.replace(hour=h, minute=mnt, second=s, microsecond=0)
                if (now - log_time).total_seconds() < minutes * 60:
                    errors.append(line)
    if errors:
        log(f"最近{minutes}分钟内发现 {len(errors)} 条错误", "warn")
        for e in errors[-3:]:
            print(f"  → {e}")
    else:
        log(f"最近{minutes}分钟内无错误日志", "ok")
    return errors

def overall_health():
    checks = [
        ("HTTP 健康", check_http_health()),
        ("数据目录挂载", check_data_dir()),
        ("NVIDIA provider", check_nvidia_provider()),
        ("QQ 频道配置", check_qq_channel().get("enabled", False)),
        ("QQ 在线状态", check_qq_log_online()),
        ("日志大小", check_log_file_size()),
        ("近期错误", len(check_recent_errors()) == 0),
    ]
    score = sum(1 for _, ok in checks if ok) / len(checks) * 100
    return score, checks

def generate_report():
    score, checks = overall_health()
    sep = "=" * 50
    print(f"{C.BOLD}{sep}")
    print("QwenPaw 巡检报告 (容器内 V4)")
    print(f"时间: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"健康评分: {score:.1f}%")
    print(f"{sep}{C.END}\n")
    for name, ok in checks:
        level = "ok" if ok else "fail"
        log(f"{name}", level)
    print(f"\n{C.BOLD}建议：{C.END}")
    if score < 100:
        if not check_http_health(): print("  • 确保容器运行且端口 19093 监听：docker start qwenpaw")
        if not check_nvidia_provider(): print("  • 设置默认 provider 为 NVIDIA (active_model.json)")
        if not check_qq_channel().get("enabled"): print("  • 配置 QQ 频道凭据 (config.json → channels.qq)")
        if not check_qq_log_online(): print("  • 检查 QQ 机器人网络连接或凭据")
        if not check_log_file_size(): print("  • 日志轮转: logrotate 或手动清理")
    else:
        print("  • 一切正常，继续保持")

if __name__ == "__main__":
    generate_report()
