--[[
QwenPaw LuCI Controller v2
Provides configuration page and status/log API for QwenPaw Docker container
]]--

module("luci.controller.qwenpaw", package.seeall)

function index()
	entry({"admin", "services", "qwenpaw"},
		cbi("qwenpaw"),
		_("QwenPaw"), 25).dependent = true

	entry({"admin", "services", "qwenpaw", "status"},
		call("act_status")).leaf = true

	entry({"admin", "services", "qwenpaw", "control"},
		call("act_control")).leaf = true

	entry({"admin", "services", "qwenpaw", "log"},
		call("act_log")).leaf = true
end

function act_status()
	local http = require "luci.http"
	local sys  = require "luci.sys"
	local json = {}

	json.running = (sys.call("docker inspect qwenpaw --format '{{.State.Status}}' 2>/dev/null | grep -q running") == 0)
	json.http_ok = false
	json.port = 19093
	json.started_at = ""
	json.enabled = false
	json.config_port = "19093"

	local handle = io.popen("docker inspect qwenpaw --format '{{range .Args}}{{.}} {{end}}' 2>/dev/null")
	if handle then
		local cmd = handle:read("*a")
		handle:close()
		local p = cmd:match("%-%-port%s+(%d+)")
		if p then json.port = tonumber(p) end
	end

	handle = io.popen("docker inspect qwenpaw --format '{{.State.StartedAt}}' 2>/dev/null")
	if handle then
		local started = handle:read("*a")
		handle:close()
		json.started_at = started:match("%S+%s+%S+") or ""
	end

	if json.running then
		json.http_ok = (sys.call("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:" .. json.port .. "/ 2>/dev/null | grep -q 200") == 0)
	end

	local uci = require "luci.model.uci".cursor()
	json.enabled = uci:get("qwenpaw", "config", "enabled") == "1"
	json.config_port = uci:get("qwenpaw", "config", "port") or "19093"
	json.data_path = uci:get("qwenpaw", "config", "data_path") or "/root/.qwenpaw/"

	http.prepare_content("application/json")
	http.write_json(json)
end

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

function act_log()
	local http = require "luci.http"
	local json = {}
	local tail_lines = 100

	-- Try to get logs from Docker container
	local handle = io.popen("docker logs qwenpaw --tail " .. tail_lines .. " 2>&1")
	if handle then
		local log = handle:read("*a")
		handle:close()
		json.log = log
		json.tail = tail_lines
	else
		json.log = "(无法获取日志)"
		json.tail = 0
	end

	http.prepare_content("application/json")
	http.write_json(json)
end
