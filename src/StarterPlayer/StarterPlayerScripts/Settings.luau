-- Client settings kept on the account: a JSON object the server stores and
-- sends back on login (the UiSettings attribute). get/set with dotted keys,
-- writes are batched and sent a second after the last change.
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Opcodes = require(ReplicatedStorage.Shared.Opcodes)
local player = Players.LocalPlayer

local Settings = {}
local data = {}
local ready = false
local waiting: { () -> () } = {}
local pending = false

local function send()
	local netSend = script.Parent:FindFirstChild("NetSend")
	if netSend then
		netSend:Fire(Opcodes.CMSG_SAVE_SETTINGS, { Settings = data })
	end
end

function Settings.get(key: string, default)
	local value = data[key]
	return if value == nil then default else value
end

function Settings.set(key: string, value)
	data[key] = value
	if not pending then
		pending = true
		task.delay(1, function()
			pending = false
			send()
		end)
	end
end

-- fn runs once the account's settings arrived (or now, if they have)
function Settings.onReady(fn: () -> ())
	if ready then
		fn()
	else
		table.insert(waiting, fn)
	end
end

local function load()
	local raw = player:GetAttribute("UiSettings")
	if not raw then
		return
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	data = if ok and typeof(value) == "table" then value else {}
	ready = true
	for _, fn in waiting do
		task.spawn(fn)
	end
	waiting = {}
end
player:GetAttributeChangedSignal("UiSettings"):Connect(load)
load()

return Settings
