--!nonstrict
-- ConfigSync.server.lua — OPTIONAL server-side DataStore persistence
-- for Atlas configuration profiles.
--
-- Place in ServerScriptService. Clients call:
--   remote:FireServer("save", Atlas:SerializeConfigs())
-- and receive "load" on join (see AtlasDemo.client.lua footer).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local store = DataStoreService:GetDataStore("AtlasProfiles_v1")

local remote = Instance.new("RemoteEvent")
remote.Name = "AtlasConfigSync"
remote.Parent = ReplicatedStorage

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local ok, json = pcall(store.GetAsync, store, "u_" .. player.UserId)
		if ok and type(json) == "string" then
			remote:FireClient(player, "load", json)
		end
	end)
end)

remote.OnServerEvent:Connect(function(player, action, json)
	if action ~= "save" or type(json) ~= "string" or #json > 60000 then
		return -- basic hygiene: action whitelist + payload size cap
	end
	pcall(store.SetAsync, store, "u_" .. player.UserId, json)
end)
