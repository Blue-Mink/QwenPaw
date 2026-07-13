--[[
QwenPaw LuCI CBI Model v3
]]--

require("luci.sys")
require("luci.http")
local fs = require "nixio.fs"
local uci = require "luci.model.uci".cursor()

m = Map("qwenpaw", translate("QwenPaw AI 智能体"),
	translate("QwenPaw 是一个强大的 AI 智能体平台，运行在 Docker 容器中。支持多智能体协作、工具调用、QQ 频道机器人等。"))

-- Status section
m:section(SimpleSection).template = "qwenpaw/qwenpaw_status"

-- Config section
s = m:section(TypedSection, "config")
s.anonymous = true
s.addremove = false

-- Enable/Disable
o = s:option(Flag, "enabled", translate("启用 QwenPaw"),
	translate("勾选后 QwenPaw 容器将自动运行，取消勾选将停止容器。"))
o.default = 0
o.rmempty = false

-- Port
o = s:option(Value, "port", translate("Web 管理端口"),
	translate("QwenPaw Web 界面访问端口，默认 19093。修改后需重启容器生效。"))
o.default = 19093
o.datatype = "port"
o.optional = false

-- Web UI link (clickable)
o = s:option(Value, "_web_link", translate("Web 界面"))
o.template = "cbi/value"
function o.cfgvalue() return "" end
function o.write() end
function o.remove() end
function o.render(self, section, scope)
	local port = uci:get("qwenpaw", "config", "port") or "19093"
	local url = "http://$(hostname -I | awk '{print $1}')" .. ":" .. port .. "/"
	-- 动态检测本机 IP（取第一个非回环地址）
	local handle = io.popen("hostname -I 2>/dev/null")
	if handle then local ip = handle:read("*a"); handle:close(); url = "http://" .. (ip:match("%S+") or "旁路由IP") .. ":" .. port .. "/" end
	luci.http.write('<div class="cbi-value">')
	luci.http.write('<label class="cbi-value-title">' .. translate("Web 界面") .. '</label>')
	luci.http.write('<div class="cbi-value-field">')
	luci.http.write('<a href="' .. url .. '" target="_blank" style="font-size:15px;font-weight:bold;color:#19a3ff;text-decoration:none">')
	luci.http.write(url)
	luci.http.write('</a>')
	luci.http.write('</div></div>')
end

-- QwenPaw data path
o = s:option(Value, "data_path", translate("QwenPaw 配置路径"),
	translate("QwenPaw 数据目录在容器内的路径，默认为 /root/.qwenpaw/"))
o.default = "/root/.qwenpaw/"
o.optional = false
o.datatype = "string"

-- Restart button
o = s:option(Button, "_restart", translate("容器操作"))
o.inputtitle = translate("重启容器")
o.inputstyle = "apply"

-- Log viewer section
s2 = m:section(SimpleSection, translate("运行日志"),
	translate("QwenPaw 容器实时日志输出，每 5 秒自动刷新。"))
s2.template = "qwenpaw/qwenpaw_log"

-- Handle save
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
