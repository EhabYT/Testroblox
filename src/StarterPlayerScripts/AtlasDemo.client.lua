--!nonstrict
-- AtlasDemo.client.lua — Demonstration harness for Atlas v2 (device-adaptive).
-- Runs as a LocalScript in StarterPlayer > StarterPlayerScripts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"):WaitForChild("Library"))

local about -- forward: the UI Settings toggle below references Tab 4

local window = Atlas:CreateWindow({
	Title = "Atlas Demo v" .. Atlas:GetVersion(),
	-- no Size: v2 picks the menu size per device class (phone/tablet/desktop)
	ToggleKey = Enum.KeyCode.RightShift,
	GamepadToggleKey = Enum.KeyCode.ButtonL3, -- controllers (console has no RightShift)
	ToggleButton = true, -- floating menu toggler on every platform (drag to move)
	Resizable = true,
	RememberLayout = true, -- window position & size ride along in every profile
	SettingsTab = "UI Settings", -- ⚙ gear button in the title bar jumps here
	LoadingScreen = { -- plays once at startup; window reveals when it ends
		Title = "Atlas",
		Subtitle = "Component UI Library",
		Duration = 2.2,
		Steps = { "Loading theme engine", "Building components", "Wiring services", "Ready" },
	},
})

-- Close confirmation: the × button asks first (RightShift toggle stays instant).
window:SetCloseHandler(function()
	Atlas:Prompt({
		Title = "Close Menu",
		Text = "Hide the interface? RightShift brings it back.",
		Buttons = { "Cancel", "Close" },
		Callback = function(choice)
			if choice == "Close" then
				window:SetVisible(false)
			end
		end,
	})
	return false -- the prompt decides asynchronously
end)

-- Shared item factory for the context-menu demos (Advanced tab). A function
-- keeps the menu dynamic — it is re-built every time it opens.
local function demoMenuItems()
	return {
		{ Name = "Center Window", Callback = function() window:Center() end },
		{ Name = "Jump to Tab", Submenu = { -- one level of nesting
			{ Name = "General", Callback = function() window:SelectTab("General") end },
			{ Name = "UI Settings", Callback = function() window:SelectTab("UI Settings") end },
			{ Name = "Components", Callback = function() window:SelectTab("Components") end },
			{ Name = "Advanced", Callback = function() window:SelectTab("Advanced") end },
			{ Name = "About", Callback = function() window:SelectTab("About") end },
		} },
		{ Name = "Hide Interface", Callback = function() window:SetVisible(false) end },
		{ Name = "Disabled Action", Disabled = true },
		"separator",
		{ Name = "Reset Size & Center", Danger = true, Callback = function()
			window:SetSize(720, 520) -- clamped per device class
			window:Center()
			Atlas:Notify({ Title = "Layout", Text = "Window size reset and centered.", Duration = 2 })
		end },
	}
end

--------------------------------------------------------------------
-- Tab 1: General
--------------------------------------------------------------------
local general = window:CreateTab({ Title = "General" })

local navSection = general:CreateSection({ Title = "Navigation" })
navSection:CreateButton({
	Title = "Open UI Settings →",
	Callback = function() window:SelectTab("UI Settings") end,
})

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
-- Tab 2: UI Settings — live control over the interface itself
--------------------------------------------------------------------
local appearance = window:CreateTab({ Title = "UI Settings" })

local presetSection = appearance:CreateSection({ Title = "Presets" })

-- Accent dot per theme next to every option name.
local schemeColors = {}
for _, name in ipairs(Atlas:GetThemeNames()) do
	local theme = Atlas.Theme.Tokens[name]
	schemeColors[name] = theme and theme.Accent
end

presetSection:CreateDropdown({
	Title = "Color Scheme",
	Options = Atlas:GetThemeNames(),
	OptionColors = schemeColors,
	Default = Atlas:GetThemeName(),
	Callback = function(name)
		Atlas:SetTheme(name)
	end,
})

presetSection:CreateButton({
	Title = "Cycle Theme →",
	Callback = function()
		local names = Atlas:GetThemeNames()
		local current = table.find(names, Atlas:GetThemeName()) or 0
		local nextName = names[current % #names + 1]
		Atlas:SetTheme(nextName)
		Atlas:Notify({ Title = "Theme", Text = "Switched to " .. nextName .. ".", Duration = 1.5 })
	end,
})

presetSection:CreateDropdown({
	Title = "Font Family",
	Options = { "Gotham", "Arial", "Source Sans", "Code" },
	Default = "Gotham",
	Callback = function(choice)
		local packs = {
			Gotham = { Enum.Font.Gotham, Enum.Font.GothamMedium, Enum.Font.GothamBold },
			Arial = { Enum.Font.Arial, Enum.Font.Arial, Enum.Font.ArialBold },
			["Source Sans"] = { Enum.Font.SourceSans, Enum.Font.SourceSans, Enum.Font.SourceSansBold },
			Code = { Enum.Font.Code, Enum.Font.Code, Enum.Font.Code },
		}
		local pack = packs[choice]
		if pack then
			Atlas:SetToken("Font", pack[1])
			Atlas:SetToken("FontMedium", pack[2])
			Atlas:SetToken("FontBold", pack[3])
			Atlas:Notify({
				Title = "Fonts",
				Text = "'" .. choice .. "' applied live to every element.",
				Duration = 3,
			})
		end
	end,
})

presetSection:CreateSlider({
	Title = "Animation Speed",
	Min = 0.5, Max = 2, Step = 0.1, Default = 1,
	Flag = "AnimSpeed",
	Callback = function(mult)
		Atlas.Utility.SetAnimSpeed(mult)
	end,
})

local colorSection = appearance:CreateSection({ Title = "Colors (Live)", Collapsible = true, Flag = "Sec_Colors" })

for _, info in ipairs({
	{ "Accent", "Accent" }, { "Background", "Background" }, { "Surface", "Surface" },
	{ "Surface Alt", "SurfaceAlt" }, { "Hover", "Hover" }, { "Stroke", "Stroke" },
	{ "Text", "Text" }, { "Text Dim", "TextDim" },
}) do
	colorSection:CreateColorPicker({
		Title = info[1],
		ThemeToken = info[2], -- swatch follows ResetTheme/scheme switches automatically
		Flag = "Token_" .. info[2],
		Callback = function(color)
			Atlas:SetToken(info[2], color)
		end,
	})
end

local layoutSection = appearance:CreateSection({ Title = "Layout" })

layoutSection:CreateSegmented({
	Title = "Sidebar Side",
	Options = { "Left", "Right" },
	Default = "Left",
	Width = 150,
	Callback = function(side)
		window:SetSidebarPosition(side:lower()) -- accent rail follows
	end,
})

layoutSection:CreateSlider({
	Title = "UI Scale",
	Min = 0.75, Max = 1.5, Step = 0.05, Default = 1,
	Flag = "UiScale",
	Callback = function(v) Atlas:SetScale(v) end,
})

layoutSection:CreateSlider({
	Title = "Sidebar Width",
	Min = 96, Max = 180, Step = 2, Default = 150,
	Callback = function(v) window:SetSidebarWidth(v) end,
})

layoutSection:CreateSlider({
	Title = "Corner Radius",
	Min = 0, Max = 14, Step = 1, Default = 8,
	Callback = function(v) Atlas:SetToken("Corner", UDim.new(0, v)) end,
})

local behaviorSection = appearance:CreateSection({ Title = "Behavior" })

behaviorSection:CreateSlider({
	Title = "Window Transparency",
	Min = 0, Max = 0.6, Step = 0.05, Default = 0,
	Callback = function(t) window:SetTransparency(t) end,
})

behaviorSection:CreateSegmented({
	Title = "Notifications Side",
	Options = { "Right", "Left" },
	Default = "Right",
	Width = 150,
	Callback = function(side) Atlas:SetNotifySide(side) end,
})

behaviorSection:CreateToggle({
	Title = "Menu Toggle Button",
	Default = true,
	Flag = "ToggleButton",
	Callback = function(on) window:SetToggleButton(on) end,
})

behaviorSection:CreateKeybind({
	Title = "Menu Toggle Key",
	Default = Enum.KeyCode.RightShift,
	Flag = "MenuToggleKey",
	Callback = function(key)
		window:SetToggleKey(key) -- live rebind, no rebuild needed
	end,
})

behaviorSection:CreateToggle({
	Title = "Show About Tab",
	Default = true,
	Flag = "ShowAboutTab",
	Callback = function(on)
		if about then
			about:SetVisible(on) -- sidebar entry + page hide together
		end
	end,
})

behaviorSection:CreateToggle({
	Title = "Watermark (FPS + Ping)",
	Default = true,
	Flag = "Watermark",
	Callback = function(on) Atlas:SetWatermarkVisible(on) end,
})
Atlas:SetWatermark({ Text = "Atlas Demo", ShowFPS = true, ShowPing = true, RememberLayout = true })

behaviorSection:CreateToggle({
	Title = "Blur Background",
	Default = false,
	Flag = "BlurBackdrop",
	Callback = function(on) window:SetBlurBackdrop(on) end,
})

local shareSection = appearance:CreateSection({ Title = "Share Theme", Collapsible = true })

local themeJsonBox
shareSection:CreateButton({
	Title = "Export Current Theme",
	Callback = function()
		local json = Atlas:ExportTheme()
		if json and themeJsonBox then
			themeJsonBox:Set(json)
			Atlas:Notify({
				Title = "Theme Exported",
				Text = "JSON copied into the box below — select it and Ctrl+C to share.",
				Duration = 4,
				AccentToken = "Success",
			})
		else
			Atlas:Notify({ Title = "Export Failed", Text = "Theme is not serializable.", Duration = 4, AccentToken = "Danger" })
		end
	end,
})

themeJsonBox = shareSection:CreateInput({
	Title = "Theme JSON",
	Placeholder = "Export fills this box — or paste JSON here",
})

shareSection:CreateButton({
	Title = "Import Theme from Box",
	Callback = function()
		local text = themeJsonBox and themeJsonBox:Get() or ""
		if text == "" then
			Atlas:Notify({ Title = "Import", Text = "Box is empty — paste theme JSON first.", Duration = 3 })
			return
		end
		if Atlas:ImportTheme(text) then
			Atlas:Notify({ Title = "Theme Imported", Text = "Registered and applied.", Duration = 3, AccentToken = "Success" })
		else
			Atlas:Notify({ Title = "Import Failed", Text = "That is not valid Atlas theme JSON.", Duration = 4, AccentToken = "Danger" })
		end
	end,
})

local resetSection = appearance:CreateSection({ Title = "Reset" })

resetSection:CreateButton({
	Title = "Reset Theme to Defaults",
	Callback = function()
		Atlas:Prompt({
			Title = "Reset Theme",
			Text = "Restore the active color scheme to its factory values?",
			Buttons = { "Cancel", "Reset" },
			Callback = function(choice)
				if choice == "Reset" then
					Atlas:ResetTheme()
					Atlas:Notify({ Title = "Reset", Text = "Theme restored to defaults.", Duration = 3, AccentToken = "Success" })
				end
			end,
		})
	end,
})

--------------------------------------------------------------------
-- Tab 3: New Components (v2.14.0)
--------------------------------------------------------------------
local components = window:CreateTab({ Title = "Components" })

-- Switch (labeled two-state, different from Toggle)
local switchSection = components:CreateSection({ Title = "Switch" })
switchSection:CreateSwitch({
	Title = "Notifications",
	OnText = "On",
	OffText = "Off",
	Default = true,
	Flag = "NotifySwitch",
	Callback = function(on)
		print("[Demo] Notifications:", on)
		Atlas:SetStatusBarText(on and "Notifications enabled" or "Notifications muted")
	end,
})
switchSection:CreateSwitch({
	Title = "Game Mode",
	OnText = "PvP",
	OffText = "PvE",
	Default = false,
	Flag = "GameMode",
	Callback = function(pvp) print("[Demo] Mode:", pvp and "PvP" or "PvE") end,
})

-- TextArea (multi-line input)
local textSection = components:CreateSection({ Title = "TextArea" })
textSection:CreateTextArea({
	Title = "Bio / Description",
	Placeholder = "Write something here...\nSupports multiple lines.",
	Height = 70,
	MaxLength = 200,
	Flag = "UserBio",
	Callback = function(text)
		print("[Demo] Bio:", text)
	end,
})
textSection:CreateTextArea({
	Title = "Lua Snippet",
	Placeholder = "-- paste code here",
	Height = 90,
	Callback = function(text) print("[Demo] Code:", text) end,
})

-- Range Slider (dual-thumb)
local rangeSection = components:CreateSection({ Title = "Range Slider" })
rangeSection:CreateRangeSlider({
	Title = "Level Range",
	Min = 1, Max = 100, Step = 1,
	DefaultMin = 10, DefaultMax = 50,
	Flag = "LevelRange",
	Callback = function(lo, hi)
		print("[Demo] Level range:", lo, "-", hi)
	end,
})
rangeSection:CreateRangeSlider({
	Title = "Price Filter",
	Min = 0, Max = 1000, Step = 25,
	DefaultMin = 100, DefaultMax = 750,
	Suffix = "$",
	Callback = function(lo, hi)
		print("[Demo] Price:", lo, "-", hi)
	end,
})

-- RadioGroup (exclusive vertical radios)
local radioSection = components:CreateSection({ Title = "Radio Group" })
radioSection:CreateRadioGroup({
	Title = "Difficulty",
	Options = { "Easy", "Normal", "Hard", "Nightmare" },
	Default = "Normal",
	Flag = "Difficulty",
	Callback = function(v)
		print("[Demo] Difficulty:", v)
		Atlas:Notify({ Title = "Difficulty", Text = "Set to " .. v .. ".", Duration = 2 })
	end,
})
radioSection:CreateRadioGroup({
	Title = "Region",
	Options = { "US East", "US West", "Europe", "Asia" },
	Default = "Europe",
	Flag = "Region",
	Callback = function(v) print("[Demo] Region:", v) end,
})

-- Chip / Tag List
local chipSection = components:CreateSection({ Title = "Chip List" })
chipSection:CreateChipList({
	Title = "Filters",
	Default = { "Online", "Verified" },
	Placeholder = "Add filter…",
	MaxTags = 8,
	Flag = "Filters",
	Callback = function(tags)
		print("[Demo] Filters:", table.concat(tags, ", "))
	end,
})
chipSection:CreateChipList({
	Title = "Favorite Colors",
	Default = { "Red", "Blue", "Green" },
	Placeholder = "Add color…",
	EmptyText = "No favorites yet",
	Callback = function(tags) print("[Demo] Colors:", table.concat(tags, ", ")) end,
})

-- Accordion (collapsible content panels)
local accordionSection = components:CreateSection({ Title = "Accordion" })
accordionSection:CreateAccordion({
	Title = "FAQ",
	DefaultOpen = 1,
	Items = {
		{ Title = "What is Atlas?", Text = "A zero-asset, component-based UI library for Roblox built entirely from Instance graphs. No images, no models, no dependencies." },
		{ Title = "How do I install it?", Text = "Option A: paste the 4 modules into ReplicatedStorage. Option B: use Rojo. Option C: single-file build from releases/." },
		{ Title = "Is it free?", Text = "Yes — MIT licensed. Use it in any project, commercial or personal." },
		{ Title = "Does it work on mobile?", Text = "Absolutely. Atlas adapts to phones, tablets, desktops and consoles automatically via the Device module." },
	},
})

-- Breadcrumb
local breadSection = components:CreateSection({ Title = "Breadcrumb" })
local breadcrumb = breadSection:CreateBreadcrumb({
	Items = { "Home", "Settings", "UI Settings", "Colors" },
	Callback = function(crumb, index)
		Atlas:Notify({ Title = "Navigation", Text = "You clicked: " .. crumb .. " (level " .. index .. ")", Duration = 2 })
	end,
})
breadSection:CreateButton({
	Title = "Change Path",
	Callback = function()
		breadcrumb:SetItems({ "Home", "Game", "Lobby", "Queue" })
		Atlas:Notify({ Title = "Breadcrumb", Text = "Path updated.", Duration = 1.5 })
	end,
})

-- Rating (star selector)
local ratingSection = components:CreateSection({ Title = "Rating" })
ratingSection:CreateRating({
	Title = "Experience",
	Default = 3,
	Flag = "ExpRating",
	Callback = function(stars)
		local labels = { "Terrible", "Bad", "OK", "Good", "Excellent" }
		local label = labels[stars] or "Not rated"
		Atlas:SetStatusBarText("Rating: " .. stars .. "/5 — " .. label)
	end,
})
ratingSection:CreateRating({
	Title = "Difficulty",
	Max = 4,
	Default = 2,
	Flag = "DiffRating",
	Callback = function(v) print("[Demo] Difficulty rating:", v) end,
})

-- TimePicker
local timeSection = components:CreateSection({ Title = "Time Picker" })
timeSection:CreateTimePicker({
	Title = "Alarm Time",
	DefaultHour = 8,
	DefaultMinute = 30,
	Use24Hour = true,
	Flag = "AlarmTime",
	Callback = function(h, m)
		print(("[Demo] Alarm: %02d:%02d"):format(h, m))
	end,
})
timeSection:CreateTimePicker({
	Title = "Event Start",
	DefaultHour = 14,
	DefaultMinute = 0,
	MinuteStep = 15,
	Use24Hour = false,
	Callback = function(h, m)
		print(("[Demo] Event: %02d:%02d"):format(h, m))
	end,
})

-- Toast Queue demo
local queueSection = components:CreateSection({ Title = "Toast Queue" })
queueSection:CreateLabel({
	Text = "Plays multiple toasts sequentially, each after the previous one dismisses.",
})
queueSection:CreateButton({
	Title = "Play 4-Toast Sequence",
	Callback = function()
		Atlas:QueueNotifications({
			{ Title = "Step 1", Text = "Connecting to server…", Duration = 1.5, AccentToken = "Accent" },
			{ Title = "Step 2", Text = "Downloading assets…", Duration = 1.5 },
			{ Title = "Step 3", Text = "Building world…", Duration = 1.5 },
			{ Title = "Step 4", Text = "Ready to play!", Duration = 2, AccentToken = "Success" },
		}, {
			Gap = 0.2,
			OnComplete = function()
				Atlas:SetStatusBarText("Toast queue finished.")
			end,
		})
	end,
})

-- Shortcuts & Status Bar demo
local serviceSection = components:CreateSection({ Title = "Services" })
serviceSection:CreateLabel({
	Text = "Keyboard shortcuts: Ctrl+D toggles the status bar. "
		.. "Ctrl+N sends a test notification.",
})
serviceSection:CreateToggle({
	Title = "Status Bar",
	Default = true,
	Flag = "StatusBarVisible",
	Callback = function(on) Atlas:SetStatusBarVisible(on) end,
})
serviceSection:CreateButton({
	Title = "Update Status Text",
	Callback = function()
		Atlas:SetStatusBarText("Updated at " .. os.date("%H:%M:%S"))
	end,
})
serviceSection:CreateLabel({
	Text = "Shortcuts registered: " .. tostring(#Atlas:GetShortcuts())
		.. " (updates after registrations below).",
})

--------------------------------------------------------------------
-- Tab 4: Advanced
--------------------------------------------------------------------
local advanced = window:CreateTab({ Title = "Advanced" })

local inputSection = advanced:CreateSection({ Title = "Inputs", Collapsible = true, Flag = "Sec_Inputs" })

inputSection:CreateSegmented({
	Title = "Targeting Mode",
	Options = { "Hold", "Toggle" },
	Default = "Hold",
	Flag = "TargetingMode",
	Callback = function(v) print("[Demo] Mode:", v) end,
})

inputSection:CreateInput({
	Title = "Fov (numeric)",
	Placeholder = "0 – 120, Enter commits",
	Numeric = true, Min = 0, Max = 120,
	Default = "70",
	Flag = "FovInput",
	Callback = function(v) print("[Demo] FOV:", v) end,
})

inputSection:CreateDropdown({
	Title = "Channel (searchable)",
	Options = { "General", "Trading", "Looking For Group", "Help", "Off Topic",
		"Announcements", "Events", "Clips", "Guides", "Bugs",
		"Suggestions", "Competitive", "Casual", "Roleplay", "Fan Art", "Dev Log" },
	Default = "General",
	Searchable = true,
	Flag = "Channel",
	Width = 170,
	Callback = function(v) print("[Demo] Channel:", v) end,
})

inputSection:CreateStepper({
	Title = "Team Size", Min = 1, Max = 8, Step = 1, Default = 4,
	Flag = "TeamSize",
	Callback = function(v) print("[Demo] TeamSize:", v) end,
})

local visualSection = advanced:CreateSection({ Title = "Visuals" })

visualSection:CreateMultiDropdown({
	Title = "Overlay Layers (searchable)",
	Options = { "Compass", "Damage Log", "Timer", "Score", "Kill Feed", "Minimap",
		"Ping Graph", "FPS Counter", "Coordinates", "Spectators", "Objectives", "Chat" },
	Default = { "Compass" },
	Searchable = true,
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
-- Indeterminate indicator for operations with unknown duration.
local queue = visualSection:CreateProgress({ Title = "Queue (indeterminate)", Marquee = true })
local queueOn = true
visualSection:CreateButton({
	Title = "Toggle Marquee",
	Callback = function()
		queueOn = not queueOn
		queue:SetMarquee(queueOn) -- off: back to the determinate bar
	end,
})
visualSection:CreateDivider()

-- Tooltip on the Walk Speed slider from the General tab
if walkSpeedHandle and walkSpeedHandle.Root then
	Atlas:AddTooltip(walkSpeedHandle.Root, "Applied to your character's Humanoid on change.")
end

-- Notification history: the library remembers the last 15 toasts.
local historySection = advanced:CreateSection({ Title = "Recent Notifications" })
local historyParagraph = historySection:CreateParagraph({
	Title = "Last toasts",
	Text = "(press Refresh)",
})
historySection:CreateButton({
	Title = "Refresh History",
	Callback = function()
		local lines = {}
		local history = Atlas:GetNotificationHistory()
		for i = 1, math.min(#history, 6) do
			local n = history[i]
			table.insert(lines, ("• [%s] %s — %s"):format(os.date("%H:%M:%S", n.At), n.Title, n.Text))
		end
		historyParagraph:SetText(#lines > 0 and table.concat(lines, "\n") or "(no notifications yet)")
	end,
})
historySection:CreateButton({
	Title = "Open Notification Center",
	Callback = function() Atlas:ShowNotificationCenter() end, -- also in the FAB menu
})

-- Context menu: click-to-open at the cursor, or right-click / long-press the
-- button itself (attached menu, re-built on every open).
local ctx = advanced:CreateSection({ Title = "Context Menu" })
local ctxButton = ctx:CreateButton({
	Title = "Show Context Menu",
	Callback = function()
		-- Long-press already opened the menu: skip the release-click re-open.
		if ctxButton.Root and ctxButton.Root:GetAttribute("AtlasSuppressClick") then
			return
		end
		Atlas:ContextMenu({ Items = demoMenuItems() }) -- Position nil = mouse
	end,
})
Atlas:AddContextMenu(ctxButton.Root, demoMenuItems) -- right-click / long-press
ctx:CreateLabel({
	Text = "Hint: the floating ≡ menu button has its own quick menu too — "
		.. "right-click or long-press it (works while the window is hidden).",
})

-- Profiles
local profiles = advanced:CreateSection({ Title = "Profiles" })

-- Header bubble: how many profiles are currently stored.
local function refreshProfileBadge()
	profiles:SetBadge(#Atlas:GetConfigs())
end
refreshProfileBadge()

profiles:CreateLabel({
	Text = "Window position & size are captured too (RememberLayout). "
		.. "Move or resize the window, then save a profile.",
})
profiles:CreateInput({ Title = "Profile Name", Flag = "ProfileName", Placeholder = "default" })
profiles:CreateButton({
	Title = "Save Profile…",
	Callback = function()
		Atlas:Prompt({ -- dialog with a text field: Enter = Save
			Title = "Save Profile",
			Text = "Name this profile:",
			Input = true,
			Placeholder = "default",
			Buttons = { "Cancel", "Save" },
			Callback = function(choice, text)
				if choice == "Save" then
					local name = (type(text) == "string" and text ~= "") and text or "default"
					Atlas:SaveConfig(name)
					refreshProfileBadge()
					Atlas:Notify({ Title = "Profiles", Text = "Saved '" .. name .. "'.", Duration = 2, AccentToken = "Success" })
				end
			end,
		})
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
profiles:CreateToggle({
	Title = "Autosave (every 15 s)",
	Default = false,
	Flag = "Autosave",
	Callback = function(on)
		if on then
			local nameHandle = Atlas:GetFlag("ProfileName")
			local name = (nameHandle and nameHandle:Get() ~= "") and nameHandle:Get() or "default"
			Atlas:SetAutoSave(name, 15)
			Atlas:Notify({ Title = "Profiles", Text = "Autosaving to '" .. name .. "' every 15 s.", Duration = 3 })
			advanced:SetBadge("A") -- tab bubble while autosave is live
		else
			Atlas:SetAutoSave(nil)
			advanced:SetBadge(nil)
		end
	end,
})

profiles:CreateButton({
	Title = "Export Profiles (JSON)",
	Callback = function()
		Atlas:Prompt({
			Title = "Export Profiles",
			Text = "Copy this JSON to keep your profiles (Ctrl+A, Ctrl+C):",
			Input = true,
			Default = Atlas:SerializeConfigs(),
			Buttons = { "Done" },
		})
	end,
})

profiles:CreateButton({
	Title = "Import Profiles (JSON)",
	Callback = function()
		Atlas:Prompt({
			Title = "Import Profiles",
			Text = "Paste previously exported JSON:",
			Input = true,
			Placeholder = "{ ... }",
			Buttons = { "Cancel", "Import" },
			Callback = function(choice, text)
				if choice ~= "Import" then
					return
				end
				if type(text) == "string" and Atlas:DeserializeConfigs(text) then
					refreshProfileBadge()
					Atlas:Notify({ Title = "Profiles", Text = "Imported.", Duration = 2, AccentToken = "Success" })
				else
					Atlas:Alert({ Title = "Profiles", Text = "Import failed — invalid JSON.", OkLabel = "OK" })
				end
			end,
		})
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
					refreshProfileBadge()
					Atlas:Notify({ Title = "Profiles", Text = "All profiles deleted.", Duration = 2, AccentToken = "Danger" })
				end
			end,
		})
	end,
})

--------------------------------------------------------------------
-- Tab 4: About
--------------------------------------------------------------------
about = window:CreateTab({ Title = "About" })
local info = about:CreateSection({ Title = "Atlas" })

info:CreateParagraph({
	Title = "Component UI Library  ·  v" .. Atlas:GetVersion(),
	Text = "Atlas is a zero-asset, component-based interface library built entirely "
		.. "from Instance graphs. RichText is <b>supported</b> everywhere, every control "
		.. "is flaggable, and the whole theme — colors, corners, fonts — rebinds live.",
})

if Atlas.Device.Class() == "Console" then
	info:CreateLabel({
		Text = "Gamepad: L3 toggles the menu · D-pad/stick moves focus · A activates "
			.. "· with a slider focused, D-pad/stick adjusts its value · keybinds capture pad buttons · B closes dialogs or the menu.",
	})
end

local stats = info:CreateLabel({ Text = "" }) -- filled at the end of the demo
---------------------------------------------------------------------------
-- (demo setup continues; stats fill happens after all registrations below)
---------------------------------------------------------------------------

-- Live device panel: watch this change as you rotate or resize.
local deviceSection = about:CreateSection({ Title = "Device" })
local deviceInfo = deviceSection:CreateParagraph({
	Title = "Adaptive Layout (v2)",
	Text = "...",
})
local function refreshDeviceInfo()
	local class = Atlas.Device.Class()
	local view = Atlas.Device.Viewport()
	deviceInfo:SetText(("Class: <b>%s</b>  ·  Viewport: <b>%d×%d</b>  ·  UI scale: <b>%.2f</b>")
		:format(class, math.floor(view.X + 0.5), math.floor(view.Y + 0.5), Atlas:GetScale())
		.. "\nThe menu size, sidebar and targets follow the device class — "
		.. "rotate or resize the window to watch everything re-fit live.")
end
refreshDeviceInfo()
Atlas.Device.OnViewportChanged(refreshDeviceInfo)

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

info:CreateButton({
	Title = "Notification with Action",
	Callback = function()
		Atlas:Notify({
			Title = "Profile Saved",
			Text = "Your settings were stored to 'default'.",
			Duration = 6,
			Action = {
				Text = "Undo",
				Callback = function()
					Atlas:Notify({ Title = "Profiles", Text = "Save reverted.", Duration = 2, AccentToken = "Danger" })
				end,
			},
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
	Name = "Hide Interface", Category = "System", Priority = -1, -- sinks below unprioritized commands
	Callback = function() window:SetVisible(false) end,
})
Atlas:RegisterCommand({
	Name = "Toggle Menu Button", Category = "Interface",
	Callback = function()
		local btn = window:GetToggleButton()
		window:SetToggleButton(not (btn and btn.Visible))
	end,
})
Atlas:RegisterCommand({
	Name = "Open UI Settings", Category = "Navigation", Priority = 1, -- floats to the top
	Callback = function()
		window:SetVisible(true)
		window:SelectTab("UI Settings")
	end,
})
Atlas:RegisterCommand({
	Name = "Center Window", Category = "Interface",
	Callback = function() window:Center() end,
})
Atlas:RegisterCommand({
	Name = "Open Notification Center", Category = "System",
	Callback = function() Atlas:ShowNotificationCenter() end,
})
Atlas:RegisterCommand({
	Name = "Clear Notifications", Category = "System",
	Callback = function() Atlas:DismissNotifications() end,
})
Atlas:RegisterCommand({
	Name = "Replay Loading Screen", Category = "System",
	Callback = function()
		Atlas:ShowLoadingScreen({
			Title = "Atlas", Subtitle = "Component UI Library", Duration = 2,
			Steps = { "Loading theme engine", "Building components", "Wiring services", "Ready" },
		})
	end,
})


--------------------------------------------------------------------
-- Keyboard shortcuts (v2.14.0)
--------------------------------------------------------------------
Atlas:AddShortcut({
	Name = "Toggle Status Bar",
	Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.D },
	Callback = function()
		local visible = Atlas._statusBar and Atlas._statusBar.Visible
		Atlas:SetStatusBarVisible(not visible)
		Atlas:Notify({ Title = "Status Bar", Text = visible and "Hidden" or "Shown", Duration = 1.5 })
	end,
})
Atlas:AddShortcut({
	Name = "Test Notification",
	Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.N },
	Callback = function()
		Atlas:Notify({ Title = "Shortcut", Text = "Ctrl+N fired!", Duration = 2, AccentToken = "Success" })
	end,
})
Atlas:AddShortcut({
	Name = "Quick Save",
	Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.S },
	Callback = function()
		Atlas:SaveConfig("quicksave")
		Atlas:SetStatusBarText("Quick-saved at " .. os.date("%H:%M:%S"))
		Atlas:Notify({ Title = "Profiles", Text = "Quick-saved.", Duration = 1.5, AccentToken = "Success" })
	end,
})

-- Status bar (v2.14.0): persistent info strip at the bottom of the screen.
Atlas:SetStatusBar({ Text = "Ready — Atlas v" .. Atlas:GetVersion(), Accent = true })

-- Registry stats for the About tab (all flags/commands exist by now).
stats:SetText(("Registry — flags: %d  ·  commands: %d  ·  themes: %d  ·  shortcuts: %d"):format(
	Atlas:GetFlagCount(),
	#Atlas:GetCommands(),
	#Atlas:GetThemeNames(),
	#Atlas:GetShortcuts()
))
