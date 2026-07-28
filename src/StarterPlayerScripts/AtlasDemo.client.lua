--!nonstrict
-- AtlasDemo.client.lua — Demonstration harness for the Atlas UI library.
-- Runs as a LocalScript in StarterPlayer > StarterPlayerScripts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"):WaitForChild("Library"))

local window = Atlas:CreateWindow({
	Title = "Atlas Demo",
	Size = UDim2.fromOffset(640, 470),
	ToggleKey = Enum.KeyCode.RightShift,
	Resizable = true,
})

--------------------------------------------------------------------
-- Tab 1: General
--------------------------------------------------------------------
local general = window:CreateTab({ Title = "General" })
local movement = general:CreateSection({ Title = "Movement" })

movement:CreateToggle({
	Title = "Auto Sprint",
	Flag = "AutoSprint",
	Default = false,
	Callback = function(on)
		print("[Demo] AutoSprint:", on)
	end,
})

local walkSpeedHandle = movement:CreateSlider({
	Title = "Walk Speed",
	Flag = "WalkSpeed",
	Min = 8, Max = 64, Step = 1, Default = 16,
	Suffix = " st/s",
	Callback = function(v)
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = v
		end
	end,
})

movement:CreateKeybind({
	Title = "Sprint Key",
	Flag = "SprintKey",
	Default = Enum.KeyCode.LeftShift,
	Callback = function(key)
		Atlas:Notify({ Title = "Input", Text = "Sprint key pressed: " .. key.Name, Duration = 2 })
	end,
})

local system = general:CreateSection({ Title = "System" })

system:CreateButton({
	Title = "Print Current Settings",
	Callback = function()
		for _, flag in ipairs({ "AutoSprint", "WalkSpeed", "SprintKey" }) do
			local handle = Atlas:GetFlag(flag)
			if handle then
				print(flag, "=", handle:Get())
			end
		end
	end,
})

system:CreateInput({
	Title = "Quick Note",
	Placeholder = "Type and press Enter",
	Callback = function(text)
		Atlas:Notify({ Title = "Note Saved", Text = text, Duration = 3, AccentToken = "Success" })
	end,
})

--------------------------------------------------------------------
-- Tab 2: Appearance
--------------------------------------------------------------------
local appearance = window:CreateTab({ Title = "Appearance" })
local themeSection = appearance:CreateSection({ Title = "Theme" })

themeSection:CreateDropdown({
	Title = "Color Scheme",
	Options = Atlas:GetThemeNames(),
	Default = "Dark",
	Callback = function(name)
		Atlas:SetTheme(name)
	end,
})

themeSection:CreateSlider({
	Title = "UI Scale",
	Min = 0.75, Max = 1.25, Step = 0.05, Default = 1,
	Callback = function(v)
		Atlas:SetScale(v)
	end,
})

--------------------------------------------------------------------
-- Tab 3: Advanced
--------------------------------------------------------------------
local advanced = window:CreateTab({ Title = "Advanced" })

local inputSection = advanced:CreateSection({ Title = "Inputs", Collapsible = true })

inputSection:CreateSegmented({
	Title = "Targeting Mode",
	Options = { "Hold", "Toggle" },
	Default = "Hold",
	Flag = "TargetingMode",
	Callback = function(v) print("[Demo] Mode:", v) end,
})

inputSection:CreateStepper({
	Title = "Team Size", Min = 1, Max = 8, Step = 1, Default = 4,
	Flag = "TeamSize",
	Callback = function(v) print("[Demo] TeamSize:", v) end,
})

local visualSection = advanced:CreateSection({ Title = "Visuals" })

visualSection:CreateMultiDropdown({
	Title = "Overlay Layers",
	Options = { "Compass", "Damage Log", "Timer", "Score" },
	Default = { "Compass" },
	Flag = "OverlayLayers",
	Callback = function(list) print("[Demo] Layers:", table.concat(list, ", ")) end,
})

visualSection:CreateColorPicker({
	Title = "Accent Tint",
	Default = Color3.fromRGB(94, 106, 242),
	Flag = "AccentTint",
	Callback = function(c) print("[Demo] Tint:", c) end,
})

local progress = visualSection:CreateProgress({ Title = "Load Progress", Default = 0.35 })
visualSection:CreateButton({
	Title = "Simulate Load",
	Callback = function()
		task.spawn(function()
			for i = 0, 100, 5 do
				progress:SetProgress(i / 100)
				task.wait(0.05)
			end
		end)
	end,
})
visualSection:CreateDivider()

-- Tooltip on the Walk Speed slider from the General tab
if walkSpeedHandle and walkSpeedHandle.Root then
	Atlas:AddTooltip(walkSpeedHandle.Root, "Applied to your character's Humanoid on change.")
end

-- Profiles
local profiles = advanced:CreateSection({ Title = "Profiles" })

profiles:CreateInput({ Title = "Profile Name", Flag = "ProfileName", Placeholder = "default" })
profiles:CreateButton({
	Title = "Save Profile",
	Callback = function()
		local nameHandle = Atlas:GetFlag("ProfileName")
		local name = (nameHandle and nameHandle:Get() ~= "") and nameHandle:Get() or "default"
		Atlas:SaveConfig(name)
		Atlas:Notify({ Title = "Profiles", Text = "Saved '" .. name .. "'.", Duration = 2, AccentToken = "Success" })
	end,
})
profiles:CreateButton({
	Title = "Load Profile",
	Callback = function()
		local nameHandle = Atlas:GetFlag("ProfileName")
		local name = (nameHandle and nameHandle:Get() ~= "") and nameHandle:Get() or "default"
		if not Atlas:LoadConfig(name) then
			Atlas:Alert({ Title = "Profiles", Text = "No profile named '" .. name .. "'.", OkLabel = "OK" })
		end
	end,
})
profiles:CreateButton({
	Title = "Delete All Profiles",
	Callback = function()
		Atlas:Prompt({
			Title = "Delete Profiles",
			Text = "Remove every stored profile for this session?",
			Buttons = { "Cancel", "Delete" },
			Callback = function(choice)
				if choice == "Delete" then
					for _, n in ipairs(Atlas:GetConfigs()) do
						Atlas:DeleteConfig(n)
					end
					Atlas:Notify({ Title = "Profiles", Text = "All profiles deleted.", Duration = 2, AccentToken = "Danger" })
				end
			end,
		})
	end,
})

--------------------------------------------------------------------
-- Tab 4: About
--------------------------------------------------------------------
local about = window:CreateTab({ Title = "About" })
local info = about:CreateSection({ Title = "Atlas" })

info:CreateLabel({
	Text = "Atlas is a zero-asset, component-based interface library built entirely "
		.. "from Instance graphs. RichText is <b>supported</b> in labels.",
	Dim = false,
})

info:CreateButton({
	Title = "Show Notification",
	Callback = function()
		Atlas:Notify({
			Title = "Atlas",
			Text = "Notifications stack, fade, and auto-dismiss.",
			Duration = 4,
		})
	end,
})

--------------------------------------------------------------------
-- Command palette registrations (Ctrl+K)
--------------------------------------------------------------------
Atlas:RegisterCommand({
	Name = "Reset Walk Speed", Category = "Movement",
	Callback = function()
		local h = Atlas:GetFlag("WalkSpeed")
		if h then
			h:Set(16)
		end
	end,
})
Atlas:RegisterCommand({
	Name = "Switch to Dark Theme", Category = "Appearance",
	Callback = function() Atlas:SetTheme("Dark") end,
})
Atlas:RegisterCommand({
	Name = "Switch to Light Theme", Category = "Appearance",
	Callback = function() Atlas:SetTheme("Light") end,
})
Atlas:RegisterCommand({
	Name = "Hide Interface", Category = "System",
	Callback = function() window:SetVisible(false) end,
})

--------------------------------------------------------------------
-- Optional cloud persistence (requires ConfigSync server script).
-- Uncomment to enable:
--------------------------------------------------------------------
-- local remote = ReplicatedStorage:WaitForChild("AtlasConfigSync")
-- remote.OnClientEvent:Connect(function(action, json)
-- 	if action == "load" and Atlas:DeserializeConfigs(json) then
-- 		Atlas:Notify({ Title = "Profiles", Text = "Cloud profiles restored.", Duration = 3 })
-- 	end
-- end)
-- Call after changes: remote:FireServer("save", Atlas:SerializeConfigs())
