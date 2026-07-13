# QwenPaw LuCI 界面构建方法（v3 最终版）

> **文档版本**: 1.0 | **最后更新**: 2026-07-14
> **适用系统**: iStoreOS 24.10.7 (OpenWrt/LEDE) — LuCI 框架

---

## 目录

1. [LuCI 界面架构概览](#1-luci-界面架构概览)
2. [前置准备：UCI 配置](#2-前置准备uci-配置)
3. [控制器（Controller）](#3-控制器controller)
4. [CBI 模型（Model）](#4-cbi-模型model)
5. [状态视图模板（Status View）](#5-状态视图模板status-view)
6. [日志视图模板（Log View）](#6-日志视图模板log-view)
7. [部署与验证](#7-部署与验证)
8. [版本演进历史](#8-版本演进历史)

---

## 1. LuCI 界面架构概览

LuCI 是 OpenWrt 的 Web 管理界面框架，采用 MVC 架构：

```
Controller（控制器）     →  路由分发、API 端点
       ↓
Model（CBI 模型）        →  表单定义、数据验证与持久化
       ↓
View（视图模板）         →  HTML 渲染（嵌入式 Lua）
```

QwenPaw LuCI 界面的文件构成：

| 文件路径 | 角色 | 说明 |
|----------|------|------|
| `/usr/lib/lua/luci/controller/qwenpaw.lua` | 控制器 | 注册菜单 + 3 个 API 端点 |
| `/usr/lib/lua/luci/model/cbi/qwenpaw.lua` | CBI 模型 | 表单字段定义与保存逻辑 |
| `/usr/lib/lua/luci/view/qwenpaw/qwenpaw_status.htm` | 状态视图 | 顶部状态面板（实时 AJAX 刷新） |
| `/usr/lib/lua/luci/view/qwenpaw/qwenpaw_log.htm` | 日志视图 | 日志查看器（自动刷新） |
| `/etc/config/qwenpaw` | UCI 配置 | 持久化存储配置项 |

---

## 2. 前置准备：UCI 配置

### 2.1 什么是 UCI

UCI（Unified Configuration Interface）是 OpenWrt 的统一配置接口。
所有配置存储在 `/etc/config/` 目录下，每个文件对应一个配置包。
LuCI 通过 `luci.model.uci` 模块读写 UCI 配置。

### 2.2 创建 QwenPaw 配置包

```bash
cat > /etc/config/qwenpaw << 'EOF'
config qwenpaw 'config'
    option enabled '1'
    option port '19093'
    option data_path '/root/.qwenpaw/'
EOF
```

### 2.3 配置项说明

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `enabled` | bool (0/1) | 1 | 是否启用 QwenPaw 容器 |
| `port` | port (数字) | 19093 | QwenPaw Web 管理端口 |
| `data_path` | string | `/root/.qwenpaw/` | 容器内 QwenPaw 数据目录 |

### 2.4 UCI 读写命令速查

```bash
# 查看全部
uci show qwenpaw

# 读取单个值
uci get qwenpaw.config.port

# 修改
uci set qwenpaw.config.port=19093
uci commit qwenpaw

# 删除
uci delete qwenpaw.config.enabled
uci commit qwenpaw
```

---

## 3. 控制器（Controller）

### 3.1 路径

```
/usr/lib/lua/luci/controller/qwenpaw.lua
```

模块名必须与路径一致：`luci.controller.qwenpaw`

### 3.2 完整源码

```lua
--[[
QwenPaw LuCI Controller v2
]]--

module("luci.controller.qwenpaw", package.seeall)

function index()
    -- 注册主菜单：服务 → QwenPaw（order=25）
    entry({"admin", "services", "qwenpaw"},
        cbi("qwenpaw"),
        _("QwenPaw"), 25).dependent = true

    -- 注册 3 个 API 端点
    entry({"admin", "services", "qwenpaw", "status"},
        call("act_status")).leaf = true

    entry({"admin", "services", "qwenpaw", "control"},
        call("act_control")).leaf = true

    entry({"admin", "services", "qwenpaw", "log"},
        call("act_log")).leaf = true
end
```

**关键函数说明：**

| 函数 | 功能 |
|------|------|
| `index()` | 菜单注册，在 LuCI 启动时自动执行 |
| `entry(path, target, title, order)` | 注册路由 |
| `cbi("qwenpaw")` | 加载 CBI 模型 `model/cbi/qwenpaw.lua` |
| `call("act_xxx")` | 调用本模块函数作为 API 端点 |
| `.dependent = true` | 依赖检查（可省略） |
| `.leaf = true` | 叶子节点（无子页面） |

**`entry()` 参数详解：**

| 参数 | 说明 |
|------|------|
| `{"admin", "services", "qwenpaw"}` | URL 路径 → `/admin/services/qwenpaw` |
| `cbi("qwenpaw")` | 处理目标：CBI 表单渲染 |
| `_("QwenPaw")` | 菜单标题（可翻译） |
| `25` | 排序值，数字越小越靠前 |

### 3.3 API 端点：act_status

返回容器运行状态 JSON，供前端 AJAX 轮询：

```lua
function act_status()
    local http = require "luci.http"
    local sys  = require "luci.sys"
    local json = {}

    -- 1. 检测容器是否 running
    json.running = (sys.call(
        "docker inspect qwenpaw --format '{{.State.Status}}' 2>/dev/null | grep -q running"
    ) == 0)

    -- 2. 从容器启动参数提取端口
    local handle = io.popen(
        "docker inspect qwenpaw --format '{{range .Args}}{{.}} {{end}}' 2>/dev/null"
    )
    if handle then
        local cmd = handle:read("*a"); handle:close()
        local p = cmd:match("%-%-port%s+(%d+)")
        if p then json.port = tonumber(p) end
    end

    -- 3. 获取启动时间
    handle = io.popen(
        "docker inspect qwenpaw --format '{{.State.StartedAt}}' 2>/dev/null"
    )
    if handle then
        local started = handle:read("*a"); handle:close()
        json.started_at = started:match("%S+%s+%S+") or ""
    end

    -- 4. HTTP 健康检查
    if json.running then
        json.http_ok = (sys.call(
            "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:"
            .. json.port .. "/ 2>/dev/null | grep -q 200"
        ) == 0)
    end

    -- 5. 读取 UCI 配置
    local uci = require "luci.model.uci".cursor()
    json.enabled = uci:get("qwenpaw", "config", "enabled") == "1"
    json.config_port = uci:get("qwenpaw", "config", "port") or "19093"

    -- 6. 返回
    http.prepare_content("application/json")
    http.write_json(json)
end
```

返回示例：
```json
{"running":true, "http_ok":true, "port":19093,
 "started_at":"2026-07-14T00:01:23.456Z",
 "enabled":true, "config_port":"19093"}
```

### 3.4 API 端点：act_control

控制容器启停（start/stop/restart）：

```lua
function act_control()
    local http = require "luci.http"
    local sys  = require "luci.sys"
    local action = http.formvalue("action")

    if action == "start" then
        sys.call("docker start qwenpaw 2>/dev/null")
    elseif action == "stop" then
        sys.call("docker stop qwenpaw 2>/dev/null")
    elseif action == "restart" then
        sys.call("docker restart qwenpaw 2>/dev/null")
    end

    http.prepare_content("application/json")
    http.write_json({ok = true, action = action})
end
```

### 3.5 API 端点：act_log

获取容器最近日志：

```lua
function act_log()
    local http = require "luci.http"
    local json = {}
    local tail_lines = 100

    local handle = io.popen(
        "docker logs qwenpaw --tail " .. tail_lines .. " 2>&1"
    )
    if handle then
        local log = handle:read("*a"); handle:close()
        json.log = log
        json.tail = tail_lines
    else
        json.log = "(无法获取日志)"
        json.tail = 0
    end

    http.prepare_content("application/json")
    http.write_json(json)
end
```

---

## 4. CBI 模型（Model）

### 4.1 路径

```
/usr/lib/lua/luci/model/cbi/qwenpaw.lua
```

CBI（Configuration Binding Interface）是 LuCI 的表单框架。

### 4.2 完整源码（v3 最终版）

```lua
--[[
QwenPaw LuCI CBI Model v3
]]--

require("luci.sys")
require("luci.http")
local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

m = Map("qwenpaw", translate("QwenPaw AI 智能体"),
    translate("QwenPaw 是一个强大的 AI 智能体平台，运行在 Docker 容器中。"))

-- ========== 状态面板（SimpleSection + 自定义模板） ==========
m:section(SimpleSection).template = "qwenpaw/qwenpaw_status"

-- ========== 配置区域（TypedSection 绑定 UCI config） ==========
s = m:section(TypedSection, "config")
s.anonymous = true
s.addremove = false

-- 启用/禁用
o = s:option(Flag, "enabled", translate("启用 QwenPaw"),
    translate("勾选后容器将自动运行，取消勾选将停止容器。"))
o.default = 0
o.rmempty = false

-- 端口
o = s:option(Value, "port", translate("Web 管理端口"),
    translate("默认 19093，修改后需重启容器。"))
o.default = 19093
o.datatype = "port"
o.optional = false

-- Web 界面链接（只读 + 自定义渲染）
o = s:option(Value, "_web_link", translate("Web 界面"))
o.template = "cbi/value"
function o.cfgvalue() return "" end
function o.write() end
function o.remove() end
function o.render(self, section, scope)
    local port = uci:get("qwenpaw", "config", "port") or "19093"
    local url = "http://192.168.3.125:" .. port .. "/"
    luci.http.write('<div class="cbi-value">')
    luci.http.write('<label class="cbi-value-title">'
        .. translate("Web 界面") .. '</label>')
    luci.http.write('<div class="cbi-value-field">')
    luci.http.write('<a href="' .. url .. '" target="_blank" '
        .. 'style="font-size:15px;font-weight:bold;color:#19a3ff;'
        .. 'text-decoration:none">')
    luci.http.write(url)
    luci.http.write('</a>')
    luci.http.write('</div></div>')
end

-- 数据路径
o = s:option(Value, "data_path", translate("QwenPaw 配置路径"),
    translate("容器内数据目录，默认为 /root/.qwenpaw/"))
o.default = "/root/.qwenpaw/"
o.optional = false
o.datatype = "string"

-- 重启按钮
o = s:option(Button, "_restart", translate("容器操作"))
o.inputtitle = translate("重启容器")
o.inputstyle = "apply"

-- ========== 日志查看器 ==========
s2 = m:section(SimpleSection, translate("运行日志"),
    translate("实时日志输出，每 5 秒自动刷新。"))
s2.template = "qwenpaw/qwenpaw_log"

-- ========== 保存处理 ==========
local apply = luci.http.formvalue("cbi.submit")
if apply then
    local enabled = luci.http.formvalue("cbid.qwenpaw.config.enabled")
    uci:set("qwenpaw", "config", "enabled", enabled or "0")
    uci:commit("qwenpaw")
    if enabled == "1" then
        luci.sys.call("docker start qwenpaw 2>/dev/null")
    else
        luci.sys.call("docker stop qwenpaw 2>/dev/null")
    end
    luci.http.redirect(luci.dispatcher.build_url("admin", "services", "qwenpaw"))
    return
end

return m
```

### 4.3 关键概念详解

#### SimpleSection vs TypedSection

| 类型 | 用途 | 绑定 UCI |
|------|------|----------|
| `SimpleSection` | 纯展示，自定义模板 | ❌ |
| `TypedSection` | 表单字段，自动映射 UCI | ✅ |

```lua
-- SimpleSection：状态面板、日志查看器（不保存数据）
m:section(SimpleSection, "标题", "描述").template = "路径/模板名"

-- TypedSection：配置表单（自动读写 UCI）
s = m:section(TypedSection, "config")  -- "config" = UCI section type
s.anonymous = true                       -- 单实例
o = s:option(Value, "port", "标签")      -- 自动映射到 option port '...'
```

#### 表单控件对照表

| 控件 | Lua 类 | 渲染效果 | 典型用法 |
|------|--------|----------|----------|
| `Flag` | Checkbox | ☑ 勾选框 | 布尔开关 |
| `Value` | 文本输入框 | 单行文本框 | 端口号、路径 |
| `Button` | 按钮 | 可点击按钮 | 重启容器 |
| `DummyValue` | 只读文本 | 纯文本展示 | 状态信息 |
| `ListValue` | 下拉菜单 | 选择框 | 枚举值选择 |

#### 自定义渲染技巧（Web 链接字段）

对于只读 + 自定义 HTML 的字段，采用三步法：

```lua
-- 第1步：声明 Value 并设置标准模板框架
o = s:option(Value, "_web_link", translate("Web 界面"))
o.template = "cbi/value"

-- 第2步：空实现读写操作（防止保存报错）
function o.cfgvalue() return "" end  -- 不读 UCI
function o.write() end               -- 不写 UCI
function o.remove() end              -- 不允许删除

-- 第3步：完全接管渲染
function o.render(self, section, scope)
    luci.http.write('<div class="cbi-value">')
    luci.http.write('<label class="cbi-value-title">标签</label>')
    luci.http.write('<div class="cbi-value-field">')
    luci.http.write('<a href="..." target="_blank">链接</a>')
    luci.http.write('</div></div>')
end
```

**要点：**
- `_` 前缀（如 `_web_link`）让 CBI 框架识别为非 UCI 字段
- `template = "cbi/value"` 借用标准 CBI value 的 CSS 框架
- `render` 函数内直接输出 HTML 字符串，完全可控

---

## 5. 状态视图模板（Status View）

### 5.1 路径

```
/usr/lib/lua/luci/view/qwenpaw/qwenpaw_status.htm
```

### 5.2 结构设计

```
┌─────────────────────────────────────────────┐
 │  🤖  QwenPaw [运行中]                       │
 │       端口: 19093 | ✅ HTTP 正常             │
 └─────────────────────────────────────────────┘
```

- 灰底圆角卡片（`background:#f8f9fa; border-radius:4px`）
- 左侧机器人 emoji（48px）
- 右侧两行文字：标题+状态标签、详情
- 通过 AJAX 每 10 秒自动更新状态

### 5.3 完整源码

```html
<%-
local uci = require "luci.model.uci".cursor()
-%>

<div class="cbi-section" style="margin-bottom:10px">
    <div class="cbi-section-node">
        <div class="cbi-value"
            style="display:flex;align-items:center;gap:16px;
                   padding:12px 16px;background:#f8f9fa;border-radius:4px">
            <div style="font-size:48px;line-height:1">🤖</div>
            <div style="flex:1">
                <div style="font-size:16px;font-weight:bold;margin-bottom:4px">
                    QwenPaw
                    <span id="qwenpaw_status_badge"
                        style="display:inline-block;padding:2px 10px;
                               border-radius:10px;font-size:12px;
                               font-weight:normal">检测中...</span>
                </div>
                <div style="font-size:13px;color:#666"
                    id="qwenpaw_status_detail">正在获取状态...</div>
            </div>
        </div>
    </div>
</div>

<script type="text/javascript">
(function() {
    var statusUrl = '<%=luci.dispatcher.build_url(
        "admin","services","qwenpaw","status")%>';
    var badge = document.getElementById('qwenpaw_status_badge');
    var detail = document.getElementById('qwenpaw_status_detail');

    function updateStatus() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState == 4 && xhr.status == 200) {
                try {
                    var s = JSON.parse(xhr.responseText);
                    if (s.running) {
                        badge.textContent = '运行中';
                        badge.style.background = '#e8f5e9';
                        badge.style.color = '#2e7d32';
                        detail.innerHTML = '端口: ' + s.port
                            + ' | ' + (s.http_ok ? '✅ HTTP 正常'
                                                : '⚠️ HTTP 未响应');
                    } else {
                        badge.textContent = '已停止';
                        badge.style.background = '#ffebee';
                        badge.style.color = '#c62828';
                        detail.textContent = 'QwenPaw 容器未运行';
                    }
                } catch(e) {
                    badge.textContent = '获取失败';
                    detail.textContent = '无法获取状态信息';
                }
            }
        };
        xhr.open('GET', statusUrl, true);
        xhr.send();
    }
    updateStatus();
    setInterval(updateStatus, 10000);
})();
</script>
```

### 5.4 嵌入 Lua 语法说明

| 语法 | 说明 | 示例 |
|------|------|------|
| `<% lua_code %>` | 执行 Lua 代码 | `<% local x = 1 %>` |
| `<%= expr %>` | 输出表达式（HTML 转义） | `<%=data_path%>` |
| `<%- lua_code -%>` | 执行代码（忽略前后空白） | `<%- local a = 1 -%>` |
| `<%:obj:method()%>` | 对象方法调用并输出 | `<%:self:cfgvalue(s)%>` |

---

## 6. 日志视图模板（Log View）

### 6.1 路径

```
/usr/lib/lua/luci/view/qwenpaw/qwenpaw_log.htm
```

### 6.2 结构设计

```
┌─────────────────────────────────────────────┐
 │  ├─ 2026-07-14 00:01:23 INFO ...           │  ← textarea
 │  │  2026-07-14 00:01:24 INFO ...           │
 │  │  ...                                     │
 │  └─────────────────────────────────────    │
 │  [🔄 刷新]  [🗑️ 清空]  已加载 50 行         │
 └─────────────────────────────────────────────┘
```

### 6.3 完整源码

```html
<%-
local uci = require "luci.model.uci".cursor()
-%>

<div class="cbi-section">
    <div class="cbi-section-node">
        <textarea id="qwenpaw_log_area"
            style="width:100%;height:300px;font-family:'Courier New',monospace;
                   font-size:12px;background:#1e1e1e;color:#d4d4d4;
                   border:1px solid #444;border-radius:4px;padding:8px;
                   resize:vertical" readonly></textarea>
        <div style="margin-top:8px;display:flex;gap:8px;align-items:center">
            <button class="cbi-button cbi-button-apply"
                onclick="qwenpawRefreshLog()">🔄 刷新</button>
            <button class="cbi-button cbi-button-reset"
                onclick="qwenpawClearLog()">🗑️ 清空</button>
            <span id="qwenpaw_log_status"
                style="font-size:12px;color:#999">就绪</span>
        </div>
    </div>
</div>

<script type="text/javascript">
var qwenpaw_log_url = '<%=luci.dispatcher.build_url(
    "admin","services","qwenpaw","log")%>';

function qwenpawRefreshLog() {
    var area = document.getElementById('qwenpaw_log_area');
    var status = document.getElementById('qwenpaw_log_status');
    status.textContent = '加载中...';

    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function() {
        if (xhr.readyState == 4) {
            if (xhr.status == 200) {
                try {
                    var r = JSON.parse(xhr.responseText);
                    if (r.log) { area.value = r.log; area.scrollTop = area.scrollHeight; }
                    var lines = r.log ? r.log.split('\n').length - 1 : 0;
                    status.textContent = '已加载 ' + lines + ' 行 ('
                        + new Date().toLocaleTimeString() + ')';
                } catch(e) { status.textContent = '解析失败'; }
            } else {
                status.textContent = '请求失败 (HTTP ' + xhr.status + ')';
            }
        }
    };
    xhr.open('GET', qwenpaw_log_url, true);
    xhr.send();
}

function qwenpawClearLog() {
    document.getElementById('qwenpaw_log_area').value = '';
    document.getElementById('qwenpaw_log_status').textContent = '已清空';
}

setTimeout(qwenpawRefreshLog, 500);      // 首次加载
setInterval(qwenpawRefreshLog, 5000);    // 每5秒自动刷新
</script>
```

### 6.4 设计要点

| 特性 | 实现方式 |
|------|---------|
| 类终端风格 | `background:#1e1e1e; color:#d4d4d4; font-family:monospace` |
| 自动滚动 | `area.scrollTop = area.scrollHeight` |
| 双重加载 | 页面加载后 500ms 首次 + 每 5 秒自动 |
| 状态提示 | `已加载 N 行 (HH:MM:SS)` |
| 清空功能 | 仅前端清空，不影响容器日志 |

---

## 7. 部署与验证

### 7.1 创建文件（SSH 方式）

```bash
# 创建视图目录
mkdir -p /usr/lib/lua/luci/view/qwenpaw/

# 逐一创建文件
vi /usr/lib/lua/luci/controller/qwenpaw.lua
vi /usr/lib/lua/luci/model/cbi/qwenpaw.lua
vi /usr/lib/lua/luci/view/qwenpaw/qwenpaw_status.htm
vi /usr/lib/lua/luci/view/qwenpaw/qwenpaw_log.htm

# 设置权限（LuCI 文件通常 644）
chmod 644 /usr/lib/lua/luci/controller/qwenpaw.lua
chmod 644 /usr/lib/lua/luci/model/cbi/qwenpaw.lua
chmod 644 /usr/lib/lua/luci/view/qwenpaw/*.htm
```

### 7.2 刷新缓存

```bash
# 重启 uhttpd（Web 服务器）
/etc/init.d/uhttpd restart

# 清除 LuCI 索引缓存
rm -f /tmp/luci-indexcache /tmp/luci-modulecache/*
```

### 7.3 验证方法

```bash
# ① 检查文件完整性
ls -la /usr/lib/lua/luci/controller/qwenpaw.lua
ls -la /usr/lib/lua/luci/model/cbi/qwenpaw.lua
ls -la /usr/lib/lua/luci/view/qwenpaw/

# ② 检查 Lua 语法（仅控制器可独立验证）
lua -e 'require "luci.controller.qwenpaw"' 2>&1
# CBI 模型会报 translate nil（正常，需在 LuCI 环境运行）

# ③ 检查索引缓存
grep -A5 "qwenpaw" /tmp/luci-indexcache.*.json 2>/dev/null

# ④ 浏览器访问
# http://192.168.3.125/cgi-bin/luci/admin/services/qwenpaw

# ⑤ 查看日志
logread | grep -E "luci|uhttpd|qwenpaw" | tail -20
```

### 7.4 常见问题

| 问题 | 原因 | 解决 |
|------|------|------|
| 页面空白 | Lua 语法错误 | `lua -e 'require "module"'` 检查 |
| API 返回 404 | 缓存未刷新 | `rm -f /tmp/luci-*cache*` |
| `translate` nil 错误 | 独立测试 CBI | 通过浏览器验证即可，这是正常现象 |
| 菜单不显示 | 索引缓存旧 | `rm -f /tmp/luci-*cache* && /etc/init.d/uhttpd restart` |

---

## 8. 版本演进历史

### v1 — 初始版
- 控制器 + CBI 模型 + 3 个视图
- 状态面板含 `打开界面` 蓝色大按钮
- 无文件路径配置

### v2 — 改进版
- 新增 `data_path` 文件路径输入
- 日志查看器独立视图 + AJAX 自动刷新
- 移除了 open_button 独立视图

### v3 — 最终版（当前）
- **移除状态面板**中的"打开界面 ▶"按钮
- **移除状态面板**中的"配置路径"显示行
- **新增** Web 界面可点击链接（`_web_link` 自定义渲染）
- 其他配置项保持 v2 原样

**设计原则：** 不重复 — 每个信息只在一个地方展示（配置路径在表单区，状态信息在状态区）
