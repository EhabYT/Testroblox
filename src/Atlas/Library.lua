--!nonstrict
-- Library.lua — Atlas core: GUI manager and component framework.
-- Part of atlas-ui (MIT License).
--
-- This file is self-sufficient; its only dependencies are the sibling
-- Theme, Utility and Device ModuleScripts inside the same Atlas folder.
-- Rebuilt from scratch for Atlas v2 — device-adaptive by design.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local Utility = require(script.Parent.Utility)
local Device = require(script.Parent.Device)

--------------------------------------------------------------------
-- Singleton manager
--------------------------------------------------------------------

local Library = {
	VERSION = "2.16.0",
	Theme = Theme,
	Utility = Utility,
	Device = Device,
	_themeName = "Dark",
	_themeBindings = {},  -- functions re-applied by SetTheme
	_themeListeners = {}, -- functions notified after every retheme
	_windows = {},        -- live windows (set), re-fitted on viewport changes
	_flags = {},         -- flag name -> component handle
	_gui = nil,
	_notifHolder = nil,
	_uiScale = nil,
	_commands = {},
	_configs = {},
}

function Library:GetVersion()
	return self.VERSION
end

local function token(name)
	return Theme.Get(Library._themeName)[name]
end

-- Compatibility shim; canonical implementation lives in Device.lua.
function Library.IsTouchOnly()
	return Device.IsTouchOnly()
end

-- Console focus helpers -------------------------------------------------------
-- On ten-foot devices windows own a SelectionGroup; these move the gamepad
-- selection in and out. pcall-guarded: SelectedObject rejects invisible or
-- destroyed objects.

function Library:_consoleMode()
	return Device.Class() == "Console"
end

function Library:_focus(object)
	if not self:_consoleMode() then
		return
	end
	if object and object.Parent then
		pcall(function()
			GuiService.SelectedObject = object
		end)
	end
end

function Library:_releaseFocusIfInside(container)
	if not self:_consoleMode() then
		return
	end
	local sel = GuiService.SelectedObject
	if sel and container and sel:IsDescendantOf(container) then
		pcall(function()
			GuiService.SelectedObject = nil
		end)
	end
end

-- ONE heartbeat drives every gamepad-watched control (2.6.1) instead of one
-- per slider. Weak keys: destroyed controls drop out on their own.
local gamepadWatches = setmetatable({}, { __mode = "k" })
local gamepadWatchStarted = false

local function watchGamepad(owner, fn)
	gamepadWatches[owner] = fn
	if gamepadWatchStarted then
		return
	end
	gamepadWatchStarted = true
	RunService.Heartbeat:Connect(function(dt)
		for watchOwner, watcher in pairs(gamepadWatches) do
			if watchOwner.Parent == nil then
				gamepadWatches[watchOwner] = nil -- destroyed: stop paying for it
			else
				watcher(dt)
			end
		end
	end)
end

local function bind(fn)
	if pcall(fn) then
		table.insert(Library._themeBindings, fn)
	end
end

-- Bind an instance property to a theme token, now and on every SetTheme.
local function T(instance, property, themeToken)
	bind(function()
		local v = token(themeToken)
		if v ~= nil then
			instance[property] = v
		end
	end)
end

-- Wraps Utility.Create: a Font given as "@TokenName" is resolved to the
-- token value AND bound, so SetToken("Font", ...) rewrites text live.
local function Create(className, properties, children)
	local fontToken
	if type(properties) == "table" and type(properties.Font) == "string" then
		fontToken = properties.Font:match("^@(%a+)$")
		if fontToken then
			properties.Font = token(fontToken)
		end
	end
	local instance = Utility.Create(className, properties, children)
	if fontToken then
		T(instance, "Font", fontToken)
	end
	return instance
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local args = table.pack(...)
	task.spawn(function()
		local ok, err = pcall(fn, table.unpack(args, 1, args.n))
		if not ok then
			warn("[Atlas] Callback error:", err)
		end
	end)
end

-- JSON-safe boxing for profile/theme serialization (EnumItem, Color3, UDim, arrays).
local function encodeValue(v)
	local t = typeof(v)
	if t == "EnumItem" then
		return { __atlas = "enum", enumType = tostring(v.EnumType), name = v.Name }
	elseif t == "Color3" then
		return { __atlas = "color", r = v.R, g = v.G, b = v.B }
	elseif t == "UDim" then
		return { __atlas = "udim", s = v.Scale, o = v.Offset }
	elseif t == "table" then
		local out = {}
		for i, item in ipairs(v) do
			out[i] = encodeValue(item)
		end
		return out
	end
	return v
end

local function decodeValue(v)
	if type(v) == "table" then
		if v.__atlas == "enum" then
			local ok, result = pcall(function()
				return Enum[v.enumType][v.name]
			end)
			if ok then
				return result
			end
			return nil
		elseif v.__atlas == "color" then
			return Color3.new(v.r, v.g, v.b)
		elseif v.__atlas == "udim" then
			return UDim.new(tonumber(v.s) or 0, tonumber(v.o) or 0)
		end
		local out = {}
		for i, item in ipairs(v) do
			out[i] = decodeValue(item)
		end
		return out
	end
	return v
end

function Library:SetTheme(name)
	if Theme.Tokens[name] == nil then
		warn(("[Atlas] Unknown theme '%s'"):format(tostring(name)))
		return
	end
	self._themeName = name
	self:_requestThemeFlush()
end

function Library:_retheme()
	local alive = {}
	for _, fn in ipairs(self._themeBindings) do
		if pcall(fn) then
			table.insert(alive, fn) -- dead bindings (destroyed windows) are dropped here
		end
	end
	self._themeBindings = alive
	alive = {}
	for _, fn in ipairs(self._themeListeners) do
		if pcall(fn) then
			table.insert(alive, fn) -- dead listeners are purged the same way
		end
	end
	self._themeListeners = alive
end

-- Coalesced retheme (2.7.0): every mutation API (SetToken/ResetTheme/
-- SetTheme) schedules ONE flush per frame instead of re-applying all
-- bindings per call — dragging a linked color picker fires SetToken per
-- drag-frame and would otherwise repaint 200+ bindings per mouse pixel.
local rethemePending = false

function Library:_requestThemeFlush()
	if rethemePending then
		return
	end
	rethemePending = true
	task.defer(function()
		rethemePending = false
		Library:_retheme()
	end)
end

-- Runs fn now and after every theme change (SetTheme/SetToken/ResetTheme).
-- Dead listeners (their UI was destroyed) are purged on the next retheme.
function Library:OnThemeChanged(fn)
	assert(type(fn) == "function", "[Atlas] OnThemeChanged expects a function")
	if pcall(fn) then
		table.insert(self._themeListeners, fn)
	end
end

-- Live-edits any token of the ACTIVE theme and re-applies every binding.
function Library:SetToken(name, value)
	local theme = Theme.Tokens[self._themeName]
	if theme == nil or theme[name] == nil then
		warn(("[Atlas] Unknown token '%s'"):format(tostring(name)))
		return false
	end
	theme[name] = value
	self:_requestThemeFlush()
	return true
end

-- Restores the active theme's factory values from Theme.Defaults.
function Library:ResetTheme()
	local theme = Theme.Tokens[self._themeName]
	local defaults = Theme.Defaults and Theme.Defaults[self._themeName]
	if theme == nil or defaults == nil then
		return false
	end
	for key, value in pairs(defaults) do
		theme[key] = value
	end
	self:_requestThemeFlush()
	return true
end

-- Reads one token from the ACTIVE theme (nil if unknown).
function Library:GetToken(name)
	local theme = Theme.Tokens[self._themeName]
	if theme == nil then
		return nil
	end
	return theme[name]
end

-- Serializes the ACTIVE theme to shareable JSON (colors, fonts, UDim boxed).
function Library:ExportTheme()
	local theme = Theme.Tokens[self._themeName]
	if theme == nil then
		return nil
	end
	local data = {}
	for key, value in pairs(theme) do
		data[key] = encodeValue(value)
	end
	local HttpService = game:GetService("HttpService")
	local ok, json = pcall(HttpService.JSONEncode, HttpService, {
		__atlasTheme = 1,
		name = self._themeName,
		tokens = data,
	})
	if not ok then
		warn("[Atlas] ExportTheme: token value is not JSON-serializable")
		return nil
	end
	return json
end

-- Registers a theme from ExportTheme JSON and switches to it.
-- name (optional) overrides the embedded theme name; existing names are replaced.
function Library:ImportTheme(json, name)
	assert(type(json) == "string", "[Atlas] ImportTheme expects a JSON string")
	local HttpService = game:GetService("HttpService")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not (ok and type(data) == "table" and type(data.tokens) == "table") then
		warn("[Atlas] ImportTheme: invalid or unrecognized theme JSON")
		return false
	end
	local tokens = {}
	for key, value in pairs(data.tokens) do
		tokens[key] = decodeValue(value)
	end
	local themeName = (type(name) == "string" and name ~= "" and name)
		or (type(data.name) == "string" and data.name ~= "" and data.name)
		or "Imported"
	Theme.Register(themeName, tokens)
	self:SetTheme(themeName)
	return true
end

function Library:SetNotifySide(side)
	self:_getGui()
	local holder = self._notifHolder
	local list = holder:FindFirstChildOfClass("UIListLayout")
	if side == "Left" then
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.new(0, 16, 0, 16)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	else
		holder.AnchorPoint = Vector2.new(1, 0)
		holder.Position = UDim2.new(1, -16, 0, 16)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end
end

function Library:GetThemeNames()
	return Theme.Names()
end

function Library:GetThemeName()
	return self._themeName
end

function Library:SetScale(scale)
	self:_getGui()
	self._uiScale.Scale = Utility.Clamp(scale, 0.5, 2)
end

function Library:GetScale()
	if self._uiScale == nil then
		return 1
	end
	return self._uiScale.Scale
end

function Library:_registerFlag(flag, handle)
	if type(flag) == "string" and flag ~= "" then
		if self._flags[flag] ~= nil then
			-- Profiles key on flag names: a silent overwrite means one control
			-- never saves. Loud is better than lost.
			warn(("[Atlas] Duplicate flag %q — the earlier control will no longer save/restore."):format(flag))
		end
		self._flags[flag] = handle
	end
end

function Library:GetFlag(flag)
	return self._flags[flag]
end

-- Diagnostics: how many flag handles are registered (profile-persisted state).
function Library:GetFlagCount()
	local n = 0
	for _ in pairs(self._flags) do
		n = n + 1
	end
	return n
end

-- Copy of the palette command list (registration order, with Priority).
function Library:GetCommands()
	return table.clone(self._commands)
end

function Library:_getGui()
	local player = Players.LocalPlayer
	if not player then
		error("[Atlas] Library must be required from a LocalScript (client only).", 3)
	end
	if self._gui == nil then
		local gui = Create("ScreenGui", {
			Name = "AtlasInterface",
			ResetOnSpawn = false,
			DisplayOrder = 50,
			IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
		self._uiScale = Create("UIScale", { Scale = 1, Parent = gui })
		local notifWidth = Device.NotifyWidth()
		self._notifHolder = Create("Frame", {
			Name = "Notifications",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.new(0, notifWidth, 1, -32),
			BackgroundTransparency = 1,
			ZIndex = 1500, -- above windows (1), below modals (2000) and the palette (2500)
			Parent = gui,
		}, {
			Create("UIListLayout", {
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Top,
			}),
		})
		self._gui = gui
	end
	return self._gui
end

--------------------------------------------------------------------
-- Notifications
--------------------------------------------------------------------

function Library:Notify(config)
	config = config or {}
	self:_getGui()
	local duration = config.Duration or 4
	local accentToken = config.AccentToken or "Accent"

	-- Ring buffer of the last 15 toasts (newest first); GetNotificationHistory exposes it.
	self._notifHistory = self._notifHistory or {}
	table.insert(self._notifHistory, 1, {
		Title = config.Title or "Notification",
		Text = config.Text or "",
		At = os.time(),
		AccentToken = accentToken,
	})
	while #self._notifHistory > 15 do
		table.remove(self._notifHistory)
	end

	-- Cap: keep at most 8 toasts; evict the oldest beyond that (single pass).
	local visible = 0
	local oldest
	for _, child in ipairs(self._notifHolder:GetChildren()) do
		if child:IsA("CanvasGroup") then
			visible = visible + 1
			if oldest == nil then
				oldest = child
			end
		end
	end
	if visible >= 8 and oldest then
		oldest:Destroy()
	end

	local card = Create("CanvasGroup", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = self._notifHolder,
	}, {
		Create("UICorner", { CornerRadius = token("Corner") }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 30),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIScale", { Scale = 0.9 }), -- grow-in entrance
	})
	T(card:FindFirstChildOfClass("UICorner"), "CornerRadius", "Corner")
	T(card, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	-- Swipe-to-dismiss: drag sideways; past 64 px the toast flies out and
	-- fades, otherwise it springs back (weak-keyed listeners: free cleanup).
	local swiping = false
	local swipeStart, swipeOrigin = nil, nil
	card.InputBegan:Connect(function(input)
		if Utility.IsPrimary(input) then
			swiping = true
			swipeStart = input.Position
			swipeOrigin = card.Position
		end
	end)
	Utility.OnInput("Changed", card, function(input)
		if not swiping then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local scale = Library:GetScale()
		local dx = (input.Position.X - swipeStart.X) / math.max(scale, 0.01)
		card.Position = UDim2.new(swipeOrigin.X.Scale, swipeOrigin.X.Offset + dx, swipeOrigin.Y.Scale, swipeOrigin.Y.Offset)
	end)
	Utility.OnInput("Ended", card, function(input)
		if not swiping or not Utility.IsPrimary(input) then
			return
		end
		swiping = false
		local scale = Library:GetScale()
		local dx = (input.Position.X - swipeStart.X) / math.max(scale, 0.01)
		if math.abs(dx) > 64 then
			local dir = dx > 0 and 1 or -1
			Utility.Tween(card, Utility.TweenFast, {
				Position = UDim2.new(swipeOrigin.X.Scale, swipeOrigin.X.Offset + dir * 260, swipeOrigin.Y.Scale, swipeOrigin.Y.Offset),
				GroupTransparency = 1,
			}).Completed:Connect(function()
				card:Destroy()
			end)
		else
			Utility.Tween(card, Utility.TweenMed, {
				Position = UDim2.new(swipeOrigin.X.Scale, swipeOrigin.X.Offset, swipeOrigin.Y.Scale, swipeOrigin.Y.Offset),
			})
		end
	end)

	local bar = Create("Frame", {
		Name = "AccentBar",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = token(accentToken),
		BorderSizePixel = 0,
		Parent = card,
	})
	bind(function()
		bar.BackgroundColor3 = token(accentToken)
	end)

	local title = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@FontBold", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Title or "Notification",
		TextColor3 = token("Text"),
		Parent = card,
	})
	T(title, "TextColor3", "Text")

	local body = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@Font", TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = config.Text or "",
		TextColor3 = token("TextDim"),
		LayoutOrder = 1,
		Parent = card,
	})
	T(body, "TextColor3", "TextDim")

	local dismissed = false
	local dismiss
	dismiss = function()
		if dismissed then
			return
		end
		dismissed = true
		Utility.Tween(card:FindFirstChildOfClass("UIScale"), Utility.TweenFast, { Scale = 0.9 })
		Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			card:Destroy()
		end)
	end

	-- Optional single action button: Notify{ Action = { Text = "Undo", Callback = fn } }
	if type(config.Action) == "table" and type(config.Action.Text) == "string" then
		local actionBtn = Create("TextButton", {
			Size = UDim2.new(0, 0, 0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = token("SurfaceAlt"),
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 12,
			TextColor3 = token(accentToken),
			Text = config.Action.Text,
			LayoutOrder = 2,
			Parent = card,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		})
		T(actionBtn, "BackgroundColor3", "SurfaceAlt")
		bind(function()
			actionBtn.TextColor3 = token(accentToken)
		end)
		actionBtn.Activated:Connect(function()
			safeCall(config.Action.Callback)
			dismiss() -- acting on a toast also clears it
		end)
	end

	local close = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundTransparency = 1,
		Font = "@FontBold", TextSize = 13,
		Text = "×", TextColor3 = token("TextDim"),
		Parent = card,
	})
	T(close, "TextColor3", "TextDim")
	close.Activated:Connect(dismiss)

	-- Slide-in from the right + grow-in for a polished entrance.
	card.Position = UDim2.new(0, 40, 0, 0)
	Utility.Tween(card, Utility.TweenMed, { GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0) })
	Utility.Tween(card:FindFirstChildOfClass("UIScale"), Utility.TweenMed, { Scale = 1 })
	if duration and duration > 0 then
		task.delay(duration, function()
			if card.Parent ~= nil then
				dismiss()
			end
		end)
	end
	return card
end

--------------------------------------------------------------------
-- Class tables
--------------------------------------------------------------------

local Window = {}; Window.__index = Window
local Tab = {}; Tab.__index = Tab
local Section = {}; Section.__index = Section

--------------------------------------------------------------------
-- Window
--------------------------------------------------------------------

-- Builds the floating menu toggle button (tap/click toggles the window,
-- drag repositions it). Works with mouse and touch. The button theme-binds
-- to Accent/OnAccent, and its opacity mirrors the window's open state.
local function createToggleButton(lib, window, gui, root)
	local fab = Create("TextButton", {
		Name = "AtlasToggleButton",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -90),
		Size = UDim2.new(0, 52, 0, 52),
		BackgroundColor3 = token("Accent"),
		AutoButtonColor = false,
		Font = "@FontBold", TextSize = 22,
		Text = "≡", TextColor3 = token("OnAccent"),
		ZIndex = 1400,
		Parent = gui,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIStroke", {
			Thickness = 2, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	bind(function()
		fab.BackgroundColor3 = token("Accent")
		fab.TextColor3 = token("OnAccent")
	end)
	-- Start dimmed when the window opens hidden.
	fab.BackgroundTransparency = root.Visible and 0 or 0.55
	fab.TextTransparency = root.Visible and 0 or 0.35

	local dragging = false
	local moved = false
	local startPos = nil
	local framePos = nil
	fab.InputBegan:Connect(function(input)
		if not Utility.IsPrimary(input) then
			return
		end
		dragging = true
		moved = false
		startPos = input.Position
		framePos = fab.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)
	window._bag:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local scale = (lib._uiScale and lib._uiScale.Scale) or 1
		if scale <= 0 then scale = 1 end
		local delta = (input.Position - startPos) / scale
		if moved or delta.Magnitude > 10 then
			moved = true
			fab.Position = UDim2.new(
				framePos.X.Scale, framePos.X.Offset + delta.X,
				framePos.Y.Scale, framePos.Y.Offset + delta.Y
			)
		end
	end))
	fab.Activated:Connect(function()
		if moved then
			moved = false -- it was a drag, not a tap
			return
		end
		if fab:GetAttribute("AtlasSuppressClick") then
			return -- the release belonged to a long-press menu open
		end
		window:SetVisible(not root.Visible)
	end)
	-- Right-click / long-press the FAB: quick actions, reachable even while
	-- the window itself is hidden. Re-built on every open (labels track state).
	lib:AddContextMenu(fab, function()
		local items = {}
		if window._settingsTab then
			table.insert(items, { Name = "Open UI Settings", Callback = function()
				if not root.Visible then
					window:SetVisible(true)
				end
				if window._minimized then
					window:SetMinimized(false)
				end
				window:SelectTab(window._settingsTab)
			end })
		end
		table.insert(items, { Name = "Center Window", Callback = function()
			window:Center()
		end })
		table.insert(items, { Name = "Notification Center", Callback = function()
			lib:ShowNotificationCenter()
		end })
		if lib._watermarkCfg then
			local on = lib._watermark and lib._watermark.Visible
			table.insert(items, { Name = on and "Hide Watermark" or "Show Watermark", Callback = function()
				lib:SetWatermarkVisible(not on)
			end })
		end
		table.insert(items, "separator")
		table.insert(items, {
			Name = root.Visible and "Hide Interface" or "Show Interface",
			Danger = root.Visible,
			Callback = function() window:SetVisible(not root.Visible) end,
		})
		return items
	end)
	return fab
end

function Library:CreateWindow(config)
	config = config or {}
	local gui = self:_getGui()
	-- Responsive sizing (v2): the device class picks the menu size, clamps
	-- explicit sizes to the safe viewport, and recommends the UI scale.
	local deviceClass = Device.Class()
	local mobile = Device.IsMobile()
	local size = config.Size
	local maxW, maxH = Device.MaxMenuSize(deviceClass)
	if size then
		size = UDim2.fromOffset(
			math.min(size.X.Offset, maxW),
			math.min(size.Y.Offset, maxH)
		)
	else
		size = Device.MenuSize(deviceClass)
	end
	if config.AutoMobileScale ~= false and self._uiScale.Scale == 1 then
		self:SetScale(Device.UIScale(deviceClass))
	end
	-- Rendered size = size * UIScale; never let it exceed the safe viewport.
	if self._uiScale.Scale > 1 then
		size = UDim2.fromOffset(
			math.min(size.X.Offset, math.floor(maxW / self._uiScale.Scale)),
			math.min(size.Y.Offset, math.floor(maxH / self._uiScale.Scale))
		)
	end

	-- Root is a CanvasGroup so the whole window can fade via GroupTransparency
	-- and rounded corners clip every child (title bar, sidebar) for free.
	local root = Create("CanvasGroup", {
		Name = config.Name or "AtlasWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = config.Position or UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		Visible = config.Visible ~= false,
		SelectionGroup = true, -- gamepad focus stays inside the open window
		Parent = gui,
	}, { Create("UICorner", { CornerRadius = token("Corner") }) })
	T(root:FindFirstChildOfClass("UICorner"), "CornerRadius", "Corner")
	T(root, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = root,
	}), "Color", "Stroke")

	-- Title bar ------------------------------------------------------------
	local titleBar = Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0, ZIndex = 2,
		Parent = root,
	})
	T(titleBar, "BackgroundColor3", "SurfaceAlt")

	-- Controls: optional settings gear (SettingsTab) + minimize + close.
	local controlCount = 2
	if type(config.SettingsTab) == "string" and config.SettingsTab ~= "" then
		controlCount = 3
	end
	local controlsWidth = controlCount * 24 + (controlCount - 1) * 6

	local titleLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -(controlsWidth + 50), 1, 0),
		Font = "@FontBold", TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = token("Text"),
		Text = config.Title or "Atlas",
		Parent = titleBar,
	})
	T(titleLabel, "TextColor3", "Text")

	local dividerTop = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 40),
		BorderSizePixel = 0, ZIndex = 2,
		BackgroundColor3 = token("Stroke"),
		Parent = root,
	})
	T(dividerTop, "BackgroundColor3", "Stroke")

	-- Window controls ------------------------------------------------------
	local controls = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, controlsWidth, 0, 24),
		BackgroundTransparency = 1,
		Parent = titleBar,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function controlButton(symbol, order)
		local b = Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = token("Hover"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = "@FontBold", TextSize = 14,
			TextColor3 = token("TextDim"),
			Text = symbol,
			Parent = controls,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		T(b, "BackgroundColor3", "Hover")
		T(b, "TextColor3", "TextDim")
		b.MouseEnter:Connect(function()
			Utility.Tween(b, Utility.TweenFast, { BackgroundTransparency = 0, TextColor3 = token("Text") })
		end)
		b.MouseLeave:Connect(function()
			Utility.Tween(b, Utility.TweenFast, { BackgroundTransparency = 1, TextColor3 = token("TextDim") })
		end)
		return b
	end

	-- Gear first: CreateWindow{ SettingsTab = "UI Settings" } gives a visible,
	-- always-reachable entry to the settings page (works in every sidebar mode).
	local gearButton
	if controlCount == 3 then
		gearButton = controlButton("⚙", 0)
	end
	local minimizeButton = controlButton("–", 1)
	local closeButton = controlButton("×", 2)

	-- Body: sidebar + pages -------------------------------------------------
	local body = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 41),
		Size = UDim2.new(1, 0, 1, -41),
		Parent = root,
	})

	local compact = mobile or size.X.Offset < 560
	local sidebarW = compact and 112 or 150

	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, sidebarW, 1, 0),
		BackgroundColor3 = token("Background"),
		BorderSizePixel = 0,
		Parent = body,
	})
	T(sidebar, "BackgroundColor3", "Background")

	local tabList = Create("Frame", {
		Name = "TabList",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 1, -16),
		Parent = sidebar,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local dividerSide = Create("Frame", {
		Position = UDim2.new(0, sidebarW, 0, 8),
		Size = UDim2.new(0, 1, 1, -16),
		BorderSizePixel = 0,
		BackgroundColor3 = token("Stroke"),
		Parent = body,
	})
	T(dividerSide, "BackgroundColor3", "Stroke")

	local pages = Create("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, sidebarW + 8, 0, 6),
		Size = UDim2.new(1, -(sidebarW + 16), 1, -12),
		Parent = body,
	})

	-- Window object ----------------------------------------------------------
	local window = setmetatable({
		_root = root,
		_body = body,
		_tabList = tabList,
		_pages = pages,
		_tabs = {},
		_activeTab = nil,
		_bag = Utility.ConnectionBag(),
		_fullSize = size,
		_minimized = false,
		_sidebarPos = "left",
		_sidebarW = sidebarW,
	}, Window)
	window._sidebar = sidebar
	window._divider = dividerSide
	window._pagesFrame = pages
	window._titleLabel = titleLabel
	if type(config.SettingsTab) == "string" and config.SettingsTab ~= "" then
		window._settingsTab = config.SettingsTab -- gear button + FAB quick menu
	end

	Utility.MakeDraggable(root, titleBar, function()
		return (self._uiScale and self._uiScale.Scale) or 1
	end)

	closeButton.Activated:Connect(function()
		-- A close handler (Window:SetCloseHandler) can gate this: anything
		-- but an explicit false lets the default hide go through.
		local handler = window._closeHandler
		if type(handler) == "function" then
			local ok, allow = pcall(handler, window)
			if not (ok and allow ~= false) then
				return
			end
		end
		window:SetVisible(false)
	end)
	minimizeButton.Activated:Connect(function()
		window:SetMinimized(not window._minimized)
	end)
	if gearButton then
		gearButton.Activated:Connect(function()
			if not root.Visible then
				window:SetVisible(true) -- only when hidden: no pointless pop-in replay
			end
			if window._minimized then
				window:SetMinimized(false) -- a hidden body would swallow the tab switch
			end
			window:SelectTab(config.SettingsTab)
		end)
	end

	-- Double-click the title bar to minimize/restore (classic desktop UX).
	local lastTitleClick = 0
	titleBar.InputBegan:Connect(function(input)
		if not Utility.IsPrimary(input) then
			return
		end
		if input.Position.X >= controls.AbsolutePosition.X then
			return -- click landed on the window buttons, not the bar
		end
		local now = os.clock()
		if now - lastTitleClick < 0.35 then
			window:SetMinimized(not window._minimized)
			lastTitleClick = 0
		else
			lastTitleClick = now
		end
	end)

	-- Stored on the window so Window:SetToggleKey can rebind at runtime.
	window._toggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	window._gamepadToggleKey = config.GamepadToggleKey -- consoles have no RightShift
	window._bag:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == window._toggleKey
			or (window._gamepadToggleKey ~= nil and input.KeyCode == window._gamepadToggleKey) then
			window:SetVisible(not root.Visible)
		elseif input.KeyCode == Enum.KeyCode.ButtonB and root.Visible then
			-- Controller "back". An open modal handles B itself, so don't double-act.
			if Library:_consoleMode() and gui:FindFirstChild("ModalOverlay") == nil then
				window:SetVisible(false)
			end
		end
	end))

	-- Resize grip (opt-in via CreateWindow{ Resizable = true })
	if config.Resizable == true then
		local grip = Create("TextButton", {
			Name = "ResizeGrip",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -2, 1, -2),
			Size = UDim2.new(0, 14, 0, 14),
			BackgroundTransparency = 1,
			Font = "@Font", TextSize = 10,
			TextColor3 = token("TextDim"),
			Text = "◢",
			ZIndex = 10,
			Parent = root,
		})
		T(grip, "TextColor3", "TextDim")

		local resizing = false
		local startMouse = Vector3.zero
		local startOffset = Vector2.zero
		grip.InputBegan:Connect(function(input)
			if not Utility.IsPrimary(input) then
				return
			end
			resizing = true
			startMouse = input.Position
			startOffset = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end)
		window._bag:Add(UserInputService.InputChanged:Connect(function(input)
			if not resizing then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local scale = (self._uiScale and self._uiScale.Scale) or 1
			if scale <= 0 then
				scale = 1
			end
			local delta = (input.Position - startMouse) / scale
			root.Size = UDim2.fromOffset(
				math.clamp(startOffset.X + delta.X, 420, 1400),
				math.clamp(startOffset.Y + delta.Y, 280, 1000)
			)
		end))
	end

	-- Floating menu toggle button. ToggleButton = true | false | nil (auto =
	-- touch devices only). Legacy MobileButton = false still forces it off.
	window._gui = gui
	window._blurOn = config.BlurBackdrop == true
	local toggleOpt = config.ToggleButton
	if toggleOpt == nil then
		toggleOpt = mobile -- auto
	end
	if config.MobileButton == false then
		toggleOpt = false
	end
	-- Optional startup loading screen: the window stays hidden until it ends.
	-- Runs before the toggle button is created so the button starts dimmed.
	if config.LoadingScreen then
		root.Visible = false
		local loaderCfg = type(config.LoadingScreen) == "table" and table.clone(config.LoadingScreen) or {}
		loaderCfg.Duration = tonumber(loaderCfg.Duration) or 2.5 -- window reveal needs auto mode
		local userDone = loaderCfg.OnComplete
		loaderCfg.OnComplete = function()
			if config.Visible ~= false then
				window:SetVisible(true)
			end
			if type(userDone) == "function" then
				userDone()
			end
		end
		self:ShowLoadingScreen(loaderCfg)
	end

	if toggleOpt then
		window._toggleBtn = createToggleButton(self, window, gui, root)
	end

	-- BlurBackdrop: start blurred if the window opens visible.
	if window._blurOn and root.Visible then
		window:SetBlur(true)
	end

	window._deviceClass = deviceClass
	self._windows[window] = true

	-- Console: a window opening visible gets an initial focus target — the
	-- defer lets the caller create its tabs first (same thread, next frame).
	if root.Visible then
		task.defer(function()
			if root.Visible and Library:_consoleMode() then
				local tab = window._activeTab or window._tabs[1]
				if tab then
					Library:_focus(tab._button)
				end
			end
		end)
	end

	-- Layout persistence (opt-in): RememberLayout = true derives the flag key
	-- from the window name, a string sets it explicitly. The pseudo-flag
	-- snapshots {cx, cy, w, h} into every profile save and restores it
	-- clamped to the live viewport on load — no extra code needed.
	if config.RememberLayout then
		local key = type(config.RememberLayout) == "string" and config.RememberLayout
			or ("Window/" .. (config.Name or "AtlasWindow") .. "/Layout")
		window._layoutFlag = key
		self:_registerFlag(key, {
			Get = function()
				local cx, cy = window:_clampedCenter()
				return { cx, cy, root.Size.X.Offset, root.Size.Y.Offset }
			end,
			Set = function(_, value)
				if type(value) ~= "table" or #value < 4 then
					return
				end
				local cx, cy, w, h = value[1], value[2], value[3], value[4]
				if type(cx) ~= "number" or type(cy) ~= "number"
					or type(w) ~= "number" or type(h) ~= "number" then
					return
				end
				local maxW, maxH = Device.MaxMenuSize(Device.Class())
				w = math.min(math.max(w, 420), maxW)
				h = math.min(math.max(h, 280), maxH)
				if window._minimized then
					window._fullSize = UDim2.fromOffset(w, h) -- body is parked at title height
				else
					root.Size = UDim2.fromOffset(w, h)
				end
				local px, py = window:_clampedCenter(UDim2.fromOffset(cx, cy))
				root.Position = UDim2.fromOffset(px, py)
			end,
		})
	end

	return window
end

function Window:SetVisible(visible)
	local root = self._root
	if visible then
		root.Visible = true
		if self._minimized then
			Utility.Tween(root, Utility.TweenMed, { GroupTransparency = 0 })
		else
			-- Subtle pop-in: start a hair smaller and ease to full size
			-- (Back easing adds a tiny overshoot for a snappier feel).
			local target = root.Size
			root.Size = UDim2.fromOffset(
				math.max(target.X.Offset - 12, 420),
				math.max(target.Y.Offset - 12, 280)
			)
			Utility.Tween(root, Utility.TweenMed, { GroupTransparency = 0 })
			Utility.Tween(root, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = target })
		end
	else
		Library:_releaseFocusIfInside(root)
		Utility.Tween(root, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			-- Guard: the user may have re-shown the window during the fade.
			if root.GroupTransparency >= 0.99 then
				root.Visible = false
			end
		end)
	end
	-- The menu toggle button dims when the window is closed.
	if self._toggleBtn then
		Utility.Tween(self._toggleBtn, Utility.TweenFast, {
			BackgroundTransparency = visible and 0 or 0.55,
			TextTransparency = visible and 0 or 0.35,
		})
	end
	-- BlurBackdrop follows the menu's open state.
	if self._blurOn then
		self:SetBlur(visible == true)
	end
	-- Console: hand the gamepad focus to the active tab on show.
	if visible then
		task.defer(function()
			if root.Visible then
				local tab = self._activeTab or self._tabs[1]
				if tab then
					Library:_focus(tab._button)
				end
			end
		end)
	end
end

function Window:IsVisible()
	return self._root.Visible
end

function Window:IsMinimized()
	return self._minimized
end

-- Gates the × close button: fn(window) is consulted on every close click and
-- returning false vetoes the hide (e.g. show a confirm prompt instead — the
-- handler may close asynchronously itself). ToggleKey stays instant.
function Window:SetCloseHandler(fn)
	assert(fn == nil or type(fn) == "function",
		"[Atlas] Window:SetCloseHandler expects a function or nil")
	self._closeHandler = fn
end

-- Ring of the last 15 toasts (newest first): {Title, Text, At, AccentToken}.
function Library:GetNotificationHistory()
	return self._notifHistory or {}
end

--------------------------------------------------------------------
-- Service: Notification Center (modal history panel)
--------------------------------------------------------------------

-- Modal panel over everything under the palette: lists GetNotificationHistory
-- with per-entry accent dots and a Clear All action. Reopening is a no-op.
function Library:ShowNotificationCenter()
	local gui = self:_getGui()
	if self._notifCenter and self._notifCenter.Parent then
		return self._notifCenter -- already open
	end
	local prevFocus = GuiService.SelectedObject

	local overlay = Create("Frame", {
		Name = "NotifCenter",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Active = true,
		Selectable = false,
		SelectionGroup = true,
		ZIndex = 2400, -- under the palette (2500), above prompts (2000)
		Parent = gui,
	})
	self._notifCenter = overlay

	local viewport = Device.Viewport()
	local card = Create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, math.min(380, viewport.X - 32), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 2401,
		Parent = overlay,
	}, {
		Create("UICorner", { CornerRadius = token("Corner") }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card:FindFirstChildOfClass("UICorner"), "CornerRadius", "Corner")
	T(card, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local header = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Parent = card,
	})
	local title = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -140, 1, 0),
		Font = "@FontBold", TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = "Notifications",
		Parent = header,
	})
	T(title, "TextColor3", "Text")

	local function headerButton(text, order, accent)
		local b = Create("TextButton", {
			LayoutOrder = order,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(order - 1) * 84, 0.5, 0), -- 76 wide + 8 gap
			Size = UDim2.new(0, order == 1 and 76 or 56, 0, 24),
			BackgroundColor3 = accent and token("Accent") or token("SurfaceAlt"),
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 12,
			TextColor3 = accent and token("OnAccent") or token("Text"),
			Text = text,
			ZIndex = 2402,
			Parent = header,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		T(b, "BackgroundColor3", accent and "Accent" or "SurfaceAlt")
		T(b, "TextColor3", accent and "OnAccent" or "Text")
		Utility.AddPressEffect(b)
		return b
	end
	local clearButton = headerButton("Clear All", 1, false)
	local closeButton = headerButton("Close", 2, true)

	local list = Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, math.min(math.max(#self:GetNotificationHistory() * 48, 40), 260)),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = token("Stroke"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		LayoutOrder = 1,
		ZIndex = 2402,
		Parent = card,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(list, "ScrollBarImageColor3", "Stroke")

	local function rebuild()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local history = self:GetNotificationHistory()
		if #history == 0 then
			local empty = Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 40),
				Font = "@Font", TextSize = 12,
				TextColor3 = token("TextDim"),
				Text = "No notifications yet.",
				ZIndex = 2402,
				Parent = list,
			})
			T(empty, "TextColor3", "TextDim")
			return
		end
		for i, entry in ipairs(history) do
			local row = Create("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = token("SurfaceAlt"),
				BorderSizePixel = 0,
				ZIndex = 2402,
				Parent = list,
			}, {
				Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
				Create("UIPadding", {
					PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
					PaddingLeft = UDim.new(0, 26), PaddingRight = UDim.new(0, 8),
				}),
			})
			T(row, "BackgroundColor3", "SurfaceAlt")
			Create("Frame", { -- accent dot
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 8, 0.5, 0),
				Size = UDim2.new(0, 8, 0, 8),
				BackgroundColor3 = token(entry.AccentToken) or token("Accent"),
				BorderSizePixel = 0,
				ZIndex = 2403,
				Parent = row,
			}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -100, 0, 16),
				Font = "@FontMedium", TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = token("Text"),
				Text = entry.Title,
				ZIndex = 2403,
				Parent = row,
			})
			local body = Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 0, 0, 18),
				Size = UDim2.new(1, -100, 0, 14),
				Font = "@Font", TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = token("TextDim"),
				Text = entry.Text,
				ZIndex = 2403,
				Parent = row,
			})
			T(body, "TextColor3", "TextDim")
			local when = Create("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -26, 0, 0),
				Size = UDim2.new(0, 60, 0, 14),
				Font = "@Font", TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = token("TextDim"),
				Text = os.date("%H:%M:%S", entry.At),
				ZIndex = 2403,
				Parent = row,
			})
			T(when, "TextColor3", "TextDim")
			local removeBtn = Create("TextButton", { -- remove just this entry
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, 0, 1, 0),
				Size = UDim2.new(0, 20, 0, 20),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = "@FontBold", TextSize = 12,
				TextColor3 = token("TextDim"),
				Text = "×",
				ZIndex = 2403,
				Parent = row,
			}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			T(removeBtn, "BackgroundColor3", "Hover")
			T(removeBtn, "TextColor3", "TextDim")
			removeBtn.MouseEnter:Connect(function()
				Utility.Tween(removeBtn, Utility.TweenFast, { BackgroundTransparency = 0, TextColor3 = token("Text") })
			end)
			removeBtn.MouseLeave:Connect(function()
				Utility.Tween(removeBtn, Utility.TweenFast, { BackgroundTransparency = 1, TextColor3 = token("TextDim") })
			end)
			local entryRef = entry
			removeBtn.Activated:Connect(function()
				local h = self._notifHistory
				if h then
					local idx = table.find(h, entryRef) -- by identity: indices shift under newer inserts
					if idx then
						table.remove(h, idx)
					end
				end
				rebuild()
			end)
		end
	end
	rebuild()

	local escConn
	local function close()
		if escConn then
			escConn:Disconnect()
			escConn = nil
		end
		if self._notifCenter == overlay then
			self._notifCenter = nil
		end
		if self:_consoleMode() then
			pcall(function()
				GuiService.SelectedObject = prevFocus
			end)
		end
		Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			overlay:Destroy()
		end)
	end

	clearButton.Activated:Connect(function()
		table.clear(self._notifHistory or {})
		self:DismissNotifications()
		rebuild()
	end)
	closeButton.Activated:Connect(close)
	overlay.InputBegan:Connect(function(input) -- backdrop click (events don't bubble to the card)
		if Utility.IsPrimary(input) then
			close()
		end
	end)
	escConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			close()
		end
	end)

	Utility.Tween(card, Utility.TweenMed, { GroupTransparency = 0 })
	self._notifCenterClose = close
	Library:_focus(closeButton)
	return overlay
end

function Library:HideNotificationCenter()
	local close = self._notifCenterClose
	if close then
		close() -- full path: esc disconnect, focus restore, self._notifCenter reset
	end
end

-- Shows/hides the floating menu toggle button; creates it lazily if the
-- window was built with ToggleButton off/none.
function Window:SetToggleButton(visible)
	if visible then
		if not (self._toggleBtn and self._toggleBtn.Parent) then
			self._toggleBtn = createToggleButton(Library, self, self._gui, self._root)
		end
		self._toggleBtn.Visible = true
	elseif self._toggleBtn then
		self._toggleBtn.Visible = false
	end
end

function Window:GetToggleButton()
	return self._toggleBtn
end

function Window:SetMinimized(minimized)
	self._minimized = minimized
	if minimized then
		self._fullSize = self._root.Size
		self._body.Visible = false
		-- Collapse to title height. Use Size.X.Offset (pre-scale): AbsoluteSize
		-- is scaled by UIScale and would make the bar WIDER on touch devices.
		Utility.Tween(self._root, Utility.TweenMed, {
			Size = UDim2.new(0, self._root.Size.X.Offset, 0, 40),
		})
	else
		self._body.Visible = true
		Utility.Tween(self._root, Utility.TweenMed, { Size = self._fullSize })
	end
end

-- Single source for sidebar geometry — SetSidebarWidth and
-- SetSidebarPosition share it (left: sidebar|divider|pages, right: flipped).
function Window:_layoutSidebar()
	local w = self._sidebarW
	if self._sidebarPos == "right" then
		self._sidebar.Position = UDim2.new(1, -w, 0, 0)
		self._divider.Position = UDim2.new(1, -(w + 1), 0, 8)
		self._pagesFrame.Position = UDim2.new(0, 0, 0, 6)
	else
		self._sidebar.Position = UDim2.new(0, 0, 0, 0)
		self._divider.Position = UDim2.new(0, w, 0, 8)
		self._pagesFrame.Position = UDim2.new(0, w + 8, 0, 6)
	end
	self._pagesFrame.Size = UDim2.new(1, -(w + 16), 1, -12)
end

function Window:SetSidebarWidth(w)
	self._sidebarW = math.clamp(w, 96, 200)
	self._sidebar.Size = UDim2.new(0, self._sidebarW, 1, 0)
	self:_layoutSidebar()
end

-- Flips the sidebar to the other side of the window ("left" | "right");
-- the active tab's accent rail follows.
function Window:SetSidebarPosition(pos)
	assert(pos == "left" or pos == "right",
		"[Atlas] Window:SetSidebarPosition expects 'left' or 'right'")
	if self._sidebarPos == pos then
		return
	end
	self._sidebarPos = pos
	self:_layoutSidebar()
	if self._activeTab then
		self:_selectTab(self._activeTab) -- re-tweens the rail to the new side
	end
end

function Window:SetTransparency(t)
	self._root.BackgroundTransparency = math.clamp(t or 0, 0, 0.6)
end

-- Renames the title-bar text at runtime.
function Window:SetTitle(text)
	self._titleLabel.Text = tostring(text)
end

-- Rebinds the menu toggle keys at runtime (keyboard + optional gamepad):
--   window:SetToggleKey(Enum.KeyCode.K)            -- keyboard only
--   window:SetToggleKey(Enum.KeyCode.K, Enum.KeyCode.ButtonR3)
-- Read back with Window:GetToggleKey().
function Window:SetToggleKey(key, gamepadKey)
	assert(typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode,
		"[Atlas] Window:SetToggleKey expects an Enum.KeyCode")
	self._toggleKey = key
	if gamepadKey ~= nil then
		assert(typeof(gamepadKey) == "EnumItem" and gamepadKey.EnumType == Enum.KeyCode,
			"[Atlas] Window:SetToggleKey gamepadKey expects an Enum.KeyCode")
		self._gamepadToggleKey = gamepadKey
	end
end

function Window:GetToggleKey()
	return self._toggleKey, self._gamepadToggleKey
end

-- Resizes at runtime (same minimums as the resize grip; clamped to the
-- safe viewport of the current device class). While minimized the new size
-- lands in _fullSize — the collapsed bar must keep title height.
function Window:SetSize(w, h)
	w = math.max(tonumber(w) or self._fullSize.X.Offset, 420)
	h = math.max(tonumber(h) or self._fullSize.Y.Offset, 280)
	local maxW, maxH = Device.MaxMenuSize(Device.Class())
	local fitted = UDim2.fromOffset(math.min(w, maxW), math.min(h, maxH))
	if self._minimized then
		self._fullSize = fitted
		self._root.Size = UDim2.new(0, fitted.X.Offset, 0, 40)
	else
		self._root.Size = fitted
	end
end

-- The window is anchored by its center: converts a UDim2 to the absolute
-- center px and clamps it so the title bar is always reachable (the rule
-- _refit enforces after rotations). Pass a UDim2 or nil for the current one.
function Window:_clampedCenter(pos)
	pos = pos or self._root.Position
	local viewport = Device.Viewport()
	local cx = math.clamp(pos.X.Scale * viewport.X + pos.X.Offset, 60, math.max(viewport.X - 60, 60))
	local cy = math.clamp(pos.Y.Scale * viewport.Y + pos.Y.Offset, 40, math.max(viewport.Y - 40, 40))
	return cx, cy
end

function Window:GetPosition()
	return self._root.Position
end

-- Moves the window; clamps so it can never be parked off-screen.
function Window:SetPosition(pos)
	assert(typeof(pos) == "UDim2", "[Atlas] Window:SetPosition expects a UDim2")
	local cx, cy = self:_clampedCenter(pos)
	self._root.Position = UDim2.fromOffset(cx, cy)
end

function Window:Center()
	self._root.Position = UDim2.fromScale(0.5, 0.5)
end

-- Current rendered size in pixels (before UIScale), returns w, h.
function Window:GetSize()
	return self._root.Size.X.Offset, self._root.Size.Y.Offset
end

-- Re-fits size and position after a viewport change (rotation, resize):
-- shrinks what no longer fits, keeps the title bar reachable on screen.
function Window:_refit(viewport)
	local maxW, maxH = Device.MaxMenuSize(Device.Class())
	local size = self._minimized and self._fullSize or self._root.Size
	if size.X.Offset > maxW or size.Y.Offset > maxH then
		local fitted = UDim2.fromOffset(
			math.min(size.X.Offset, maxW),
			math.min(size.Y.Offset, maxH)
		)
		if self._minimized then
			self._fullSize = fitted -- bar keeps title height; restore target shrinks
			self._root.Size = UDim2.new(0, fitted.X.Offset, 0, 40)
		else
			self._root.Size = fitted
		end
	end
	local cx, cy = self:_clampedCenter()
	self._root.Position = UDim2.fromOffset(cx, cy)
	-- the floating toggler must stay reachable too (it can be dragged anywhere)
	if self._toggleBtn then
		local fpos = self._toggleBtn.Position
		local fx = math.clamp(fpos.X.Scale * viewport.X + fpos.X.Offset, 52, math.max(viewport.X, 52))
		local fy = math.clamp(fpos.Y.Scale * viewport.Y + fpos.Y.Offset, 52, math.max(viewport.Y, 52))
		self._toggleBtn.Position = UDim2.fromOffset(fx, fy)
	end
end

-- Lighting blur behind the menu: CreateWindow{ BlurBackdrop = true } or
-- Window:SetBlurBackdrop(true) at runtime. SetBlur is the low-level driver.
function Window:SetBlur(on)
	if on then
		if not (self._blur and self._blur.Parent) then
			local blur = Instance.new("BlurEffect")
			blur.Name = "AtlasBlur"
			blur.Size = 0
			blur.Parent = game:GetService("Lighting")
			self._blur = blur
		end
		Utility.Tween(self._blur, Utility.TweenMed, { Size = 12 })
	elseif self._blur then
		Utility.Tween(self._blur, Utility.TweenFast, { Size = 0 })
	end
end

function Window:SetBlurBackdrop(on)
	self._blurOn = on == true
	if self._blurOn then
		if self._root.Visible then
			self:SetBlur(true)
		end
	else
		self:SetBlur(false)
	end
end

function Window:Destroy()
	Library._windows[self] = nil
	if self._layoutFlag then
		Library._flags[self._layoutFlag] = nil
		self._layoutFlag = nil
	end
	self._bag:DisconnectAll()
	if self._toggleBtn then
		self._toggleBtn:Destroy() -- parents to the ScreenGui, not the root
		self._toggleBtn = nil
	end
	if self._blur then
		self._blur:Destroy() -- Lighting effect, not a GUI element
		self._blur = nil
	end
	self._root:Destroy()
end

--------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------

function Window:CreateTab(config)
	config = config or {}
	local thisWindow = self

	local button = Create("TextButton", {
		Name = "Tab_" .. (config.Title or "Tab"),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = token("Hover"),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, -- narrow sidebars clip clean, no overflow into the page
		TextColor3 = token("TextDim"),
		Text = config.Title or "Tab",
		Parent = self._tabList,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 30) }),
		Create("Frame", { -- accent rail, shown only on the active tab
			Name = "ActiveRail",
			Size = UDim2.new(0, 3, 0.55, 0),
			Position = UDim2.new(0, 4, 0.225, 0),
			BackgroundColor3 = token("Accent"),
			BorderSizePixel = 0,
			BackgroundTransparency = 1,
		}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
		Create("TextLabel", { -- counter bubble, driven by Tab:SetBadge(v)
			Name = "Badge",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 0, 0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = token("Accent"),
			BorderSizePixel = 0,
			Font = "@FontBold", TextSize = 10,
			TextColor3 = token("OnAccent"),
			Text = "",
			Visible = false,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
		}),
	})

	local page = Create("ScrollingFrame", {
		Name = "Page_" .. (config.Title or "Tab"),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = token("Stroke"),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self._pages,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }),
	})
	T(page, "ScrollBarImageColor3", "Stroke")

	local tab = setmetatable({ _window = thisWindow, _button = button, _page = page }, Tab)
	T(button:FindFirstChild("ActiveRail"), "BackgroundColor3", "Accent")
	T(button:FindFirstChild("Badge"), "BackgroundColor3", "Accent")
	T(button:FindFirstChild("Badge"), "TextColor3", "OnAccent")

	bind(function()
		if thisWindow._activeTab == tab then
			button.BackgroundTransparency = 0
			button.TextColor3 = token("Text")
		else
			button.BackgroundTransparency = 1
			button.TextColor3 = token("TextDim")
		end
	end)

	button.MouseEnter:Connect(function()
		if thisWindow._activeTab ~= tab then
			Utility.Tween(button, Utility.TweenFast, { BackgroundTransparency = 0.5, TextColor3 = token("Text") })
		end
	end)
	button.MouseLeave:Connect(function()
		if thisWindow._activeTab ~= tab then
			Utility.Tween(button, Utility.TweenFast, { BackgroundTransparency = 1, TextColor3 = token("TextDim") })
		end
	end)
	button.Activated:Connect(function()
		thisWindow:_selectTab(tab)
	end)

	table.insert(thisWindow._tabs, tab)
	if #thisWindow._tabs == 1 then
		thisWindow:_selectTab(tab)
	end
	return tab
end

function Window:_selectTab(tab)
	self._activeTab = tab
	for _, t in ipairs(self._tabs) do
		local active = (t == tab)
		if active then
			t._page.Visible = true
			-- Scroll to top on tab switch for a fresh feel.
			t._page.CanvasPosition = Vector2.new(0, 0)
			-- Fade-in: a quick transparency transition on the page.
			if t._page:FindFirstChild("_PageFade") == nil then
				-- Use a CanvasGroup wrapper trick: page is a ScrollingFrame,
				-- so we tween its children's GroupTransparency via a nested approach.
				-- Simpler: adjust the page's own scroll-bar and tween transparency
				-- of a cover overlay that fades out.
				local fade = Create("Frame", {
					Name = "_PageFade",
					Size = UDim2.new(1, 0, 1, 0),
					BackgroundColor3 = token("Surface"),
					BackgroundTransparency = 0,
					ZIndex = 100,
					Parent = t._page,
				})
				T(fade, "BackgroundColor3", "Surface")
				Utility.Tween(fade, Utility.TweenFast, { BackgroundTransparency = 1 }).Completed:Connect(function()
					fade:Destroy()
				end)
			end
		else
			t._page.Visible = false
		end
		Utility.Tween(t._button, Utility.TweenFast, {
			BackgroundTransparency = active and 0 or 1,
			TextColor3 = active and token("Text") or token("TextDim"),
		})
		local rail = t._button:FindFirstChild("ActiveRail")
		if rail then
			-- Rail hugs the sidebar's outer edge (matters on right sidebars).
			rail.Position = self._sidebarPos == "right"
				and UDim2.new(1, -7, 0.225, 0)
				or UDim2.new(0, 4, 0.225, 0)
			Utility.Tween(rail, Utility.TweenFast, { BackgroundTransparency = active and 0 or 1 })
		end
	end
end

-- Public tab switching — accepts a tab handle or its title string:
--   window:SelectTab(tab)  /  window:SelectTab("UI Settings")
-- Returns true on success and warns on an unknown title — a silent no-op
-- looks exactly like "the settings tab is broken".
function Window:SelectTab(tabOrTitle)
	local target = tabOrTitle
	if type(tabOrTitle) == "string" then
		target = nil
		for _, t in ipairs(self._tabs) do
			if t._button.Text == tabOrTitle then
				target = t
				break
			end
		end
	end
	if target then
		self:_selectTab(target)
		return true
	end
	warn(("[Atlas] SelectTab: no tab titled %q"):format(tostring(tabOrTitle)))
	return false
end

-- Counter bubble on the tab button: tab:SetBadge(3) / tab:SetBadge("new").
-- nil, false, 0 or "" hides it again.
function Tab:SetBadge(value)
	local badge = self._button and self._button:FindFirstChild("Badge")
	if badge == nil then
		return
	end
	if value == nil or value == false or value == 0 or value == "" then
		badge.Visible = false
	else
		badge.Text = tostring(value)
		badge.Visible = true
	end
end

-- Hides/shows the sidebar entry + page. Hiding the ACTIVE tab moves
-- selection to the first remaining visible tab.
function Tab:SetVisible(visible)
	local v = visible == true
	self._button.Visible = v
	if not v and self._window._activeTab == self then
		local fallback
		for _, t in ipairs(self._window._tabs) do
			if t ~= self and t._button.Visible then
				fallback = t
				break
			end
		end
		if fallback then
			self._window:_selectTab(fallback)
		else
			self._page.Visible = false
			self._window._activeTab = nil
		end
	elseif v and self._window._activeTab == nil then
		self._window:_selectTab(self) -- was the only tab left: adopt it
	end
end

--------------------------------------------------------------------
-- Section and component rows
--------------------------------------------------------------------

local function sectionRow(section, height, config)
	config = config or {}
	-- Rows with a Description sub-label need extra height.
	local effectiveHeight = config.Description and (height + 16) or height
	local row = Create("Frame", {
		Size = UDim2.new(1, 0, 0, effectiveHeight),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		Parent = section._body,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}),
	})
	T(row, "BackgroundColor3", "SurfaceAlt")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = row,
	}), "Color", "Stroke")
	-- Hover highlight on every control row.
	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			Utility.Tween(row, Utility.TweenFast, { BackgroundColor3 = token("Hover") })
		end
	end)
	row.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			Utility.Tween(row, Utility.TweenFast, { BackgroundColor3 = token("SurfaceAlt") })
		end
	end)
	return row
end

local function rowLabel(row, text, widthReserve, description)
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(widthReserve or 0), 0, description and 18 or 0),
		AutomaticSize = description and Enum.AutomaticSize.None or Enum.AutomaticSize.None,
		Position = description and UDim2.new(0, 0, 0, 4) or UDim2.new(0, 0, 0, 0),
		AnchorPoint = description and Vector2.new(0, 0) or Vector2.zero,
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = token("Text"),
		Text = text,
		Parent = row,
	})
	if not description then
		label.Size = UDim2.new(1, -(widthReserve or 0), 1, 0)
	end
	T(label, "TextColor3", "Text")
	-- Optional description subtitle below the title.
	if description then
		local desc = Create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 22),
			Size = UDim2.new(1, -(widthReserve or 0), 0, 14),
			Font = "@Font", TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = token("TextDim"),
			Text = description,
			Parent = row,
		})
		T(desc, "TextColor3", "TextDim")
	end
	return label
end

function Tab:CreateSection(config)
	config = config or {}
	local collapsible = config.Collapsible == true

	local holder = Create("Frame", {
		Name = "Section_" .. (config.Title or ""),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._page,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- Section icon: CreateSection{ Icon = "⚡" } adds a prefix before the title.
	local headerText = string.upper(config.Title or "Section")
	if type(config.Icon) == "string" and config.Icon ~= "" then
		headerText = config.Icon .. "  " .. headerText
	end

	local headerClass = collapsible and "TextButton" or "TextLabel"
	local header = Create(headerClass, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = "@FontBold", TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = headerText,
		AutoButtonColor = false,
		Parent = holder,
	})
	T(header, "TextColor3", "TextDim")

	-- Optional header bubble, driven by Section:SetBadge(v) (parity with tabs).
	local badge = Create("TextLabel", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 0, 0, 14),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Font = "@FontBold", TextSize = 10,
		TextColor3 = token("OnAccent"),
		Text = "",
		Visible = false,
		Parent = header,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }),
	})
	T(badge, "BackgroundColor3", "Accent")
	T(badge, "TextColor3", "OnAccent")

	local body = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local section = setmetatable({ _body = body, _holder = holder, _badge = badge }, Section)

	if collapsible then
		local collapsed = config.DefaultCollapsed == true
		-- Dedicated chevron glyph (rotates -90° when collapsed) instead of
		-- re-rendering the whole header text.
		local chevron = Create("TextLabel", {
			Name = "Chevron",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 14, 1, 0),
			Font = "@FontBold", TextSize = 12,
			TextColor3 = token("TextDim"),
			Text = "▾",
			Parent = header,
		})
		T(chevron, "TextColor3", "TextDim")
		Create("UIPadding", { PaddingLeft = UDim.new(0, 16), Parent = header })
		header.Text = string.upper(config.Title or "Section")
		header.MouseEnter:Connect(function()
			Utility.Tween(header, Utility.TweenFast, { TextColor3 = token("Text") })
		end)
		header.MouseLeave:Connect(function()
			Utility.Tween(header, Utility.TweenFast, { TextColor3 = token("TextDim") })
		end)
		local function paint(instant)
			body.Visible = not collapsed
			local goal = { Rotation = collapsed and -90 or 0 }
			if instant then
				chevron.Rotation = goal.Rotation
			else
				Utility.Tween(chevron, Utility.TweenFast, goal)
			end
		end
		header.Activated:Connect(function()
			collapsed = not collapsed
			paint(false)
		end)
		paint(true)

		-- Collapse state is flaggable, so profiles remember it.
		local sectionHandle = {}
		function sectionHandle:Set(c, silent)
			c = c == true
			if c ~= collapsed then
				collapsed = c
				paint(false)
			end
		end
		function sectionHandle:Get()
			return collapsed
		end
		Library:_registerFlag(config.Flag, sectionHandle)
	end

	return section
end

-- Hides/shows the whole section (feature groups, conditional content).
function Section:SetVisible(visible)
	self._holder.Visible = visible == true
end

-- Number/status bubble in the section header (parity with Tab:SetBadge):
-- nil/false/0/"" clears it, anything else shows.
function Section:SetBadge(value)
	local badge = self._badge
	if badge == nil then
		return
	end
	if value == nil or value == false or value == 0 or value == "" then
		badge.Visible = false
	else
		badge.Text = tostring(value)
		badge.Visible = true
	end
end

function Section:CreateDivider()
	local line = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = self._body,
	})
	T(line, "BackgroundColor3", "Stroke")
	return line
end

--------------------------------------------------------------------
-- Component: Button
--------------------------------------------------------------------

function Section:CreateButton(config)
	config = config or {}
	local btnHeight = config.Description and 50 or 34
	local button = Create("TextButton", {
		Size = UDim2.new(1, 0, 0, btnHeight),
		BackgroundColor3 = token("SurfaceAlt"),
		AutoButtonColor = false, BorderSizePixel = 0,
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Button",
		Parent = self._body,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			PaddingTop = config.Description and UDim.new(0, 6) or UDim.new(0, 0),
		}),
		Create("TextLabel", {
			Name = "Chevron",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 16, 0, 16),
			Font = "@FontBold", TextSize = 14,
			TextColor3 = token("TextDim"), Text = "›",
		}),
	})
	if config.Description then
		-- Shift the title up and add a description line.
		button.TextYAlignment = Enum.TextYAlignment.Top
		local desc = Create("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 18),
			Size = UDim2.new(1, -24, 0, 14),
			Font = "@Font", TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = token("TextDim"),
			Text = config.Description,
			Parent = button,
		})
		T(desc, "TextColor3", "TextDim")
	end
	T(button, "BackgroundColor3", "SurfaceAlt")
	T(button, "TextColor3", "Text")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button,
	}), "Color", "Stroke")
	T(button.Chevron, "TextColor3", "TextDim")

	button.MouseEnter:Connect(function()
		Utility.Tween(button, Utility.TweenFast, { BackgroundColor3 = token("Hover") })
	end)
	button.MouseLeave:Connect(function()
		Utility.Tween(button, Utility.TweenFast, { BackgroundColor3 = token("SurfaceAlt") })
	end)
	Utility.AddPressEffect(button)

	local disabled = config.Disabled == true
	if disabled then
		button.AutoButtonColor = false
		button.BackgroundTransparency = 0.4
		button.TextTransparency = 0.4
	end

	button.Activated:Connect(function()
		if disabled then return end
		safeCall(config.Callback)
	end)

	local handle = { Root = button }
	function handle:SetText(text)
		button.Text = text
	end
	function handle:SetDisabled(on)
		disabled = on == true
		button.BackgroundTransparency = disabled and 0.4 or 0
		button.TextTransparency = disabled and 0.4 or 0
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Toggle
--------------------------------------------------------------------

function Section:CreateToggle(config)
	config = config or {}
	local state = config.Default == true
	local disabled = config.Disabled == true
	local row = sectionRow(self, 34, { Description = config.Description })
	rowLabel(row, config.Title or "Toggle", 60, config.Description)

	local pill = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 20),
		BorderSizePixel = 0,
		Parent = row,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = pill,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local hit = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "",
		ZIndex = 3, Parent = row,
	})
	-- Toggle hover: pill brightens slightly when hovered.
	hit.MouseEnter:Connect(function()
		if not disabled then
			Utility.Tween(knob, Utility.TweenFast, { Size = UDim2.new(0, 18, 0, 18) })
		end
	end)
	hit.MouseLeave:Connect(function()
		Utility.Tween(knob, Utility.TweenFast, { Size = UDim2.new(0, 16, 0, 16) })
	end)

	local function apply(instant)
		local onColor = state and token("Accent") or token("Stroke")
		local knobPos = state and UDim2.new(0, 18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
		if instant then
			pill.BackgroundColor3 = onColor
			knob.Position = knobPos
		else
			Utility.Tween(pill, Utility.TweenFast, { BackgroundColor3 = onColor })
			Utility.Tween(knob, Utility.TweenFast, { Position = knobPos })
		end
	end
	bind(function()
		apply(true)
	end)

	local handle = { Root = row }
	function handle:Set(newState, silent)
		newState = newState == true
		if newState == state then
			return
		end
		state = newState
		apply(false)
		if not silent then
			safeCall(config.Callback, state)
		end
	end
	function handle:Get()
		return state
	end

	hit.Activated:Connect(function()
		if disabled then return end
		handle:Set(not state)
	end)

	function handle:SetDisabled(on)
		disabled = on == true
		row.BackgroundTransparency = disabled and 0.4 or 0
	end

	if disabled then
		row.BackgroundTransparency = 0.4
	end

	Library:_registerFlag(config.Flag, handle)
	apply(true)
	return handle
end

--------------------------------------------------------------------
-- Component: Slider
--------------------------------------------------------------------

function Section:CreateSlider(config)
	config = config or {}
	local minV = config.Min or 0
	local maxV = config.Max or 100
	local step = config.Step or 1
	local suffix = config.Suffix or ""
	local value = Utility.Clamp(config.Default or minV, minV, maxV)

	local function format(v)
		if step >= 1 then
			return string.format("%d%s", v, suffix)
		end
		return string.format("%.2f%s", v, suffix)
	end

	local row = sectionRow(self, 50, { Description = config.Description })
	local label = rowLabel(row, config.Title or "Slider", 90, config.Description)
	label.Size = UDim2.new(1, -90, 0, 20)

	local valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 86, 0, 20),
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("TextDim"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = format(value),
		Parent = row,
	})
	T(valueLabel, "TextColor3", "TextDim")

	local track = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = row,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "Stroke")

	local function percent(v)
		if maxV <= minV then
			return 0
		end
		return (v - minV) / (maxV - minV)
	end

	local fill = Create("Frame", {
		Size = UDim2.fromScale(percent(value), 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	bind(function()
		fill.BackgroundColor3 = token("Accent")
	end)

	local knob = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(percent(value), 0, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0, ZIndex = 2,
		Parent = track,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIStroke", {
			Thickness = 1, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	local hit = Create("TextButton", {
		BackgroundTransparency = 1, Text = "",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3, Parent = row,
	})
	-- Gamepad adjust mode: horizontal selection points back at ourselves, so
	-- DPad/stick ADJUSTS the value instead of navigating away (up/down still
	-- moves focus to neighbours — classic console slider trick).
	hit.SelectionLeft = hit
	hit.SelectionRight = hit

	local dragging = false

	local function setValue(v, fire)
		v = Utility.Clamp(Utility.Round(v, step), minV, maxV)
		if v ~= value then
			value = v
			local p = percent(v)
			fill.Size = UDim2.fromScale(p, 1)
			knob.Position = UDim2.new(p, 0, 0.5, 0)
			valueLabel.Text = format(v)
			if fire ~= false then
				safeCall(config.Callback, v)
			end
		end
	end

	local function updateFromInput(input)
		local width = math.max(track.AbsoluteSize.X, 1)
		local p = Utility.Clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		setValue(minV + p * (maxV - minV))
	end

	local function knobGrow(big)
		Utility.Tween(knob, Utility.TweenFast, { Size = big and UDim2.new(0, 18, 0, 18) or UDim2.new(0, 14, 0, 14) })
	end

	hit.InputBegan:Connect(function(input)
		if Utility.IsPrimary(input) then
			dragging = true
			knobGrow(true)
			updateFromInput(input)
		end
	end)
	Utility.OnInput("Ended", hit, function(input)
		if Utility.IsPrimary(input) then
			dragging = false
			knobGrow(false)
		end
	end)
	-- The knob swells on hover too, signaling "grabbable" (desktop only).
	hit.MouseEnter:Connect(function()
		knobGrow(true)
	end)
	hit.MouseLeave:Connect(function()
		if not dragging then
			knobGrow(false)
		end
	end)
	Utility.OnInput("Changed", hit, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input)
		end
	end)

	-- Gamepad: when the track is the selected object, DPad taps step by Step
	-- and the left thumbstick sweeps continuously (~full range in 1.7 s).
	-- knobGrow transitions only on edges so idle frames don't churn tweens.
	local stickActive = false
	local function gamepadGrow(on)
		if stickActive ~= on then
			stickActive = on
			knobGrow(on)
		end
	end
	Utility.OnInput("Began", hit, function(input)
		if GuiService.SelectedObject ~= hit then
			return
		end
		if input.KeyCode == Enum.KeyCode.DPadLeft then
			setValue(value - step)
			gamepadGrow(true)
			task.delay(0.15, gamepadGrow, false)
		elseif input.KeyCode == Enum.KeyCode.DPadRight then
			setValue(value + step)
			gamepadGrow(true)
			task.delay(0.15, gamepadGrow, false)
		end
	end)
	-- Shared watcher in Library: ONE heartbeat for every slider.
	watchGamepad(hit, function(dt)
		if GuiService.SelectedObject ~= hit then
			gamepadGrow(false)
			return
		end
		local sweeping = false
		for _, obj in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
			if obj.KeyCode == Enum.KeyCode.Thumbstick1 then
				local x = obj.Position.X
				if math.abs(x) > 0.15 then
					setValue(value + x * (maxV - minV) * 0.6 * dt)
					sweeping = true
				end
			end
		end
		gamepadGrow(sweeping)
	end)

	local handle = { Root = row }
	function handle:Set(v, silent)
		setValue(v, not silent)
	end
	function handle:Get()
		return value
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Dropdown
--------------------------------------------------------------------

function Section:CreateDropdown(config)
	config = config or {}
	local options = config.Options or {}
	assert(#options > 0, "[Atlas] CreateDropdown requires a non-empty Options array")
	local selected = config.Default
	if not table.find(options, selected) then
		selected = options[1]
	end
	local open = false

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Dropdown", (config.Width or 150) + 12)

	local valueButton = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, config.Width or 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("Text"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 24) }),
		Create("TextLabel", {
			Name = "Chevron",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			Font = "@FontMedium", TextSize = 12,
			TextColor3 = token("TextDim"),
			Text = "▾",
		}),
	})
	T(valueButton, "BackgroundColor3", "Surface")
	T(valueButton, "TextColor3", "Text")
	T(valueButton:FindFirstChild("Chevron"), "TextColor3", "TextDim")
	Utility.AddPressEffect(valueButton)

	local function renderValue()
		valueButton.Text = tostring(selected)
	end
	renderValue()

	local list = Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(list, "BackgroundColor3", "SurfaceAlt")

	local optionEntries = {}
	local searchBox
	local chevron = valueButton:FindFirstChild("Chevron")

	-- Single open/close path: rotates the chevron and manages the search box.
	local function setOpen(v)
		open = v
		list.Visible = v
		if chevron then
			Utility.Tween(chevron, Utility.TweenFast, { Rotation = v and 180 or 0 })
		end
		if v and searchBox then
			searchBox:CaptureFocus()
		elseif (not v) and searchBox and searchBox.Text ~= "" then
			searchBox.Text = "" -- reopen with a clean filter next time
		end
	end

	local function applyFilter()
		local query = searchBox and searchBox.Text:lower() or ""
		for _, entry in ipairs(optionEntries) do
			entry.button.Visible = query == "" or entry.name:find(query, 1, true) ~= nil
		end
	end

	-- (Re)builds the option rows; used at creation and by handle:SetOptions.
	local function renderOptions(newOptions)
		for _, entry in ipairs(optionEntries) do
			entry.button:Destroy()
		end
		optionEntries = {}
		for index, option in ipairs(newOptions) do
			-- OptionColors{ [option] = Color3 }: a dot swatch before the label.
			local dotColor = type(config.OptionColors) == "table" and config.OptionColors[option] or nil
			local optionButton = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = "@FontMedium", TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = token("TextDim"),
				Text = tostring(option),
				LayoutOrder = index + 1,
				Parent = list,
			}, {
				Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Create("UIPadding", { PaddingLeft = UDim.new(0, dotColor and 28 or 10) }),
			})
			if dotColor then
				Create("Frame", {
					Name = "Swatch",
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 10, 0.5, 0),
					Size = UDim2.new(0, 10, 0, 10),
					BackgroundColor3 = dotColor,
					BorderSizePixel = 0,
					Parent = optionButton,
				}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			end
			T(optionButton, "BackgroundColor3", "Hover")
			T(optionButton, "TextColor3", "TextDim")
			optionButton.MouseEnter:Connect(function()
				Utility.Tween(optionButton, Utility.TweenFast, { BackgroundTransparency = 0, TextColor3 = token("Text") })
			end)
			optionButton.MouseLeave:Connect(function()
				Utility.Tween(optionButton, Utility.TweenFast, { BackgroundTransparency = 1, TextColor3 = token("TextDim") })
			end)
			Utility.AddPressEffect(optionButton)
			optionButton.Activated:Connect(function()
				selected = option
				renderValue()
				setOpen(false)
				safeCall(config.Callback, selected)
			end)
			optionEntries[index] = { button = optionButton, name = tostring(option):lower() }
		end
		applyFilter()
	end
	renderOptions(options)

	-- Search filter box (CreateDropdown{ Searchable = true }); LayoutOrder 1
	-- keeps it pinned above the option rows.
	if config.Searchable == true then
		searchBox = Create("TextBox", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = token("Surface"),
			ClearTextOnFocus = false,
			Font = "@FontMedium", TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("Text"),
			PlaceholderColor3 = token("TextDim"),
			PlaceholderText = config.SearchPlaceholder or "Search...",
			Text = "",
			LayoutOrder = 1,
			Parent = list,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		})
		T(searchBox, "BackgroundColor3", "Surface")
		T(searchBox, "TextColor3", "Text")
		T(searchBox, "PlaceholderColor3", "TextDim")
		searchBox:GetPropertyChangedSignal("Text"):Connect(applyFilter)
	end

	valueButton.Activated:Connect(function()
		setOpen(not open)
	end)

	local handle = { Root = row }
	function handle:Set(v, silent)
		if table.find(options, v) then
			selected = v
			renderValue()
			if not silent then
				safeCall(config.Callback, v)
			end
		end
	end
	function handle:Get()
		return selected
	end
	-- Swaps the choices at runtime; keeps the selection if still valid.
	function handle:SetOptions(newOptions)
		assert(type(newOptions) == "table" and #newOptions > 0,
			"[Atlas] SetOptions requires a non-empty array")
		options = newOptions
		renderOptions(options)
		if not table.find(options, selected) then
			selected = options[1]
			renderValue()
		end
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Keybind
--------------------------------------------------------------------

function Section:CreateKeybind(config)
	config = config or {}
	local currentBind = config.Default -- Enum.KeyCode or nil
	local listening = false
	local touchOnly = Library.IsTouchOnly()

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Keybind", 110)

	local box = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 90, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("TextDim"),
		Text = touchOnly and "—" or (currentBind and currentBind.Name or "None"),
		Parent = row,
	}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	T(box, "BackgroundColor3", "Surface")
	T(box, "TextColor3", "TextDim")
	Utility.AddPressEffect(box)

	box.Activated:Connect(function()
		if touchOnly then
			Library:Notify({ Title = "Keybind", Text = "Keybinds need a physical keyboard.", Duration = 2.5 })
			return
		end
		if listening then
			return
		end
		listening = true
		box.Text = "…"
	end)

	Utility.OnInput("Began", box, function(input, gameProcessed)
		if listening then
			local t = input.UserInputType
			-- Keyboard and controller pad 1 — gamepad buttons ARE KeyCodes
			-- (ButtonA..ButtonR3), so captures and triggers share one path.
			if t == Enum.UserInputType.Keyboard or t == Enum.UserInputType.Gamepad1 then
				if input.KeyCode ~= Enum.KeyCode.Escape then
					currentBind = input.KeyCode
				end
				listening = false
				box.Text = currentBind and currentBind.Name or "None"
			end
			return
		end
		if gameProcessed then
			return
		end
		if currentBind ~= nil and input.KeyCode == currentBind then
			safeCall(config.Callback, currentBind)
		end
	end)

	local handle = { Root = row }
	function handle:Set(key)
		currentBind = key
		box.Text = key and key.Name or "None"
	end
	function handle:Get()
		return currentBind
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Text Input
--------------------------------------------------------------------

function Section:CreateInput(config)
	config = config or {}
	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Input", 170)

	local stroke = Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})

	local box = Create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = config.Placeholder or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Default or "",
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		stroke,
	})
	T(box, "BackgroundColor3", "Surface")
	T(box, "TextColor3", "Text")
	T(box, "PlaceholderColor3", "TextDim")

	box.Focused:Connect(function()
		Utility.Tween(stroke, Utility.TweenFast, { Color = token("Accent") })
	end)
	box.FocusLost:Connect(function(enterPressed)
		Utility.Tween(stroke, Utility.TweenFast, { Color = token("Stroke") })
		if config.Numeric == true then
			-- Sanitize to a plain number and clamp into Min/Max on commit.
			local n = tonumber((box.Text:gsub(",", ".")):match("[%+%-]?[%d%.]+"))
			if n ~= nil then
				if config.Min then n = math.max(config.Min, n) end
				if config.Max then n = math.min(config.Max, n) end
				box.Text = tostring(math.floor(n * 100 + 0.5) / 100)
			else
				box.Text = config.Default or ""
			end
		end
		if enterPressed then
			safeCall(config.Callback, box.Text)
		end
	end)

	local handle = { Root = row }
	function handle:Set(text)
		box.Text = tostring(text)
	end
	function handle:Get()
		return box.Text
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Label / Paragraph
--------------------------------------------------------------------

function Section:CreateLabel(config)
	config = config or {}
	local tokenName = config.Dim == false and "Text" or "TextDim"
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@Font", TextSize = config.TextSize or 12,
		RichText = true, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token(tokenName),
		Text = config.Text or "",
		Parent = self._body,
	})
	T(label, "TextColor3", tokenName)

	local handle = { Root = label }
	function handle:SetText(text)
		label.Text = tostring(text)
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Paragraph (titled text card)
--------------------------------------------------------------------

function Section:CreateParagraph(config)
	config = config or {}
	local card = Create("Frame", {
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card, "BackgroundColor3", "SurfaceAlt")

	local titleLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@FontBold", TextSize = 13,
		RichText = true, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Paragraph",
		LayoutOrder = 1,
		Parent = card,
	})
	T(titleLabel, "TextColor3", "Text")

	local bodyLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@Font", TextSize = 12,
		RichText = true, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = config.Text or "",
		LayoutOrder = 2,
		Parent = card,
	})
	T(bodyLabel, "TextColor3", "TextDim")

	local handle = { Root = card }
	function handle:SetText(text)
		bodyLabel.Text = tostring(text)
	end
	function handle:SetTitle(text)
		titleLabel.Text = tostring(text)
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Segmented Control
--------------------------------------------------------------------

function Section:CreateSegmented(config)
	config = config or {}
	local options = config.Options or {}
	assert(#options >= 2, "[Atlas] CreateSegmented requires at least two options")
	local selected = config.Default or options[1]

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Options", (config.Width or 200) + 12)

	local group = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, config.Width or 200, 0, 24),
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
			PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2),
		}),
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalFlex = Enum.UIFlexAlignment.Fill,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	T(group, "BackgroundColor3", "Surface")

	local buttons = {}
	local refresh

	for index, option in ipairs(options) do
		local b = Create("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = token("Accent"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 12,
			TextColor3 = token("TextDim"),
			Text = tostring(option),
			Parent = group,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
		buttons[option] = b
		Utility.AddPressEffect(b)
		b.Activated:Connect(function()
			if selected == option then
				return
			end
			selected = option
			refresh()
			safeCall(config.Callback, selected)
		end)
	end

	refresh = function()
		for option, b in pairs(buttons) do
			local active = (option == selected)
			b.BackgroundTransparency = active and 0 or 1
			b.BackgroundColor3 = active and token("Accent") or token("Hover")
			b.TextColor3 = active and token("OnAccent") or token("TextDim")
		end
	end
	bind(refresh)
	refresh()

	local handle = { Root = row }
	function handle:Set(v, silent)
		if buttons[v] then
			selected = v
			refresh()
			if not silent then
				safeCall(config.Callback, v)
			end
		end
	end
	function handle:Get()
		return selected
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Multi-Select Dropdown
--------------------------------------------------------------------

function Section:CreateMultiDropdown(config)
	config = config or {}
	local options = config.Options or {}
	assert(#options > 0, "[Atlas] CreateMultiDropdown requires a non-empty Options array")
	local selectedSet = {}
	for _, v in ipairs(config.Default or {}) do
		selectedSet[v] = true
	end
	local open = false

	local function getList()
		local out = {}
		for _, option in ipairs(options) do
			if selectedSet[option] then
				table.insert(out, tostring(option))
			end
		end
		return out
	end

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Multi-Select", 170)

	local valueButton = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("Text"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	T(valueButton, "BackgroundColor3", "Surface")
	T(valueButton, "TextColor3", "Text")
	Utility.AddPressEffect(valueButton)

	local function renderValue()
		local listItems = getList()
		valueButton.Text = (#listItems > 0 and table.concat(listItems, ", ") or "None") .. "  ▾"
	end
	renderValue()

	local list = Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(list, "BackgroundColor3", "SurfaceAlt")

	local optionButtons = {}
	local function repaintAll()
		for option, b in pairs(optionButtons) do
			b.Text = (selectedSet[option] and "✓  " or "") .. tostring(option)
			b.TextColor3 = selectedSet[option] and token("Text") or token("TextDim")
		end
	end

	for index, option in ipairs(options) do
		-- OptionColors{ [option] = Color3 }: swatch dot, same language as Dropdown.
		local dotColor = type(config.OptionColors) == "table" and config.OptionColors[option] or nil
		local b = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = token("Hover"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("TextDim"),
			LayoutOrder = index + 1,
			Parent = list,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, dotColor and 28 or 10) }),
		})
		if dotColor then
			Create("Frame", {
				Name = "Swatch",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Size = UDim2.new(0, 10, 0, 10),
				BackgroundColor3 = dotColor,
				BorderSizePixel = 0,
				Parent = b,
			}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
		T(b, "BackgroundColor3", "Hover")
		optionButtons[option] = b
		b.Activated:Connect(function()
			if selectedSet[option] then
				selectedSet[option] = nil
			else
				selectedSet[option] = true
			end
			repaintAll()
			renderValue()
			safeCall(config.Callback, getList())
		end)
		Utility.AddPressEffect(b)
	end
	repaintAll()

	-- Search filter box (CreateMultiDropdown{ Searchable = true }),
	-- pinned above the options by LayoutOrder 1.
	local searchBox
	if config.Searchable == true then
		searchBox = Create("TextBox", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = token("Surface"),
			ClearTextOnFocus = false,
			Font = "@FontMedium", TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("Text"),
			PlaceholderColor3 = token("TextDim"),
			PlaceholderText = config.SearchPlaceholder or "Search...",
			Text = "",
			LayoutOrder = 1,
			Parent = list,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		})
		T(searchBox, "BackgroundColor3", "Surface")
		T(searchBox, "TextColor3", "Text")
		T(searchBox, "PlaceholderColor3", "TextDim")
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = searchBox.Text:lower()
			for option, b in pairs(optionButtons) do
				b.Visible = query == "" or tostring(option):lower():find(query, 1, true) ~= nil
			end
		end)
	end

	valueButton.Activated:Connect(function()
		open = not open
		list.Visible = open
		if open and searchBox then
			searchBox:CaptureFocus()
		elseif not open and searchBox and searchBox.Text ~= "" then
			searchBox.Text = "" -- reopen with a clean filter next time
		end
	end)

	local handle = { Root = row }
	function handle:Set(values)
		selectedSet = {}
		for _, v in ipairs(values or {}) do
			selectedSet[v] = true
		end
		repaintAll()
		renderValue()
	end
	function handle:Get()
		return getList()
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Number Stepper
--------------------------------------------------------------------

function Section:CreateStepper(config)
	config = config or {}
	local minV = config.Min or 0
	local maxV = config.Max or 100
	local step = config.Step or 1
	local value = Utility.Clamp(config.Default or minV, minV, maxV)

	local function format(v)
		return step >= 1 and string.format("%d", v) or string.format("%.2f", v)
	end

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Number", 130)

	local group = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 118, 0, 24),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function smallButton(symbol, order)
		local b = Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = token("Surface"),
			AutoButtonColor = false,
			Font = "@FontBold", TextSize = 14,
			TextColor3 = token("Text"), Text = symbol,
			Parent = group,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		T(b, "BackgroundColor3", "Surface")
		T(b, "TextColor3", "Text")
		Utility.AddPressEffect(b)
		return b
	end

	local minus = smallButton("−", 1)
	local box = Create("TextBox", {
		LayoutOrder = 2,
		Size = UDim2.new(0, 58, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("Text"),
		Text = format(value),
		Parent = group,
	}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	T(box, "BackgroundColor3", "Surface")
	T(box, "TextColor3", "Text")
	local plus = smallButton("+", 3)

	local function commit(v, fire)
		v = Utility.Clamp(Utility.Round(v, step), minV, maxV)
		if v ~= value then
			value = v
			box.Text = format(v)
			if fire ~= false then
				safeCall(config.Callback, v)
			end
		else
			box.Text = format(v)
		end
	end

	minus.Activated:Connect(function()
		commit(value - step)
	end)
	plus.Activated:Connect(function()
		commit(value + step)
	end)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			local n = tonumber(box.Text)
			if n then
				commit(n)
			else
				box.Text = format(value)
			end
		else
			box.Text = format(value)
		end
	end)

	local handle = { Root = row }
	function handle:Set(v, silent)
		commit(v, not silent)
	end
	function handle:Get()
		return value
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Progress Bar
--------------------------------------------------------------------

function Section:CreateProgress(config)
	config = config or {}
	local progress = Utility.Clamp(config.Default or 0, 0, 1)
	local showPercent = config.ShowPercent ~= false

	local row = sectionRow(self, 46)
	local label = rowLabel(row, config.Title or "Progress", 60)
	label.Size = UDim2.new(1, -60, 0, 18)

	local percentLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 56, 0, 18),
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("TextDim"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = showPercent and string.format("%d%%", progress * 100) or "",
		Visible = showPercent,
		Parent = row,
	})
	T(percentLabel, "TextColor3", "TextDim")

	local track = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = row,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "Stroke")

	local fill = Create("Frame", {
		Size = UDim2.fromScale(progress, 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	bind(function()
		fill.BackgroundColor3 = token("Accent")
	end)

	local handle = { Root = row }
	function handle:SetProgress(p, instant)
		p = Utility.Clamp(p, 0, 1)
		progress = p
		if instant then
			fill.Size = UDim2.fromScale(p, 1)
		else
			Utility.Tween(fill, Utility.TweenFast, { Size = UDim2.fromScale(p, 1) })
		end
		if showPercent then
			percentLabel.Text = string.format("%d%%", math.floor(p * 100 + 0.5))
		end
	end
	-- Marquee mode: indeterminate indicator — a pill sweeps the track back
	-- and forth until cleared (waiting on something with unknown duration).
	local marqueePill

	function handle:SetMarquee(on)
		on = on == true
		if on and marqueePill == nil then
			fill.Visible = false
			local pill = Create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.new(0.3, 0, 1, 0),
				BackgroundColor3 = token("Accent"),
				BorderSizePixel = 0,
				Parent = track,
			}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			T(pill, "BackgroundColor3", "Accent")
			marqueePill = pill
			local sweep = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			task.spawn(function() -- timed loop: survives target destruction cleanly
				while marqueePill == pill and pill.Parent do
					Utility.Tween(pill, sweep, { Position = UDim2.new(0.7, 0, 0.5, 0) })
					task.wait(0.95)
					if marqueePill ~= pill or pill.Parent == nil then
						break
					end
					Utility.Tween(pill, sweep, { Position = UDim2.new(0, 0, 0.5, 0) })
					task.wait(0.95)
				end
			end)
		elseif not on and marqueePill then
			marqueePill:Destroy()
			marqueePill = nil
			fill.Visible = true
		end
	end

	function handle:SetLabel(t)
		label.Text = tostring(t)
	end
	function handle:Get()
		return progress
	end
	Library:_registerFlag(config.Flag, handle)
	if config.Marquee == true then
		handle:SetMarquee(true)
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Color Picker
--------------------------------------------------------------------

local function colorToHex(c)
	return string.format("#%02X%02X%02X",
		math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToColor(text)
	local hex = tostring(text):gsub("#", ""):upper()
	if #hex == 3 then
		hex = hex:gsub("(.)", "%1%1")
	end
	if #hex ~= 6 or hex:find("[^0-9A-F]") then
		return nil
	end
	return Color3.fromRGB(
		tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
	)
end

local function rainbowSequence()
	local points = {}
	for i = 0, 12 do
		table.insert(points, ColorSequenceKeypoint.new(i / 12, Color3.fromHSV(i / 12, 1, 1)))
	end
	return ColorSequence.new(points)
end

function Section:CreateColorPicker(config)
	config = config or {}
	local open = false
	-- ThemeToken links the picker to a live theme token: it seeds the
	-- default and re-syncs the swatch whenever the theme is rewritten
	-- (SetTheme/SetToken/ResetTheme), silently, without firing Callback.
	local linkedToken = type(config.ThemeToken) == "string" and config.ThemeToken or nil
	local default = config.Default
	if default == nil and linkedToken then
		local value = token(linkedToken)
		if typeof(value) == "Color3" then
			default = value
		end
	end
	local h, s, v = (default or Color3.fromRGB(237, 66, 69)):ToHSV()
	local color = Color3.fromHSV(h, s, v)

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Color", 60)

	local swatch = Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 44, 0, 22),
		BackgroundColor3 = color,
		AutoButtonColor = false, Text = "",
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIStroke", {
			Thickness = 1, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	local panel = Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(panel, "BackgroundColor3", "SurfaceAlt")

	-- Saturation/Value square ------------------------------------------------
	local svFrame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		Parent = panel,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(0, 0, 0),
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		}),
	})
	local svDot = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 5,
		Parent = svFrame,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIStroke", { Thickness = 2, Color = Color3.new(0.1, 0.1, 0.1) }),
	})
	local svHit = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Text = "", ZIndex = 6, Parent = svFrame,
	})

	-- Hue track ----------------------------------------------------------------
	local hueTrack = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, LayoutOrder = 1,
		Parent = panel,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIGradient", { Color = rainbowSequence() }),
	})
	local hueKnob = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 5,
		Parent = hueTrack,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Create("UIStroke", { Thickness = 2, Color = Color3.new(0.1, 0.1, 0.1) }),
	})
	local hueHit = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Text = "", ZIndex = 6, Parent = hueTrack,
	})

	-- Hex entry + preset swatches -----------------------------------------------
	local bottomRow = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1, LayoutOrder = 2,
		Parent = panel,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local hexBox = Create("TextBox", {
		Size = UDim2.new(0, 78, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("Text"),
		Parent = bottomRow,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	T(hexBox, "BackgroundColor3", "Surface")
	T(hexBox, "TextColor3", "Text")

	local applyAll
	local applyingHex = false

	local presets = {
		Color3.fromRGB(237, 66, 69), Color3.fromRGB(250, 168, 26),
		Color3.fromRGB(67, 181, 129), Color3.fromRGB(59, 130, 246),
		token("Accent"), Color3.fromRGB(168, 85, 247),
	}
	for i, preset in ipairs(presets) do
		local p = Create("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = preset,
			AutoButtonColor = false, Text = "",
			Parent = bottomRow,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		if i == 5 then -- the Accent preset follows live theme edits
			T(p, "BackgroundColor3", "Accent")
		end
		p.Activated:Connect(function()
			local chosen = (i == 5 and token("Accent")) or preset
			if typeof(chosen) == "Color3" then
				h, s, v = chosen:ToHSV()
				applyAll(true)
			end
		end)
	end

	applyAll = function(fire, skipHex)
		color = Color3.fromHSV(h, s, v)
		svFrame.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svDot.Position = UDim2.fromScale(s, 1 - v)
		hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
		swatch.BackgroundColor3 = color
		if not (applyingHex or skipHex) then
			hexBox.Text = colorToHex(color)
		end
		if fire then
			safeCall(config.Callback, color)
		end
	end

	hexBox.Focused:Connect(function()
		applyingHex = true
	end)
	hexBox.FocusLost:Connect(function(enterPressed)
		applyingHex = false
		if enterPressed then
			local parsed = hexToColor(hexBox.Text)
			if parsed then
				h, s, v = parsed:ToHSV()
				applyAll(true)
				return
			end
		end
		hexBox.Text = colorToHex(color)
	end)

	-- Drag wiring --------------------------------------------------------------
	local activeDrag -- "sv" | "hue" | nil
	local function dragUpdate(input)
		if activeDrag == "sv" then
			s = Utility.Clamp((input.Position.X - svFrame.AbsolutePosition.X) / math.max(svFrame.AbsoluteSize.X, 1), 0, 1)
			v = 1 - Utility.Clamp((input.Position.Y - svFrame.AbsolutePosition.Y) / math.max(svFrame.AbsoluteSize.Y, 1), 0, 1)
			applyAll(true)
		elseif activeDrag == "hue" then
			h = Utility.Clamp((input.Position.X - hueTrack.AbsolutePosition.X) / math.max(hueTrack.AbsoluteSize.X, 1), 0, 0.999)
			applyAll(true)
		end
	end
	svHit.InputBegan:Connect(function(i)
		if Utility.IsPrimary(i) then
			activeDrag = "sv"
			dragUpdate(i)
		end
	end)
	hueHit.InputBegan:Connect(function(i)
		if Utility.IsPrimary(i) then
			activeDrag = "hue"
			dragUpdate(i)
		end
	end)
	Utility.OnInput("Ended", row, function(i)
		if Utility.IsPrimary(i) then
			activeDrag = nil
		end
	end)
	Utility.OnInput("Changed", row, function(i)
		if activeDrag and (i.UserInputType == Enum.UserInputType.MouseMovement
			or i.UserInputType == Enum.UserInputType.Touch) then
			dragUpdate(i)
		end
	end)

	swatch.Activated:Connect(function()
		open = not open
		panel.Visible = open
	end)

	local handle = { Root = row }
	function handle:Set(c)
		h, s, v = c:ToHSV()
		applyAll(false)
		-- Linked pickers push restores/programmatic sets INTO the token so the
		-- next retheme (from any other control) can't yank the swatch back.
		if linkedToken then
			local theme = Theme.Tokens[Library._themeName]
			if theme and theme[linkedToken] ~= nil and theme[linkedToken] ~= color then
				Library:SetToken(linkedToken, color)
			end
		end
	end
	function handle:Get()
		return color
	end
	if linkedToken then
		Library:OnThemeChanged(function()
			local value = token(linkedToken)
			if typeof(value) == "Color3" and value ~= color then
				h, s, v = value:ToHSV() -- pull only; never pushes back (no cycles)
				applyAll(false)
			end
		end)
	end
	Library:_registerFlag(config.Flag, handle)
	applyAll(false)
	return handle
end

--------------------------------------------------------------------
-- Component: Switch (labeled on/off — shows custom text per state)
--------------------------------------------------------------------

function Section:CreateSwitch(config)
	config = config or {}
	local state = config.Default == true
	local onText = config.OnText or "On"
	local offText = config.OffText or "Off"

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Switch", 130)

	local group = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 120, 0, 24),
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		Parent = row,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIStroke", {
			Thickness = 1, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
	T(group, "BackgroundColor3", "Surface")
	T(group:FindFirstChildOfClass("UIStroke"), "Color", "Stroke")

	local indicator = Create("Frame", {
		Name = "Indicator",
		Position = UDim2.new(0, 2, 0, 2),
		Size = UDim2.new(0.5, -3, 1, -4),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = group,
	}, { Create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	bind(function()
		indicator.BackgroundColor3 = token("Accent")
	end)

	local offLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = "@FontMedium", TextSize = 11,
		TextColor3 = token("TextDim"),
		Text = offText,
		Parent = group,
	})
	T(offLabel, "TextColor3", "TextDim")

	local onLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Font = "@FontMedium", TextSize = 11,
		TextColor3 = token("OnAccent"),
		Text = onText,
		Parent = group,
	})

	local hit = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "",
		ZIndex = 3, Parent = group,
	})

	local function apply(instant)
		local indicatorGoal = state
			and { Position = UDim2.new(0.5, 1, 0, 2) }
			or { Position = UDim2.new(0, 2, 0, 2) }
		local onGoal = state and token("OnAccent") or token("TextDim")
		local offGoal = state and token("TextDim") or token("OnAccent")
		if instant then
			indicator.Position = indicatorGoal.Position
			onLabel.TextColor3 = onGoal
			offLabel.TextColor3 = offGoal
		else
			Utility.Tween(indicator, Utility.TweenFast, indicatorGoal)
			Utility.Tween(onLabel, Utility.TweenFast, { TextColor3 = onGoal })
			Utility.Tween(offLabel, Utility.TweenFast, { TextColor3 = offGoal })
		end
	end
	bind(function()
		apply(true)
	end)

	local handle = { Root = row }
	function handle:Set(newState, silent)
		newState = newState == true
		if newState == state then
			return
		end
		state = newState
		apply(false)
		if not silent then
			safeCall(config.Callback, state)
		end
	end
	function handle:Get()
		return state
	end
	hit.Activated:Connect(function()
		handle:Set(not state)
	end)
	Utility.AddPressEffect(hit)
	Library:_registerFlag(config.Flag, handle)
	apply(true)
	return handle
end

--------------------------------------------------------------------
-- Component: TextArea (multi-line text input)
--------------------------------------------------------------------

function Section:CreateTextArea(config)
	config = config or {}
	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local title = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Text",
		Parent = holder,
	})
	T(title, "TextColor3", "Text")

	local stroke = Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
	T(stroke, "Color", "Stroke")

	local box = Create("TextBox", {
		Size = UDim2.new(1, 0, 0, config.Height or 80),
		BackgroundColor3 = token("SurfaceAlt"),
		ClearTextOnFocus = false,
		MultiLine = true,
		TextWrapped = true,
		Font = "@Font", TextSize = 12,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = config.Placeholder or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = config.Default or "",
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		}),
		stroke,
	})
	T(box, "BackgroundColor3", "SurfaceAlt")
	T(box, "TextColor3", "Text")
	T(box, "PlaceholderColor3", "TextDim")

	box.Focused:Connect(function()
		Utility.Tween(stroke, Utility.TweenFast, { Color = token("Accent") })
	end)
	box.FocusLost:Connect(function(enterPressed)
		Utility.Tween(stroke, Utility.TweenFast, { Color = token("Stroke") })
		safeCall(config.Callback, box.Text)
	end)

	-- Character limit display (optional).
	local charLabel
	if config.MaxLength and type(config.MaxLength) == "number" then
		charLabel = Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 12),
			Font = "@Font", TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = token("TextDim"),
			Text = ("%d / %d"):format(#box.Text, config.MaxLength),
			LayoutOrder = 2,
			Parent = holder,
		})
		T(charLabel, "TextColor3", "TextDim")
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > config.MaxLength then
				box.Text = box.Text:sub(1, config.MaxLength)
			end
			charLabel.Text = ("%d / %d"):format(#box.Text, config.MaxLength)
		end)
	end

	local handle = { Root = holder }
	function handle:Set(text)
		box.Text = tostring(text)
	end
	function handle:Get()
		return box.Text
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Range Slider (dual-thumb min/max)
--------------------------------------------------------------------

function Section:CreateRangeSlider(config)
	config = config or {}
	local minV = config.Min or 0
	local maxV = config.Max or 100
	local step = config.Step or 1
	local suffix = config.Suffix or ""
	local lo = Utility.Clamp(config.DefaultMin or minV, minV, maxV)
	local hi = Utility.Clamp(config.DefaultMax or maxV, minV, maxV)
	if lo > hi then
		lo, hi = hi, lo
	end

	local function format(v)
		if step >= 1 then
			return string.format("%d%s", v, suffix)
		end
		return string.format("%.2f%s", v, suffix)
	end

	local function percent(v)
		if maxV <= minV then
			return 0
		end
		return (v - minV) / (maxV - minV)
	end

	local row = sectionRow(self, 50)
	local label = rowLabel(row, config.Title or "Range", 120)
	label.Size = UDim2.new(1, -120, 0, 20)

	local valueLabel = Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 116, 0, 20),
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("TextDim"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = format(lo) .. " – " .. format(hi),
		Parent = row,
	})
	T(valueLabel, "TextColor3", "TextDim")

	local track = Create("Frame", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = row,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "Stroke")

	local fill = Create("Frame", {
		Position = UDim2.fromScale(percent(lo), 0),
		Size = UDim2.fromScale(percent(hi) - percent(lo), 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	bind(function()
		fill.BackgroundColor3 = token("Accent")
	end)

	local function makeKnob(initP)
		return Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(initP, 0, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0, ZIndex = 2,
			Parent = track,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIStroke", {
				Thickness = 1, Color = token("Stroke"),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	local knobLo = makeKnob(percent(lo))
	local knobHi = makeKnob(percent(hi))

	local hit = Create("TextButton", {
		BackgroundTransparency = 1, Text = "",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3, Parent = row,
	})

	local activeDrag -- "lo" | "hi" | nil

	local function refresh()
		local pLo = percent(lo)
		local pHi = percent(hi)
		fill.Position = UDim2.fromScale(pLo, 0)
		fill.Size = UDim2.fromScale(pHi - pLo, 1)
		knobLo.Position = UDim2.new(pLo, 0, 0.5, 0)
		knobHi.Position = UDim2.new(pHi, 0, 0.5, 0)
		valueLabel.Text = format(lo) .. " – " .. format(hi)
	end

	local function updateFromInput(input)
		local width = math.max(track.AbsoluteSize.X, 1)
		local p = Utility.Clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		local v = Utility.Clamp(Utility.Round(minV + p * (maxV - minV), step), minV, maxV)
		if activeDrag == "lo" then
			lo = math.min(v, hi)
		elseif activeDrag == "hi" then
			hi = math.max(v, lo)
		end
		refresh()
		safeCall(config.Callback, lo, hi)
	end

	hit.InputBegan:Connect(function(input)
		if not Utility.IsPrimary(input) then
			return
		end
		-- Determine which knob is closer to the click.
		local width = math.max(track.AbsoluteSize.X, 1)
		local p = Utility.Clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		local v = minV + p * (maxV - minV)
		if math.abs(v - lo) <= math.abs(v - hi) then
			activeDrag = "lo"
		else
			activeDrag = "hi"
		end
		updateFromInput(input)
	end)
	Utility.OnInput("Ended", hit, function(input)
		if Utility.IsPrimary(input) then
			activeDrag = nil
		end
	end)
	Utility.OnInput("Changed", hit, function(input)
		if activeDrag and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input)
		end
	end)

	local handle = { Root = row }
	function handle:Set(newLo, newHi, silent)
		lo = Utility.Clamp(Utility.Round(newLo or lo, step), minV, maxV)
		hi = Utility.Clamp(Utility.Round(newHi or hi, step), minV, maxV)
		if lo > hi then
			lo, hi = hi, lo
		end
		refresh()
		if not silent then
			safeCall(config.Callback, lo, hi)
		end
	end
	function handle:Get()
		return lo, hi
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: RadioGroup (exclusive radio buttons)
--------------------------------------------------------------------

function Section:CreateRadioGroup(config)
	config = config or {}
	local options = config.Options or {}
	assert(#options >= 2, "[Atlas] CreateRadioGroup requires at least two options")
	local selected = config.Default or options[1]

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Header label
	Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 18),
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Choice",
		Parent = holder,
	})

	local radioButtons = {}
	local radioOuters = {}
	local radioInners = {}

	local function repaint()
		for option, _ in pairs(radioButtons) do
			local active = (option == selected)
			local inner = radioInners[option]
			if inner then
				Utility.Tween(inner, Utility.TweenFast, {
					Size = active and UDim2.new(0, 10, 0, 10) or UDim2.new(0, 0, 0, 0),
					BackgroundTransparency = active and 0 or 1,
				})
			end
			local labelObj = radioButtons[option]
			if labelObj then
				labelObj.TextColor3 = active and token("Text") or token("TextDim")
			end
		end
	end
	bind(repaint)

	for index, option in ipairs(options) do
		local rowFrame = Create("Frame", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			Parent = holder,
		})

		local outer = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 18, 0, 18),
			BackgroundColor3 = token("Surface"),
			BorderSizePixel = 0,
			Parent = rowFrame,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIStroke", {
				Thickness = 1, Color = token("Stroke"),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
		T(outer, "BackgroundColor3", "Surface")
		T(outer:FindFirstChildOfClass("UIStroke"), "Color", "Stroke")
		radioOuters[option] = outer

		local inner = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = (option == selected) and UDim2.new(0, 10, 0, 10) or UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = token("Accent"),
			BackgroundTransparency = (option == selected) and 0 or 1,
			BorderSizePixel = 0, ZIndex = 2,
			Parent = outer,
		}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		bind(function()
			inner.BackgroundColor3 = token("Accent")
		end)
		radioInners[option] = inner

		local lbl = Create("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 26, 0, 0),
			Size = UDim2.new(1, -26, 1, 0),
			Font = "@FontMedium", TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = (option == selected) and token("Text") or token("TextDim"),
			Text = tostring(option),
			Parent = rowFrame,
		})
		radioButtons[option] = lbl

		local hit = Create("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1, Text = "",
			ZIndex = 3, Parent = rowFrame,
		})
		hit.Activated:Connect(function()
			if selected == option then
				return
			end
			selected = option
			repaint()
			safeCall(config.Callback, selected)
		end)
	end

	local handle = { Root = holder }
	function handle:Set(v, silent)
		if radioButtons[v] then
			selected = v
			repaint()
			if not silent then
				safeCall(config.Callback, v)
			end
		end
	end
	function handle:Get()
		return selected
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Chip / Tag List (inline removable tags)
--------------------------------------------------------------------

function Section:CreateChipList(config)
	config = config or {}
	local tags = {}
	for _, v in ipairs(config.Default or {}) do
		table.insert(tags, tostring(v))
	end

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local title = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = "@FontMedium", TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Tags",
		Parent = holder,
	})
	T(title, "TextColor3", "Text")

	local chipContainer = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Wraps = true,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function renderChips()
		for _, child in ipairs(chipContainer:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		for i, tag in ipairs(tags) do
			local chip = Create("Frame", {
				LayoutOrder = i,
				Size = UDim2.new(0, 0, 0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = token("SurfaceAlt"),
				BorderSizePixel = 0,
				Parent = chipContainer,
			}, {
				Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }),
				Create("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 4),
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			T(chip, "BackgroundColor3", "SurfaceAlt")
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = "@FontMedium", TextSize = 11,
				TextColor3 = token("Text"),
				Text = tag,
				LayoutOrder = 1,
				Parent = chip,
			})
			local removeBtn = Create("TextButton", {
				Size = UDim2.new(0, 16, 0, 16),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = 0.5,
				AutoButtonColor = false,
				Font = "@FontBold", TextSize = 10,
				TextColor3 = token("TextDim"),
				Text = "×",
				LayoutOrder = 2,
				Parent = chip,
			}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			T(removeBtn, "BackgroundColor3", "Hover")
			T(removeBtn, "TextColor3", "TextDim")
			removeBtn.Activated:Connect(function()
				local idx = table.find(tags, tag)
				if idx then
					table.remove(tags, idx)
				end
				renderChips()
				safeCall(config.Callback, tags)
			end)
		end
		-- Empty state
		if #tags == 0 then
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = "@Font", TextSize = 11,
				TextColor3 = token("TextDim"),
				Text = config.EmptyText or "No tags",
				Parent = chipContainer,
			})
		end
	end

	-- Input row for adding new tags
	local inputRow = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 2,
		Parent = holder,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local addBox = Create("TextBox", {
		Size = UDim2.new(1, -60, 0, 26),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = "@Font", TextSize = 12,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = config.Placeholder or "Add tag…",
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		LayoutOrder = 1,
		Parent = inputRow,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	T(addBox, "BackgroundColor3", "Surface")
	T(addBox, "TextColor3", "Text")
	T(addBox, "PlaceholderColor3", "TextDim")

	local addBtn = Create("TextButton", {
		Size = UDim2.new(0, 52, 0, 26),
		BackgroundColor3 = token("Accent"),
		AutoButtonColor = false,
		Font = "@FontMedium", TextSize = 12,
		TextColor3 = token("OnAccent"),
		Text = "Add",
		LayoutOrder = 2,
		Parent = inputRow,
	}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	T(addBtn, "BackgroundColor3", "Accent")
	T(addBtn, "TextColor3", "OnAccent")
	Utility.AddPressEffect(addBtn)

	local function addTag()
		local text = addBox.Text:match("^%s*(.-)%s*$") -- trim
		if text == "" then
			return
		end
		local maxTags = config.MaxTags or 20
		if #tags >= maxTags then
			return
		end
		if not table.find(tags, text) then
			table.insert(tags, text)
			renderChips()
			safeCall(config.Callback, tags)
		end
		addBox.Text = ""
	end

	addBtn.Activated:Connect(addTag)
	addBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			addTag()
		end
	end)

	renderChips()

	local handle = { Root = holder }
	function handle:Set(newTags)
		tags = {}
		for _, v in ipairs(newTags or {}) do
			table.insert(tags, tostring(v))
		end
		renderChips()
	end
	function handle:Get()
		return tags
	end
	function handle:Add(tag)
		if type(tag) == "string" and tag ~= "" and not table.find(tags, tag) then
			table.insert(tags, tag)
			renderChips()
		end
	end
	function handle:Remove(tag)
		local idx = table.find(tags, tag)
		if idx then
			table.remove(tags, idx)
			renderChips()
		end
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: Accordion (collapsible content panels)
--------------------------------------------------------------------

function Section:CreateAccordion(config)
	config = config or {}
	local items = config.Items or {}
	assert(#items >= 1, "[Atlas] CreateAccordion requires at least one item")

	local holder = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	-- Optional accordion title
	if config.Title then
		Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 18),
			Font = "@FontMedium", TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("Text"),
			Text = config.Title,
			Parent = holder,
		})
	end

	local openIndex = config.DefaultOpen -- nil = all closed; number = which to open
	local panels = {}

	for i, item in ipairs(items) do
		local itemFrame = Create("Frame", {
			LayoutOrder = i,
			BackgroundColor3 = token("SurfaceAlt"),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = holder,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		})
		T(itemFrame, "BackgroundColor3", "SurfaceAlt")

		local headerBtn = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("Text"),
			Text = item.Title or ("Item " .. i),
			Parent = itemFrame,
		}, {
			Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 30) }),
		})
		T(headerBtn, "TextColor3", "Text")

		local chevron = Create("TextLabel", {
			Name = "Chevron",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 14, 0, 14),
			Font = "@FontBold", TextSize = 12,
			TextColor3 = token("TextDim"),
			Text = "▾",
			Rotation = (openIndex == i) and 0 or -90,
			Parent = headerBtn,
		})
		T(chevron, "TextColor3", "TextDim")

		local content = Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = (openIndex == i),
			Parent = itemFrame,
		}, {
			Create("UIPadding", {
				PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
			}),
		})

		local bodyLabel = Create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = "@Font", TextSize = 12,
			TextWrapped = true, RichText = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("TextDim"),
			Text = item.Text or "",
			Parent = content,
		})
		T(bodyLabel, "TextColor3", "TextDim")

		panels[i] = { frame = itemFrame, content = content, chevron = chevron }

		headerBtn.Activated:Connect(function()
			local isOpen = content.Visible
			-- If Exclusive mode (default), close all others first.
			if config.Exclusive ~= false then
				for j, panel in ipairs(panels) do
					if j ~= i and panel.content.Visible then
						panel.content.Visible = false
						Utility.Tween(panel.chevron, Utility.TweenFast, { Rotation = -90 })
					end
				end
			end
			content.Visible = not isOpen
			Utility.Tween(chevron, Utility.TweenFast, { Rotation = content.Visible and 0 or -90 })
		end)

		headerBtn.MouseEnter:Connect(function()
			Utility.Tween(headerBtn, Utility.TweenFast, { BackgroundTransparency = 0.5 })
		end)
		headerBtn.MouseLeave:Connect(function()
			Utility.Tween(headerBtn, Utility.TweenFast, { BackgroundTransparency = 1 })
		end)
	end

	local handle = { Root = holder }
	function handle:Open(index)
		if panels[index] then
			if config.Exclusive ~= false then
				for j, panel in ipairs(panels) do
					if j ~= index then
						panel.content.Visible = false
						panel.chevron.Rotation = -90
					end
				end
			end
			panels[index].content.Visible = true
			panels[index].chevron.Rotation = 0
		end
	end
	function handle:CloseAll()
		for _, panel in ipairs(panels) do
			panel.content.Visible = false
			panel.chevron.Rotation = -90
		end
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Breadcrumb (navigation path indicator)
--------------------------------------------------------------------

function Section:CreateBreadcrumb(config)
	config = config or {}
	local crumbs = config.Items or { "Home" }

	local row = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = self._body,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 0),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local handle = { Root = row }

	local function rebuild(items)
		for _, child in ipairs(row:GetChildren()) do
			if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		for i, crumb in ipairs(items) do
			local isLast = (i == #items)
			local btn = Create("TextButton", {
				LayoutOrder = i * 2 - 1,
				Size = UDim2.new(0, 0, 0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = isLast and "@FontBold" or "@Font",
				TextSize = 12,
				TextColor3 = isLast and token("Text") or token("Accent"),
				Text = tostring(crumb),
				Parent = row,
			}, {
				Create("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2) }),
			})
			if not isLast then
				btn.Activated:Connect(function()
					safeCall(config.Callback, crumb, i)
				end)
				btn.MouseEnter:Connect(function()
					Utility.Tween(btn, Utility.TweenFast, { TextColor3 = token("Text") })
				end)
				btn.MouseLeave:Connect(function()
					Utility.Tween(btn, Utility.TweenFast, { TextColor3 = token("Accent") })
				end)
				-- Separator
				Create("TextLabel", {
					LayoutOrder = i * 2,
					Size = UDim2.new(0, 16, 0, 24),
					BackgroundTransparency = 1,
					Font = "@Font", TextSize = 12,
					TextColor3 = token("TextDim"),
					Text = "›",
					Parent = row,
				})
			end
		end
	end
	rebuild(crumbs)

	function handle:SetItems(items)
		crumbs = items or {}
		rebuild(crumbs)
	end
	function handle:Get()
		return crumbs
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Rating (star selector, 1–N)
--------------------------------------------------------------------

function Section:CreateRating(config)
	config = config or {}
	local maxStars = config.Max or 5
	local current = Utility.Clamp(config.Default or 0, 0, maxStars)

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Rating", maxStars * 24 + 10)

	local starGroup = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, maxStars * 24, 0, 24),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local stars = {}
	local function repaint()
		for i, star in ipairs(stars) do
			star.Text = i <= current and "★" or "☆"
			star.TextColor3 = i <= current and token("Accent") or token("TextDim")
		end
	end

	for i = 1, maxStars do
		local star = Create("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, 22, 0, 24),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = "@FontBold", TextSize = 18,
			TextColor3 = i <= current and token("Accent") or token("TextDim"),
			Text = i <= current and "★" or "☆",
			Parent = starGroup,
		})
		star.Activated:Connect(function()
			-- Clicking the same star again deselects (goes to 0).
			if current == i then
				current = 0
			else
				current = i
			end
			repaint()
			safeCall(config.Callback, current)
		end)
		star.MouseEnter:Connect(function()
			-- Preview: fill stars up to hover point.
			for j, s in ipairs(stars) do
				s.Text = j <= i and "★" or "☆"
				s.TextColor3 = j <= i and token("Accent") or token("TextDim")
			end
		end)
		star.MouseLeave:Connect(function()
			repaint()
		end)
		stars[i] = star
	end
	bind(repaint)

	local handle = { Root = row }
	function handle:Set(v, silent)
		current = Utility.Clamp(math.floor(tonumber(v) or 0), 0, maxStars)
		repaint()
		if not silent then
			safeCall(config.Callback, current)
		end
	end
	function handle:Get()
		return current
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Component: TimePicker (hours : minutes with steppers)
--------------------------------------------------------------------

function Section:CreateTimePicker(config)
	config = config or {}
	local hour = Utility.Clamp(config.DefaultHour or 12, 0, 23)
	local minute = Utility.Clamp(config.DefaultMinute or 0, 0, 59)
	local minuteStep = config.MinuteStep or 1
	local use24h = config.Use24Hour ~= false

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Time", 160)

	local group = Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 148, 0, 24),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 2),
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function formatTime()
		if use24h then
			return string.format("%02d:%02d", hour, minute)
		else
			local h12 = hour % 12
			if h12 == 0 then h12 = 12 end
			local ampm = hour < 12 and "AM" or "PM"
			return string.format("%d:%02d %s", h12, minute, ampm)
		end
	end

	local function smallBtn(symbol, order)
		local b = Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(0, 22, 0, 24),
			BackgroundColor3 = token("Surface"),
			AutoButtonColor = false,
			Font = "@FontBold", TextSize = 13,
			TextColor3 = token("Text"), Text = symbol,
			Parent = group,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		T(b, "BackgroundColor3", "Surface")
		T(b, "TextColor3", "Text")
		Utility.AddPressEffect(b)
		return b
	end

	local display = Create("TextLabel", {
		LayoutOrder = 3,
		Size = UDim2.new(0, 70, 0, 24),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		Font = "@FontMedium", TextSize = 13,
		TextColor3 = token("Text"),
		Text = formatTime(),
		Parent = group,
	}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	T(display, "BackgroundColor3", "SurfaceAlt")
	T(display, "TextColor3", "Text")

	local function fire()
		display.Text = formatTime()
		safeCall(config.Callback, hour, minute)
	end

	local hDown = smallBtn("−", 1)
	local hUp = smallBtn("+", 2)
	-- display is order 3
	local mDown = smallBtn("−", 4)
	local mUp = smallBtn("+", 5)

	hDown.Activated:Connect(function()
		hour = (hour - 1) % 24
		fire()
	end)
	hUp.Activated:Connect(function()
		hour = (hour + 1) % 24
		fire()
	end)
	mDown.Activated:Connect(function()
		minute = (minute - minuteStep) % 60
		fire()
	end)
	mUp.Activated:Connect(function()
		minute = (minute + minuteStep) % 60
		fire()
	end)

	local handle = { Root = row }
	function handle:Set(h, m, silent)
		hour = Utility.Clamp(math.floor(tonumber(h) or hour), 0, 23)
		minute = Utility.Clamp(math.floor(tonumber(m) or minute), 0, 59)
		display.Text = formatTime()
		if not silent then
			safeCall(config.Callback, hour, minute)
		end
	end
	function handle:Get()
		return hour, minute
	end
	Library:_registerFlag(config.Flag, handle)
	return handle
end

--------------------------------------------------------------------
-- Service: Toast Queue (sequential batch notifications)
--------------------------------------------------------------------

-- Atlas:QueueNotifications({ {Title, Text, Duration}, ... })
-- Plays each toast one after the previous dismisses, with a small gap.
function Library:QueueNotifications(list, config)
	assert(type(list) == "table" and #list >= 1,
		"[Atlas] QueueNotifications requires a non-empty list")
	config = config or {}
	local gap = config.Gap or 0.3
	local index = 0
	local function playNext()
		index = index + 1
		if index > #list then
			safeCall(config.OnComplete)
			return
		end
		local item = list[index]
		if type(item) ~= "table" then
			playNext()
			return
		end
		local duration = item.Duration or 3
		self:Notify({
			Title = item.Title or "Notification",
			Text = item.Text or "",
			Duration = duration,
			AccentToken = item.AccentToken,
			Action = item.Action,
		})
		task.delay(duration + gap, playNext)
	end
	playNext()
end

--------------------------------------------------------------------
-- Service: Keyboard Shortcuts
--------------------------------------------------------------------

-- Atlas:AddShortcut({ Keys = { Enum.KeyCode.LeftControl, Enum.KeyCode.S },
--                     Name = "Save", Callback = fn })
-- Returns a handle with :Disconnect().
-- All modifiers must be held at the moment the final key goes down.

Library._shortcuts = Library._shortcuts or {}
local shortcutsConnected = false

local function ensureShortcutsConnected()
	if shortcutsConnected then
		return
	end
	shortcutsConnected = true
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		for _, sc in ipairs(Library._shortcuts) do
			if sc.Enabled == false then
				-- skip disabled shortcuts
			elseif input.KeyCode == sc.TriggerKey then
				local allHeld = true
				for _, mod in ipairs(sc.Modifiers) do
					if not UserInputService:IsKeyDown(mod) then
						allHeld = false
						break
					end
				end
				if allHeld then
					safeCall(sc.Callback)
				end
			end
		end
	end)
end

function Library:AddShortcut(config)
	assert(type(config) == "table" and type(config.Keys) == "table" and #config.Keys >= 1,
		"[Atlas] AddShortcut requires a Keys array (at least one KeyCode)")
	assert(type(config.Callback) == "function",
		"[Atlas] AddShortcut requires a Callback function")
	ensureShortcutsConnected()
	-- Last key in the array is the trigger; the rest are modifiers.
	local keys = config.Keys
	local triggerKey = keys[#keys]
	local modifiers = {}
	for i = 1, #keys - 1 do
		table.insert(modifiers, keys[i])
	end
	local entry = {
		Name = config.Name or "Shortcut",
		Keys = keys,
		TriggerKey = triggerKey,
		Modifiers = modifiers,
		Callback = config.Callback,
		Enabled = true,
	}
	table.insert(self._shortcuts, entry)
	local handle = {}
	function handle:Disconnect()
		entry.Enabled = false
		local idx = table.find(Library._shortcuts, entry)
		if idx then
			table.remove(Library._shortcuts, idx)
		end
	end
	function handle:SetEnabled(on)
		entry.Enabled = on ~= false
	end
	return handle
end

function Library:GetShortcuts()
	local list = {}
	for _, sc in ipairs(self._shortcuts) do
		if sc.Enabled ~= false then
			table.insert(list, { Name = sc.Name, Keys = sc.Keys })
		end
	end
	return list
end

--------------------------------------------------------------------
-- Service: Status Bar (persistent bottom bar with live status text)
--------------------------------------------------------------------

-- Atlas:SetStatusBar({ Text = "Ready", Accent = true })
-- Atlas:SetStatusBarText("Processing...")
-- Atlas:SetStatusBarVisible(bool)

function Library:SetStatusBar(config)
	config = config or {}
	local gui = self:_getGui()

	if self._statusBar == nil then
		local bar = Create("Frame", {
			Name = "AtlasStatusBar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundColor3 = token("Surface"),
			BorderSizePixel = 0,
			ZIndex = 1100,
			Parent = gui,
		}, {
			Create("UIStroke", {
				Thickness = 1, Color = token("Stroke"),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
		T(bar, "BackgroundColor3", "Surface")
		T(bar:FindFirstChildOfClass("UIStroke"), "Color", "Stroke")

		local dot = Create("Frame", {
			Name = "StatusDot",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 12, 0.5, 0),
			Size = UDim2.new(0, 8, 0, 8),
			BackgroundColor3 = token("Accent"),
			BorderSizePixel = 0,
			Visible = false,
			Parent = bar,
		}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		T(dot, "BackgroundColor3", "Accent")

		local label = Create("TextLabel", {
			Name = "StatusText",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 12, 0, 0),
			Size = UDim2.new(1, -24, 1, 0),
			Font = "@FontMedium", TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("TextDim"),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "",
			Parent = bar,
		})
		T(label, "TextColor3", "TextDim")

		self._statusBar = bar
		self._statusDot = dot
		self._statusLabel = label
	end

	local bar = self._statusBar
	local dot = self._statusDot
	local label = self._statusLabel

	if config.Text ~= nil then
		label.Text = tostring(config.Text)
	end
	if config.Accent ~= nil then
		dot.Visible = config.Accent == true
		label.Position = config.Accent
			and UDim2.new(0, 26, 0, 0)
			or UDim2.new(0, 12, 0, 0)
		label.Size = config.Accent
			and UDim2.new(1, -38, 1, 0)
			or UDim2.new(1, -24, 1, 0)
	end
	bar.Visible = config.Visible ~= false
	return bar
end

function Library:SetStatusBarText(text)
	if self._statusLabel then
		self._statusLabel.Text = tostring(text)
	end
end

function Library:SetStatusBarVisible(visible)
	if self._statusBar then
		self._statusBar.Visible = visible == true
	end
end

--------------------------------------------------------------------
-- Service: Tooltips
--------------------------------------------------------------------

function Library:AddTooltip(target, text)
	assert(target and target:IsA("GuiObject"), "[Atlas] AddTooltip expects a GuiObject")
	local gui = self:_getGui()
	local hovering = false
	local tip

	local function hide()
		if tip then
			local t = tip
			tip = nil
			Utility.Tween(t, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
				t:Destroy()
			end)
		end
	end

	local function show()
		if tip ~= nil or target:IsDescendantOf(game) == false then
			return
		end
		tip = Create("CanvasGroup", {
			Name = "Tooltip",
			AnchorPoint = Vector2.new(0.5, 1),
			Size = UDim2.new(0, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = token("Surface"),
			BorderSizePixel = 0,
			GroupTransparency = 1,
			ZIndex = 3000,
			Parent = gui,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Create("UIPadding", {
				PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			}),
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Font = "@Font", TextSize = 12,
				TextColor3 = token("Text"),
				Text = text,
			}),
		})
		T(tip, "BackgroundColor3", "Surface")
		-- Position above the target, but use the mouse X for horizontal
		-- alignment so the tooltip tracks where the user is looking.
		local mousePos = UserInputService:GetMouseLocation()
		local centerX = mousePos.X
		local topY = target.AbsolutePosition.Y - 8
		-- Fallback if the mouse is far from the target (touch scenario):
		if math.abs(centerX - (target.AbsolutePosition.X + target.AbsoluteSize.X / 2)) > target.AbsoluteSize.X then
			centerX = target.AbsolutePosition.X + target.AbsoluteSize.X / 2
		end
		local viewW = gui.AbsoluteSize.X
		tip.Position = UDim2.fromOffset(
			math.clamp(centerX, 90, math.max(viewW - 90, 90)),
			math.max(topY, 8)
		)
		Utility.Tween(tip, Utility.TweenFast, { GroupTransparency = 0 })
	end

	target.MouseEnter:Connect(function()
		hovering = true
		task.delay(0.35, function()
			if hovering then
				show()
			end
		end)
	end)
	target.MouseLeave:Connect(function()
		hovering = false
		hide()
	end)
	-- Touch has no hover: long-press (0.5 s) shows the tip, it stays
	-- readable for 1.5 s after the finger lifts.
	local holdGen = 0
	target.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		holdGen = holdGen + 1
		local gen = holdGen
		task.delay(0.5, function()
			if holdGen == gen then
				show()
			end
		end)
	end)
	target.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		holdGen = holdGen + 1
		local gen = holdGen
		task.delay(1.5, function()
			if holdGen == gen then
				hide()
			end
		end)
	end)
	target.Destroying:Connect(hide)
end

--------------------------------------------------------------------
-- Service: Modal Dialogs
--------------------------------------------------------------------

function Library:Prompt(config)
	config = config or {}
	local gui = self:_getGui()
	local buttons = config.Buttons or { "Cancel", "Confirm" }

	-- Gamepad: the modal is its own selection scope; the previous focus is
	-- restored on close (window group resumes underneath).
	local prevFocus = GuiService.SelectedObject

	local overlay = Create("Frame", {
		Name = "ModalOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Active = true,
		Selectable = false,
		SelectionGroup = true,
		ZIndex = 2000,
		Parent = gui,
	})

	local card = Create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, math.min(config.Width or 340, 340), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 2001,
		Parent = overlay,
	}, {
		Create("UICorner", { CornerRadius = token("Corner") }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card:FindFirstChildOfClass("UICorner"), "CornerRadius", "Corner")
	T(card, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local title = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@FontBold", TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Confirm",
		Parent = card,
	})
	T(title, "TextColor3", "Text")

	local body = Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = "@Font", TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = config.Text or "",
		LayoutOrder = 1,
		Parent = card,
	})
	T(body, "TextColor3", "TextDim")

	-- Optional text field: Prompt{ Input = true, Placeholder, Default } —
	-- the Callback then receives (choice, text). Enter commits as primary.
	local inputBox
	if config.Input == true then
		inputBox = Create("TextBox", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = token("SurfaceAlt"),
			ClearTextOnFocus = false,
			Font = "@FontMedium", TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("Text"),
			PlaceholderColor3 = token("TextDim"),
			PlaceholderText = config.Placeholder or "",
			Text = config.Default or "",
			LayoutOrder = 2,
			Parent = card,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		})
		T(inputBox, "BackgroundColor3", "SurfaceAlt")
		T(inputBox, "TextColor3", "Text")
		T(inputBox, "PlaceholderColor3", "TextDim")
	end

	local buttonRow = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
		Parent = card,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local closed = false
	local escConnection
	local function close(result)
		if closed then
			return
		end
		closed = true
		if escConnection then
			escConnection:Disconnect()
			escConnection = nil
		end
		if Library:_consoleMode() then
			pcall(function()
				GuiService.SelectedObject = prevFocus -- back to the window group
			end)
		end
		Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			overlay:Destroy()
		end)
		safeCall(config.Callback, result, inputBox and inputBox.Text or nil)
	end

	if inputBox then
		inputBox.FocusLost:Connect(function(enterPressed)
			if enterPressed then
				close(buttons[#buttons]) -- Enter = primary action
			end
		end)
	end

	local primaryButton
	for index, label in ipairs(buttons) do
		local isPrimary = (index == #buttons)
		local b = Create("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(0, 88, 0, 30),
			BackgroundColor3 = isPrimary and token("Accent") or token("SurfaceAlt"),
			AutoButtonColor = false,
			Font = "@FontMedium", TextSize = 13,
			TextColor3 = isPrimary and token("OnAccent") or token("Text"),
			Text = tostring(label),
			Parent = buttonRow,
		}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		bind(function()
			b.BackgroundColor3 = isPrimary and token("Accent") or token("SurfaceAlt")
			b.TextColor3 = isPrimary and token("OnAccent") or token("Text")
		end)
		if isPrimary then
			primaryButton = b
		end
		b.Activated:Connect(function()
			close(label)
		end)
	end

	escConnection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape
			or input.KeyCode == Enum.KeyCode.ButtonB then -- controller "back"
			close(nil) -- Escape/B reports no choice
		end
	end)

	Utility.Tween(card, Utility.TweenMed, { GroupTransparency = 0 })
	-- Console: focus the field (input prompts) or the primary action.
	Library:_focus(inputBox or primaryButton)
	return overlay
end

function Library:Alert(config)
	config = config or {}
	config.Buttons = { config.OkLabel or "OK" }
	return self:Prompt(config)
end

--------------------------------------------------------------------
-- Service: Command Palette
--------------------------------------------------------------------

-- Optional Priority: higher floats to the top of every query, ties keep
-- registration order (stable, so muscle memory survives).
local commandCounter = 0

function Library:RegisterCommand(config)
	assert(type(config) == "table" and type(config.Name) == "string",
		"[Atlas] RegisterCommand requires a Name")
	commandCounter = commandCounter + 1
	config._order = commandCounter
	config.Priority = tonumber(config.Priority) or 0
	table.insert(self._commands, config)
end

local paletteState = { open = false }

local function closePalette()
	if not paletteState.open then
		return
	end
	paletteState.open = false
	if paletteState.inputConn then
		paletteState.inputConn:Disconnect()
		paletteState.inputConn = nil
	end
	local overlay = paletteState.overlay
	local card = paletteState.card
	paletteState.overlay = nil
	paletteState.card = nil
	if overlay then
		if card then
			Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 })
		end
		Utility.Tween(overlay, Utility.TweenFast, { BackgroundTransparency = 1 }).Completed:Connect(function()
			overlay:Destroy()
		end)
	end
end

local function openPalette()
	if paletteState.open then
		return
	end
	paletteState.open = true
	local gui = Library:_getGui()

	local overlay = Create("Frame", {
		Name = "PaletteOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Active = true,
		ZIndex = 2500,
		Parent = gui,
	})
	overlay.InputBegan:Connect(function(input)
		if Utility.IsPrimary(input) then
			closePalette()
		end
	end)

	local card = Create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		ZIndex = 2501,
		Parent = overlay,
	}, {
		Create("UICorner", { CornerRadius = token("Corner") }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card:FindFirstChildOfClass("UICorner"), "CornerRadius", "Corner")
	T(card, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local box = Create("TextBox", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = token("SurfaceAlt"),
		ClearTextOnFocus = false,
		Font = "@FontMedium", TextSize = 14,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = "Type a command…",
		Text = "",
		Parent = card,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	T(box, "BackgroundColor3", "SurfaceAlt")
	T(box, "TextColor3", "Text")
	T(box, "PlaceholderColor3", "TextDim")

	local listFrame = Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = card,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

	paletteState.overlay = overlay
	paletteState.card = card
	paletteState.index = 1
	paletteState.results = {}

	local function rebuild()
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local query = string.lower(box.Text)
		paletteState.results = {}
		for _, cmd in ipairs(Library._commands) do
			if query == "" or string.find(string.lower(cmd.Name), query, 1, true) then
				table.insert(paletteState.results, cmd)
			end
		end
		table.sort(paletteState.results, function(a, b)
			if a.Priority ~= b.Priority then
				return a.Priority > b.Priority
			end
			return a._order < b._order
		end)
		paletteState.index = math.clamp(paletteState.index, 1, math.max(#paletteState.results, 1))
		for i, cmd in ipairs(paletteState.results) do
			if i > 8 then
				break
			end
			local rowBtn = Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = (i == paletteState.index) and 0 or 1,
				AutoButtonColor = false, Text = "",
				Parent = listFrame,
			}, { Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
			T(rowBtn, "BackgroundColor3", "Hover")
			Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -130, 1, 0),
				Font = "@FontMedium", TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = token("Text"),
				Text = cmd.Name,
				Parent = rowBtn,
			})
			Create("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0, 110, 1, 0),
				Font = "@Font", TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = token("TextDim"),
				Text = cmd.Category or "",
				Parent = rowBtn,
			})
			Utility.AddPressEffect(rowBtn)
			rowBtn.Activated:Connect(function()
				closePalette()
				safeCall(cmd.Callback)
			end)
		end
	end

	box:GetPropertyChangedSignal("Text"):Connect(rebuild)
	rebuild()
	task.defer(box.CaptureFocus, box)

	-- No gameProcessed filter here: while the box is focused, every keystroke
	-- IS game-processed — filtering would dead-end the arrow keys.
	paletteState.inputConn = UserInputService.InputBegan:Connect(function(input)
		if not paletteState.open then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			closePalette()
		elseif input.KeyCode == Enum.KeyCode.Down then
			paletteState.index = math.min(paletteState.index + 1, math.max(#paletteState.results, 1))
			rebuild()
		elseif input.KeyCode == Enum.KeyCode.Up then
			paletteState.index = math.max(paletteState.index - 1, 1)
			rebuild()
		elseif input.KeyCode == Enum.KeyCode.Return then
			local cmd = paletteState.results[paletteState.index]
			closePalette()
			if cmd then
				safeCall(cmd.Callback)
			end
		end
	end)
end

function Library:OpenPalette()
	openPalette()
end

-- Fades out every active toast immediately.
function Library:DismissNotifications()
	if self._notifHolder == nil then
		return
	end
	for _, child in ipairs(self._notifHolder:GetChildren()) do
		if child:IsA("CanvasGroup") and child.Name == "Notification" then
			local card = child
			Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
				card:Destroy()
			end)
		end
	end
end

--------------------------------------------------------------------
-- Service: Context Menu (right-click / touch long-press, one level of submenus)
--------------------------------------------------------------------

-- One menu at a time: opening a new one closes the old. activeMenu tracks the
-- root panel plus any open submenu chain (panels[1] = root).
local activeMenu = nil

local function measureMenuWidth(items)
	local TextService = game:GetService("TextService")
	local width = 120
	for _, item in ipairs(items) do
		if type(item) == "table" and type(item.Name) == "string" then
			local ok, bounds = pcall(TextService.GetTextSize, TextService,
				item.Name, 13, token("FontMedium"), Vector2.new(4096, 28))
			width = math.max(width, math.min((ok and bounds.X or #item.Name * 7) + 44, 260))
		end
	end
	return width
end

-- Fades out and destroys every panel from `fromIndex` up (submenu chains).
local function closePanelChain(panels, fromIndex)
	for i = #panels, fromIndex, -1 do
		local frame = panels[i]
		panels[i] = nil
		if frame and frame.Parent then
			Utility.Tween(frame, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
				frame:Destroy()
			end)
		end
	end
end

local function closeContextMenu()
	local menu = activeMenu
	if menu == nil then
		return
	end
	activeMenu = nil
	if menu.conn then
		menu.conn:Disconnect()
		menu.conn = nil
	end
	closePanelChain(menu.panels, 1)
end

-- Forward declarations: panels open submenus, submenus are panels.
local buildPanel, openSubmenu

-- depth 0 = root. Returns (frame, width); frame starts transparent, caller
-- positions + reveals it.
buildPanel = function(gui, items, depth)
	local width = measureMenuWidth(items)
	local frame = Create("CanvasGroup", {
		Name = "ContextMenu",
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 2700 + depth, -- above the palette (2500), below the loader (3000)
		Parent = gui,
	}, {
		Create("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIScale", { Scale = 0.96 }), -- grow-in, same language as toasts
	})
	T(frame, "BackgroundColor3", "Surface")
	T(Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame,
	}), "Color", "Stroke")

	for order, item in ipairs(items) do
		if item == "separator" then
			Create("Frame", {
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 9),
				BackgroundTransparency = 1,
				Parent = frame,
			}, {
				Create("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 4, 0.5, 0),
					Size = UDim2.new(1, -8, 0, 1),
					BorderSizePixel = 0,
					BackgroundColor3 = token("Stroke"),
				}),
			})
		elseif type(item) == "table" and type(item.Name) == "string" then
			local hasSub = type(item.Submenu) == "table"
			local labelColor = item.Danger and "Danger" or (item.Disabled and "TextDim" or "Text")
			local row = Create("TextButton", {
				LayoutOrder = order,
				Size = UDim2.new(1, 0, 0, 28),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Font = "@FontMedium", TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = token(labelColor),
				Text = item.Name,
				Parent = frame,
			}, {
				Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
				Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }),
			})
			T(row, "BackgroundColor3", "Hover")
			T(row, "TextColor3", labelColor)
			if hasSub then
				local chevron = Create("TextLabel", {
					Name = "SubChevron",
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.new(0, 14, 1, 0),
					BackgroundTransparency = 1,
					Font = "@FontMedium", TextSize = 12,
					TextColor3 = token("TextDim"),
					Text = "▸",
					Parent = row,
				})
				T(chevron, "TextColor3", "TextDim")
			end
			if not item.Disabled then
				Utility.AddPressEffect(row)
				row.MouseEnter:Connect(function()
					Utility.Tween(row, Utility.TweenFast, { BackgroundTransparency = 0 })
					if activeMenu then
						-- hovering a sibling row collapses deeper panels first
						closePanelChain(activeMenu.panels, depth + 2)
						if hasSub then
							openSubmenu(row, item.Submenu, depth + 1)
						end
					end
				end)
				row.MouseLeave:Connect(function()
					Utility.Tween(row, Utility.TweenFast, { BackgroundTransparency = 1 })
				end)
				row.Activated:Connect(function()
					if hasSub then
						-- touch path: no MouseEnter — tap the parent row to expand
						if activeMenu and activeMenu.panels[depth + 2] == nil then
							openSubmenu(row, item.Submenu, depth + 1)
						end
					else
						closeContextMenu()
						safeCall(item.Callback)
					end
				end)
			end
		end
	end
	return frame, width
end

-- Opens the child panel beside `row`, flipping left when the right side
-- doesn't fit. depth is the CHILD's depth (root children = 1).
openSubmenu = function(row, subItems, depth)
	if activeMenu == nil then
		return
	end
	local frame, width = buildPanel(row:FindFirstAncestorOfClass("ScreenGui"), subItems, depth)
	activeMenu.panels[depth + 1] = frame
	local rowPos, rowSize = row.AbsolutePosition, row.AbsoluteSize
	local viewport = Device.Viewport()
	local x = rowPos.X + rowSize.X + 6
	if x + width > viewport.X - 8 then
		x = math.max(rowPos.X - width - 6, 8)
	end
	frame.Position = UDim2.fromOffset(x, 8)
	task.defer(function() -- height settles one frame after AutomaticSize
		if frame.Parent == nil then
			return
		end
		local y = math.clamp(rowPos.Y - 5, 8, math.max(viewport.Y - frame.AbsoluteSize.Y - 8, 8))
		frame.Position = UDim2.fromOffset(x, y)
	end)
	Utility.Tween(frame, Utility.TweenFast, { GroupTransparency = 0 })
	Utility.Tween(frame:FindFirstChildOfClass("UIScale"), Utility.TweenFast, { Scale = 1 })
end

-- Library:ContextMenu({ Items = { { Name, Callback, Disabled?, Danger?,
--                       Submenu = { ...items }? } | "separator", ... },
--                       Position = Vector2? (default: mouse location) })
-- Auto-width from the longest label, viewport-clamped, closes on Escape or an
-- outside press. Returns a handle with :Close() (idempotent).
function Library:ContextMenu(config)
	assert(type(config) == "table" and type(config.Items) == "table",
		"[Atlas] ContextMenu requires an Items list")
	local gui = self:_getGui()
	closeContextMenu()

	local frame, width = buildPanel(gui, config.Items, 0)

	-- Place after AutomaticSize settles; flip above the cursor near screen bottom.
	local origin = config.Position or UserInputService:GetMouseLocation()
	task.defer(function()
		if frame.Parent == nil then
			return
		end
		local viewport = Device.Viewport()
		local x = math.clamp(origin.X, 8, math.max(viewport.X - width - 8, 8))
		local y = origin.Y
		if y + frame.AbsoluteSize.Y + 8 > viewport.Y then
			y = math.max(viewport.Y - frame.AbsoluteSize.Y - 8, 8)
		end
		frame.Position = UDim2.fromOffset(x, math.max(y, 8))
	end)

	-- Outside press or Escape closes; a press INSIDE any panel is left to the rows.
	local conn
	conn = UserInputService.InputBegan:Connect(function(input)
		if activeMenu == nil or activeMenu.conn ~= conn then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			closeContextMenu()
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.MouseButton2
			and t ~= Enum.UserInputType.Touch then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		for _, panel in ipairs(activeMenu.panels) do
			local pos, size = panel.AbsolutePosition, panel.AbsoluteSize
			if p.X >= pos.X and p.X <= pos.X + size.X and p.Y >= pos.Y and p.Y <= pos.Y + size.Y then
				return -- inside: the rows handle it
			end
		end
		closeContextMenu()
	end)

	activeMenu = { panels = { frame }, conn = conn }
	Utility.Tween(frame, Utility.TweenFast, { GroupTransparency = 0 })
	Utility.Tween(frame:FindFirstChildOfClass("UIScale"), Utility.TweenFast, { Scale = 1 })
	return { Close = closeContextMenu }
end

function Library:CloseContextMenu()
	closeContextMenu()
end

-- Attaches a context menu to ANY GuiObject: right-click on mouse, a 0.55 s
-- STATIONARY long-press on touch (moving the finger counts as a drag and
-- cancels). `items` may be a table or a function returning one (re-evaluated
-- on every open, so dynamic menus are free).
function Library:AddContextMenu(target, items)
	assert(target and target:IsA("GuiObject"), "[Atlas] AddContextMenu expects a GuiObject")
	local function resolve()
		local list = type(items) == "function" and items() or items
		assert(type(list) == "table", "[Atlas] AddContextMenu: items must be a table or a function")
		return list
	end
	local holdGen = 0
	local touchStart = nil
	target.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			Library:ContextMenu({
				Items = resolve(),
				Position = Vector2.new(input.Position.X, input.Position.Y),
			})
		elseif input.UserInputType == Enum.UserInputType.Touch then
			holdGen = holdGen + 1
			local gen = holdGen
			touchStart = Vector2.new(input.Position.X, input.Position.Y)
			task.delay(0.55, function()
				if holdGen == gen and touchStart then
					Library:ContextMenu({ Items = resolve(), Position = touchStart })
					-- The finger is still down: releasing it fires Activated on
					-- the target. Consumers (like the FAB) must swallow that one
					-- click via this flag — otherwise a long-press ALSO toggles.
					target:SetAttribute("AtlasSuppressClick", true)
				end
			end)
		end
	end)
	target.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch
			and input.UserInputState == Enum.UserInputState.Change
			and touchStart
			and (Vector2.new(input.Position.X, input.Position.Y) - touchStart).Magnitude > 10 then
			holdGen = holdGen + 1 -- finger moved: this is a drag, not a long-press
			touchStart = nil
		end
	end)
	target.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			holdGen = holdGen + 1
			touchStart = nil
			-- Clear after Activated has had its chance to read the flag.
			task.delay(0.15, function()
				if target.Parent then
					target:SetAttribute("AtlasSuppressClick", false)
				end
			end)
		end
	end)
end

-- Global hotkey: Ctrl+K opens the palette.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.K
		and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
		openPalette()
	end
end)

--------------------------------------------------------------------
-- Service: Watermark
--------------------------------------------------------------------

-- Small draggable top-left pill: title + optional FPS/ping, theme-bound.
--   Atlas:SetWatermark({ Text = "Atlas", ShowFPS = true, ShowPing = false })
--   Atlas:SetWatermarkVisible(bool)
local watermarkState = { frames = 0, elapsed = 0, fps = 0, ping = nil }

local function watermarkText(cfg)
	local parts = { cfg.Text or "Atlas" }
	if cfg.ShowFPS ~= false then
		table.insert(parts, ("%d FPS"):format(watermarkState.fps))
	end
	if cfg.ShowPing == true and watermarkState.ping ~= nil then
		table.insert(parts, ("%d ms"):format(watermarkState.ping))
	end
	return table.concat(parts, "  •  ")
end

function Library:SetWatermark(config)
	config = config or {}
	local gui = self:_getGui()
	if self._watermarkCfg == nil then
		self._watermarkCfg = { Text = "Atlas", ShowFPS = true, ShowPing = false, Visible = true }
	end
	for key, value in pairs(config) do
		self._watermarkCfg[key] = value
	end
	local cfg = self._watermarkCfg

	if self._watermark == nil then
		local pill = Create("TextLabel", {
			Name = "AtlasWatermark",
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.new(0, 16, 0, 16),
			Size = UDim2.new(0, 0, 0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = token("Surface"),
			BorderSizePixel = 0,
			Font = "@FontMedium", TextSize = 12,
			TextColor3 = token("Text"),
			Text = "",
			ZIndex = 1300,
			Parent = gui,
		}, {
			Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			Create("UIStroke", {
				Thickness = 1, Color = token("Stroke"),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
		T(pill, "BackgroundColor3", "Surface")
		T(pill, "TextColor3", "Text")
		T(pill:FindFirstChildOfClass("UIStroke"), "Color", "Stroke")
		Utility.MakeDraggable(pill, pill, function()
			return (self._uiScale and self._uiScale.Scale) or 1
		end)
		self._watermark = pill

		local conn
		conn = RunService.Heartbeat:Connect(function(dt)
			if not pill.Parent then
				conn:Disconnect()
				return
			end
			watermarkState.frames = watermarkState.frames + 1
			watermarkState.elapsed = watermarkState.elapsed + dt
			if watermarkState.elapsed >= 0.5 then -- refresh stats at ~2 Hz
				watermarkState.fps = math.floor(watermarkState.frames / watermarkState.elapsed + 0.5)
				watermarkState.frames, watermarkState.elapsed = 0, 0
				if cfg.ShowPing == true then
					local ok, item = pcall(function()
						return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
					end)
					watermarkState.ping = ok and math.floor(item + 0.5) or nil
				else
					watermarkState.ping = nil
				end
				pill.Text = watermarkText(cfg)
			end
		end)
	end

	self._watermark.Text = watermarkText(cfg)
	self._watermark.Visible = cfg.Visible ~= false

	-- SetWatermark{ RememberLayout = true }: the dragged position rides along
	-- in every profile save/load, clamped into the live viewport on restore.
	if cfg.RememberLayout and self._flags["Watermark/Layout"] == nil then
		local pill = self._watermark
		self:_registerFlag("Watermark/Layout", {
			Get = function()
				if pill.Parent == nil then
					return nil
				end
				local viewport = Device.Viewport()
				local pos = pill.Position -- anchored top-left
				return { pos.X.Scale * viewport.X + pos.X.Offset, pos.Y.Scale * viewport.Y + pos.Y.Offset }
			end,
			Set = function(_, value)
				if type(value) ~= "table" or #value < 2 or pill.Parent == nil then
					return
				end
				local viewport = Device.Viewport()
				local x = math.clamp(tonumber(value[1]) or 16, 0, math.max(viewport.X - 40, 0))
				local y = math.clamp(tonumber(value[2]) or 16, 0, math.max(viewport.Y - 40, 0))
				pill.Position = UDim2.fromOffset(x, y)
			end,
		})
	end
	return self._watermark
end

function Library:SetWatermarkVisible(visible)
	local pill = self._watermark
	if pill then
		pill.Visible = visible == true
		self._watermarkCfg.Visible = visible == true
	elseif visible then
		self:SetWatermark({ Visible = true })
	end
end

--------------------------------------------------------------------
-- Responsive refit: rotate a phone/iPad (or resize the window) and
-- every open Atlas window re-clamps to the new safe viewport.
--------------------------------------------------------------------

Device.OnViewportChanged(function(viewport)
	for window in pairs(Library._windows) do
		pcall(function()
			window:_refit(viewport)
		end)
	end
	if Library._notifHolder then
		Library._notifHolder.Size = UDim2.new(0, Device.NotifyWidth(), 1, -32)
	end
	if Library._watermark then -- draggable, so it can end up off-screen after rotation
		local pos = Library._watermark.Position
		local x = math.clamp(pos.X.Scale * viewport.X + pos.X.Offset, 0, math.max(viewport.X - 40, 0))
		local y = math.clamp(pos.Y.Scale * viewport.Y + pos.Y.Offset, 0, math.max(viewport.Y - 26, 0))
		Library._watermark.Position = UDim2.fromOffset(x, y)
	end
end)

--------------------------------------------------------------------
-- Service: Loading Screen
--------------------------------------------------------------------

-- Full-screen branded loader, mouse/touch friendly, zero assets.
--   Atlas:ShowLoadingScreen({
--       Title = "Atlas", Subtitle = "...", Duration = 2.5,        -- auto mode
--       Steps = { "Loading modules", "Building UI", "Ready" },    -- optional staging text
--       OnComplete = function() end,                              -- after the fade-out
--   }) -> loader
-- Without Duration it runs in manual mode: drive it with
--   loader:SetProgress(0..1 [, statusText])  then  loader:Done()
function Library:ShowLoadingScreen(config)
	config = config or {}
	local gui = self:_getGui()
	local deviceClass = Device.Class()
	local mobile = Device.IsMobile()
	local stackWidth = ({ Phone = 240, Tablet = 300, Desktop = 280, Console = 300 })[deviceClass] or 280

	local overlay = Create("CanvasGroup", { -- CanvasGroup: one GroupTransparency fade for all
		Name = "AtlasLoadingScreen",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = token("Background"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		ZIndex = 3000,
		Parent = gui,
	})
	T(overlay, "BackgroundColor3", "Background")

	local stack = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, stackWidth, 0, 130),
		BackgroundTransparency = 1,
		Parent = overlay,
	}, {
		Create("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	local title = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Font = "@FontBold", TextSize = mobile and 30 or 26,
		TextColor3 = token("Text"),
		Text = config.Title or "Atlas",
		LayoutOrder = 1,
		Parent = stack,
	})
	T(title, "TextColor3", "Text")

	local subtitle = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = "@Font", TextSize = 12,
		TextColor3 = token("TextDim"),
		Text = config.Subtitle or "Loading interface...",
		LayoutOrder = 2,
		Parent = stack,
	})
	T(subtitle, "TextColor3", "TextDim")

	local statusRow = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = stack,
	})
	local statusLabel = Create("TextLabel", {
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Font = "@FontMedium", TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = token("TextDim"),
		Text = "",
		Parent = statusRow,
	})
	T(statusLabel, "TextColor3", "TextDim")
	local pctLabel = Create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 44, 1, 0),
		BackgroundTransparency = 1,
		Font = "@FontBold", TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = token("Accent"),
		Text = "0%",
		Parent = statusRow,
	})
	T(pctLabel, "TextColor3", "Accent")

	local track = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 4,
		Parent = stack,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "SurfaceAlt")
	local fill = Create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(fill, "BackgroundColor3", "Accent")

	local loader = {}
	local steps = type(config.Steps) == "table" and config.Steps or nil
	local finished = false

	local function fillTo(p)
		fill.Size = UDim2.fromScale(p, 1) -- direct set: called every Heartbeat in auto mode
		pctLabel.Text = ("%d%%"):format(math.floor(p * 100 + 0.5))
		if steps and #steps > 0 then
			local idx = math.clamp(math.floor(p * #steps) + 1, 1, #steps)
			statusLabel.Text = steps[idx]
		end
	end

	function loader:SetProgress(p, text)
		if finished then
			return
		end
		if type(text) == "string" then
			steps = nil
			statusLabel.Text = text
		end
		fillTo(Utility.Clamp(tonumber(p) or 0, 0, 1))
	end

	function loader:Done()
		if finished then
			return
		end
		finished = true
		fillTo(1)
		Utility.Tween(overlay, Utility.TweenMed, { GroupTransparency = 1 }).Completed:Connect(function()
			overlay:Destroy()
		end)
		safeCall(config.OnComplete)
	end

	function loader:Destroy()
		finished = true
		overlay:Destroy()
	end

	Utility.Tween(overlay, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { GroupTransparency = 0 })
	fillTo(0)

	local duration = tonumber(config.Duration)
	if duration and duration > 0 then
		local startTime = os.clock()
		local conn
		conn = RunService.Heartbeat:Connect(function()
			if finished or overlay.Parent == nil then
				conn:Disconnect()
				return
			end
			local p = math.min((os.clock() - startTime) / duration, 1)
			fillTo(p)
			if p >= 1 then
				conn:Disconnect()
				loader:Done()
			end
		end)
	end

	return loader
end

--------------------------------------------------------------------
-- Service: Configuration Profiles
--------------------------------------------------------------------

function Library:ExportConfig()
	local data = {}
	for flag, handle in pairs(self._flags) do
		if type(handle.Get) == "function" then
			local ok, value = pcall(handle.Get)
			if ok then
				data[flag] = encodeValue(value)
			end
		end
	end
	return data
end

function Library:ApplyConfig(data)
	for flag, encoded in pairs(data or {}) do
		local handle = self._flags[flag]
		if handle and type(handle.Set) == "function" then
			local value = decodeValue(encoded)
			-- All value setters honor the optional silent flag (no callbacks during restore).
			pcall(handle.Set, handle, value, true)
		end
	end
end

function Library:SaveConfig(name)
	assert(type(name) == "string" and name ~= "", "[Atlas] SaveConfig requires a name")
	self._configs[name] = self:ExportConfig()
	return self._configs[name]
end

-- Periodically snapshots all flagged controls into a named profile.
-- SetAutoSave("slot", 15) starts it; SetAutoSave(nil) stops it. A later
-- call replaces any earlier loop (generation-guarded).
function Library:SetAutoSave(name, interval)
	self._autoSaveGen = (self._autoSaveGen or 0) + 1
	if name == nil or name == false then
		return
	end
	assert(type(name) == "string" and name ~= "", "[Atlas] SetAutoSave requires a profile name")
	local generation = self._autoSaveGen
	local every = math.max(tonumber(interval) or 15, 2)
	task.spawn(function()
		while self._autoSaveGen == generation do
			task.wait(every)
			if self._autoSaveGen ~= generation then
				break
			end
			pcall(Library.SaveConfig, self, name)
		end
	end)
end

function Library:LoadConfig(name)
	local data = self._configs[name]
	if data == nil then
		return false
	end
	self:ApplyConfig(data)
	return true
end

function Library:DeleteConfig(name)
	self._configs[name] = nil
end

function Library:GetConfigs()
	local names = {}
	for key in pairs(self._configs) do
		table.insert(names, key)
	end
	table.sort(names)
	return names
end

function Library:SerializeConfigs()
	local HttpService = game:GetService("HttpService")
	return HttpService:JSONEncode(self._configs)
end

function Library:DeserializeConfigs(json)
	local HttpService = game:GetService("HttpService")
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if ok and type(data) == "table" then
		self._configs = data
		return true
	end
	warn("[Atlas] DeserializeConfigs: invalid JSON")
	return false
end

return Library
