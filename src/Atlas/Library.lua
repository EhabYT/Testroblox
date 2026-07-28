--!nonstrict
-- Library.lua — Atlas core: GUI manager and component framework.
-- Part of atlas-ui (MIT License).
--
-- This file is self-sufficient; its only dependencies are the sibling
-- Theme and Utility ModuleScripts inside the same Atlas folder.

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)
local Utility = require(script.Parent.Utility)

--------------------------------------------------------------------
-- Singleton manager
--------------------------------------------------------------------

local Library = {
	_themeName = "Dark",
	_themeBindings = {}, -- functions re-applied by SetTheme
	_flags = {},         -- flag name -> component handle
	_gui = nil,
	_notifHolder = nil,
	_uiScale = nil,
	_windows = {},
	_commands = {},
	_configs = {},
}

local function token(name)
	return Theme.Get(Library._themeName)[name]
end

local function bind(fn)
	table.insert(Library._themeBindings, fn)
	pcall(fn)
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

function Library:SetTheme(name)
	if Theme.Tokens[name] == nil then
		warn(("[Atlas] Unknown theme '%s'"):format(tostring(name)))
		return
	end
	self._themeName = name
	for _, fn in ipairs(self._themeBindings) do
		pcall(fn)
	end
end

function Library:GetThemeNames()
	return Theme.Names()
end

function Library:SetScale(scale)
	self:_getGui()
	self._uiScale.Scale = Utility.Clamp(scale, 0.5, 2)
end

function Library:_registerFlag(flag, handle)
	if type(flag) == "string" and flag ~= "" then
		self._flags[flag] = handle
	end
end

function Library:GetFlag(flag)
	return self._flags[flag]
end

function Library:_getGui()
	local player = Players.LocalPlayer
	if not player then
		error("[Atlas] Library must be required from a LocalScript (client only).", 3)
	end
	if self._gui == nil then
		local gui = Utility.Create("ScreenGui", {
			Name = "AtlasInterface",
			ResetOnSpawn = false,
			DisplayOrder = 50,
			IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = player:WaitForChild("PlayerGui"),
		})
		self._uiScale = Utility.Create("UIScale", { Scale = 1, Parent = gui })
		self._notifHolder = Utility.Create("Frame", {
			Name = "Notifications",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.new(0, 300, 1, -32),
			BackgroundTransparency = 1,
			Parent = gui,
		}, {
			Utility.Create("UIListLayout", {
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

	local card = Utility.Create("CanvasGroup", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Parent = self._notifHolder,
	}, {
		Utility.Create("UICorner", { CornerRadius = token("Corner") }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 30),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card, "BackgroundColor3", "Surface")
	T(Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local bar = Utility.Create("Frame", {
		Name = "AccentBar",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = token(accentToken),
		BorderSizePixel = 0,
		Parent = card,
	})
	bind(function()
		bar.BackgroundColor3 = token(accentToken)
	end)

	local title = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = token("FontBold"), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Title or "Notification",
		TextColor3 = token("Text"),
		Parent = card,
	})
	T(title, "TextColor3", "Text")

	local body = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = token("Font"), TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Text = config.Text or "",
		TextColor3 = token("TextDim"),
		LayoutOrder = 1,
		Parent = card,
	})
	T(body, "TextColor3", "TextDim")

	local dismissed = false
	local function dismiss()
		if dismissed then
			return
		end
		dismissed = true
		Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			card:Destroy()
		end)
	end

	local close = Utility.Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 18, 0, 18),
		BackgroundTransparency = 1,
		Font = token("FontBold"), TextSize = 13,
		Text = "×", TextColor3 = token("TextDim"),
		Parent = card,
	})
	T(close, "TextColor3", "TextDim")
	close.Activated:Connect(dismiss)

	Utility.Tween(card, Utility.TweenMed, { GroupTransparency = 0 })
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

function Library:CreateWindow(config)
	config = config or {}
	local gui = self:_getGui()
	local size = config.Size or UDim2.fromOffset(620, 460)

	-- Root is a CanvasGroup so the whole window can fade via GroupTransparency
	-- and rounded corners clip every child (title bar, sidebar) for free.
	local root = Utility.Create("CanvasGroup", {
		Name = config.Name or "AtlasWindow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = config.Position or UDim2.fromScale(0.5, 0.5),
		Size = size,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		Visible = config.Visible ~= false,
		Parent = gui,
	}, { Utility.Create("UICorner", { CornerRadius = token("Corner") }) })
	T(root, "BackgroundColor3", "Surface")
	T(Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = root,
	}), "Color", "Stroke")

	-- Title bar ------------------------------------------------------------
	local titleBar = Utility.Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0, ZIndex = 2,
		Parent = root,
	})
	T(titleBar, "BackgroundColor3", "SurfaceAlt")

	local titleLabel = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -110, 1, 0),
		Font = token("FontBold"), TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = token("Text"),
		Text = config.Title or "Atlas",
		Parent = titleBar,
	})
	T(titleLabel, "TextColor3", "Text")

	local dividerTop = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 0, 40),
		BorderSizePixel = 0, ZIndex = 2,
		BackgroundColor3 = token("Stroke"),
		Parent = root,
	})
	T(dividerTop, "BackgroundColor3", "Stroke")

	-- Window controls ------------------------------------------------------
	local controls = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 60, 0, 24),
		BackgroundTransparency = 1,
		Parent = titleBar,
	}, {
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function controlButton(symbol, order)
		local b = Utility.Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = token("Hover"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = token("FontBold"), TextSize = 14,
			TextColor3 = token("TextDim"),
			Text = symbol,
			Parent = controls,
		}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
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

	local minimizeButton = controlButton("–", 1)
	local closeButton = controlButton("×", 2)

	-- Body: sidebar + pages -------------------------------------------------
	local body = Utility.Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 41),
		Size = UDim2.new(1, 0, 1, -41),
		Parent = root,
	})

	local sidebar = Utility.Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 150, 1, 0),
		BackgroundColor3 = token("Background"),
		BorderSizePixel = 0,
		Parent = body,
	})
	T(sidebar, "BackgroundColor3", "Background")

	local tabList = Utility.Create("Frame", {
		Name = "TabList",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 8),
		Size = UDim2.new(1, -16, 1, -16),
		Parent = sidebar,
	}, {
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local dividerSide = Utility.Create("Frame", {
		Position = UDim2.new(0, 150, 0, 8),
		Size = UDim2.new(0, 1, 1, -16),
		BorderSizePixel = 0,
		BackgroundColor3 = token("Stroke"),
		Parent = body,
	})
	T(dividerSide, "BackgroundColor3", "Stroke")

	local pages = Utility.Create("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 158, 0, 6),
		Size = UDim2.new(1, -166, 1, -12),
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
	}, Window)

	Utility.MakeDraggable(root, titleBar, function()
		return (self._uiScale and self._uiScale.Scale) or 1
	end)

	closeButton.Activated:Connect(function()
		window:SetVisible(false)
	end)
	minimizeButton.Activated:Connect(function()
		window:SetMinimized(not window._minimized)
	end)

	local toggleKey = config.ToggleKey or Enum.KeyCode.RightShift
	window._bag:Add(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == toggleKey then
			window:SetVisible(not root.Visible)
		end
	end))

	-- Resize grip (opt-in via CreateWindow{ Resizable = true })
	if config.Resizable == true then
		local grip = Utility.Create("TextButton", {
			Name = "ResizeGrip",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -2, 1, -2),
			Size = UDim2.new(0, 14, 0, 14),
			BackgroundTransparency = 1,
			Font = token("Font"), TextSize = 10,
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

	table.insert(self._windows, window)
	return window
end

function Window:SetVisible(visible)
	local root = self._root
	if visible then
		root.Visible = true
		Utility.Tween(root, Utility.TweenMed, { GroupTransparency = 0 })
	else
		Utility.Tween(root, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			-- Guard: the user may have re-shown the window during the fade.
			if root.GroupTransparency >= 0.99 then
				root.Visible = false
			end
		end)
	end
end

function Window:SetMinimized(minimized)
	self._minimized = minimized
	if minimized then
		self._fullSize = self._root.Size
		self._body.Visible = false
		Utility.Tween(self._root, Utility.TweenMed, {
			Size = UDim2.new(0, self._root.AbsoluteSize.X, 0, 40),
		})
	else
		self._body.Visible = true
		Utility.Tween(self._root, Utility.TweenMed, { Size = self._fullSize })
	end
end

function Window:Destroy()
	self._bag:DisconnectAll()
	self._root:Destroy()
end

--------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------

function Window:CreateTab(config)
	config = config or {}
	local thisWindow = self

	local button = Utility.Create("TextButton", {
		Name = "Tab_" .. (config.Title or "Tab"),
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = token("Hover"),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = token("FontMedium"), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = config.Title or "Tab",
		Parent = self._tabList,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }),
	})

	local page = Utility.Create("ScrollingFrame", {
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
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		Utility.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }),
	})
	T(page, "ScrollBarImageColor3", "Stroke")

	local tab = setmetatable({ _window = thisWindow, _button = button, _page = page }, Tab)

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
		t._page.Visible = active
		Utility.Tween(t._button, Utility.TweenFast, {
			BackgroundTransparency = active and 0 or 1,
			TextColor3 = active and token("Text") or token("TextDim"),
		})
	end
end

--------------------------------------------------------------------
-- Section and component rows
--------------------------------------------------------------------

local function sectionRow(section, height)
	local row = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		Parent = section._body,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}),
	})
	T(row, "BackgroundColor3", "SurfaceAlt")
	T(Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = row,
	}), "Color", "Stroke")
	return row
end

local function rowLabel(row, text, widthReserve)
	local label = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(widthReserve or 0), 1, 0),
		Font = token("FontMedium"), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = token("Text"),
		Text = text,
		Parent = row,
	})
	T(label, "TextColor3", "Text")
	return label
end

function Tab:CreateSection(config)
	config = config or {}
	local collapsible = config.Collapsible == true

	local holder = Utility.Create("Frame", {
		Name = "Section_" .. (config.Title or ""),
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._page,
	}, {
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local headerClass = collapsible and "TextButton" or "TextLabel"
	local header = Utility.Create(headerClass, {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 16),
		Font = token("FontBold"), TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = string.upper(config.Title or "Section"),
		AutoButtonColor = false,
		Parent = holder,
	})
	T(header, "TextColor3", "TextDim")

	local body = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local section = setmetatable({ _body = body }, Section)

	if collapsible then
		local collapsed = config.DefaultCollapsed == true
		local function paint()
			header.Text = (collapsed and "▸ " or "▾ ") .. string.upper(config.Title or "Section")
			body.Visible = not collapsed
		end
		header.Activated:Connect(function()
			collapsed = not collapsed
			paint()
		end)
		paint()
	end

	return section
end

function Section:CreateDivider()
	local line = Utility.Create("Frame", {
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
	local button = Utility.Create("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = token("SurfaceAlt"),
		AutoButtonColor = false, BorderSizePixel = 0,
		Font = token("FontMedium"), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Button",
		Parent = self._body,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}),
		Utility.Create("TextLabel", {
			Name = "Chevron",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.new(0, 16, 0, 16),
			Font = token("FontBold"), TextSize = 14,
			TextColor3 = token("TextDim"), Text = "›",
		}),
	})
	T(button, "BackgroundColor3", "SurfaceAlt")
	T(button, "TextColor3", "Text")
	T(Utility.Create("UIStroke", {
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
	button.Activated:Connect(function()
		safeCall(config.Callback)
	end)

	local handle = { Root = button }
	function handle:SetText(text)
		button.Text = text
	end
	return handle
end

--------------------------------------------------------------------
-- Component: Toggle
--------------------------------------------------------------------

function Section:CreateToggle(config)
	config = config or {}
	local state = config.Default == true
	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Toggle", 60)

	local pill = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 36, 0, 20),
		BorderSizePixel = 0,
		Parent = row,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local knob = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = pill,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	local hit = Utility.Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, Text = "",
		ZIndex = 3, Parent = row,
	})

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
		handle:Set(not state)
	end)

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

	local row = sectionRow(self, 50)
	local label = rowLabel(row, config.Title or "Slider", 90)
	label.Size = UDim2.new(1, -90, 0, 20)

	local valueLabel = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 86, 0, 20),
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("TextDim"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = format(value),
		Parent = row,
	})
	T(valueLabel, "TextColor3", "TextDim")

	local track = Utility.Create("Frame", {
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = row,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "Stroke")

	local function percent(v)
		if maxV <= minV then
			return 0
		end
		return (v - minV) / (maxV - minV)
	end

	local fill = Utility.Create("Frame", {
		Size = UDim2.fromScale(percent(value), 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	bind(function()
		fill.BackgroundColor3 = token("Accent")
	end)

	local knob = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(percent(value), 0, 0.5, 0),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0, ZIndex = 2,
		Parent = track,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Utility.Create("UIStroke", {
			Thickness = 1, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	local hit = Utility.Create("TextButton", {
		BackgroundTransparency = 1, Text = "",
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(1, 0, 0, 20),
		ZIndex = 3, Parent = row,
	})

	local dragging = false

	local function setValue(v)
		v = Utility.Clamp(Utility.Round(v, step), minV, maxV)
		if v ~= value then
			value = v
			local p = percent(v)
			fill.Size = UDim2.fromScale(p, 1)
			knob.Position = UDim2.new(p, 0, 0.5, 0)
			valueLabel.Text = format(v)
			safeCall(config.Callback, v)
		end
	end

	local function updateFromInput(input)
		local width = math.max(track.AbsoluteSize.X, 1)
		local p = Utility.Clamp((input.Position.X - track.AbsolutePosition.X) / width, 0, 1)
		setValue(minV + p * (maxV - minV))
	end

	hit.InputBegan:Connect(function(input)
		if Utility.IsPrimary(input) then
			dragging = true
			updateFromInput(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if Utility.IsPrimary(input) then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromInput(input)
		end
	end)

	local handle = { Root = row }
	function handle:Set(v)
		setValue(v)
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

	local holder = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Utility.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Dropdown", 170)

	local valueButton = Utility.Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("Text"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	T(valueButton, "BackgroundColor3", "Surface")
	T(valueButton, "TextColor3", "Text")

	local function renderValue()
		valueButton.Text = tostring(selected) .. "  ▾"
	end
	renderValue()

	local list = Utility.Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(list, "BackgroundColor3", "SurfaceAlt")

	for index, option in ipairs(options) do
		local optionButton = Utility.Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = token("Hover"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = token("FontMedium"), TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("TextDim"),
			Text = tostring(option),
			LayoutOrder = index,
			Parent = list,
		}, {
			Utility.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }),
		})
		T(optionButton, "BackgroundColor3", "Hover")
		T(optionButton, "TextColor3", "TextDim")
		optionButton.MouseEnter:Connect(function()
			Utility.Tween(optionButton, Utility.TweenFast, { BackgroundTransparency = 0, TextColor3 = token("Text") })
		end)
		optionButton.MouseLeave:Connect(function()
			Utility.Tween(optionButton, Utility.TweenFast, { BackgroundTransparency = 1, TextColor3 = token("TextDim") })
		end)
		optionButton.Activated:Connect(function()
			selected = option
			renderValue()
			open = false
			list.Visible = false
			safeCall(config.Callback, selected)
		end)
	end

	valueButton.Activated:Connect(function()
		open = not open
		list.Visible = open
	end)

	local handle = { Root = row }
	function handle:Set(v)
		if table.find(options, v) then
			selected = v
			renderValue()
			safeCall(config.Callback, v)
		end
	end
	function handle:Get()
		return selected
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

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Keybind", 110)

	local box = Utility.Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 90, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("TextDim"),
		Text = currentBind and currentBind.Name or "None",
		Parent = row,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
	T(box, "BackgroundColor3", "Surface")
	T(box, "TextColor3", "TextDim")

	box.Activated:Connect(function()
		if listening then
			return
		end
		listening = true
		box.Text = "…"
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
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

	local stroke = Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})

	local box = Utility.Create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = config.Placeholder or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Default or "",
		Parent = row,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
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
	local label = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = token("Font"), TextSize = config.TextSize or 12,
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
-- Component: Segmented Control
--------------------------------------------------------------------

function Section:CreateSegmented(config)
	config = config or {}
	local options = config.Options or {}
	assert(#options >= 2, "[Atlas] CreateSegmented requires at least two options")
	local selected = config.Default or options[1]

	local row = sectionRow(self, 34)
	rowLabel(row, config.Title or "Options", (config.Width or 200) + 12)

	local group = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, config.Width or 200, 0, 24),
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		Parent = row,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2),
			PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2),
		}),
		Utility.Create("UIListLayout", {
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
		local b = Utility.Create("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = token("Accent"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = token("FontMedium"), TextSize = 12,
			TextColor3 = token("TextDim"),
			Text = tostring(option),
			Parent = group,
		}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 4) }) })
		buttons[option] = b
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
	function handle:Set(v)
		if buttons[v] then
			selected = v
			refresh()
			safeCall(config.Callback, v)
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

	local holder = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Utility.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Multi-Select", 170)

	local valueButton = Utility.Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 24),
		BackgroundColor3 = token("Surface"),
		AutoButtonColor = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("Text"),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	T(valueButton, "BackgroundColor3", "Surface")
	T(valueButton, "TextColor3", "Text")

	local function renderValue()
		local listItems = getList()
		valueButton.Text = (#listItems > 0 and table.concat(listItems, ", ") or "None") .. "  ▾"
	end
	renderValue()

	local list = Utility.Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
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
		local b = Utility.Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = token("Hover"),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Font = token("FontMedium"), TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = token("TextDim"),
			LayoutOrder = index,
			Parent = list,
		}, {
			Utility.Create("UICorner", { CornerRadius = UDim.new(0, 4) }),
			Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 10) }),
		})
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
	end
	repaintAll()

	valueButton.Activated:Connect(function()
		open = not open
		list.Visible = open
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

	local group = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 118, 0, 24),
		BackgroundTransparency = 1,
		Parent = row,
	}, {
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local function smallButton(symbol, order)
		local b = Utility.Create("TextButton", {
			LayoutOrder = order,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = token("Surface"),
			AutoButtonColor = false,
			Font = token("FontBold"), TextSize = 14,
			TextColor3 = token("Text"), Text = symbol,
			Parent = group,
		}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		T(b, "BackgroundColor3", "Surface")
		T(b, "TextColor3", "Text")
		return b
	end

	local minus = smallButton("−", 1)
	local box = Utility.Create("TextBox", {
		LayoutOrder = 2,
		Size = UDim2.new(0, 58, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("Text"),
		Text = format(value),
		Parent = group,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
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
	function handle:Set(v)
		commit(v)
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

	local percentLabel = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 56, 0, 18),
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("TextDim"),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = showPercent and string.format("%d%%", progress * 100) or "",
		Visible = showPercent,
		Parent = row,
	})
	T(percentLabel, "TextColor3", "TextDim")

	local track = Utility.Create("Frame", {
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = token("Stroke"),
		BorderSizePixel = 0,
		Parent = row,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	T(track, "BackgroundColor3", "Stroke")

	local fill = Utility.Create("Frame", {
		Size = UDim2.fromScale(progress, 1),
		BackgroundColor3 = token("Accent"),
		BorderSizePixel = 0,
		Parent = track,
	}, { Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }) })
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
	function handle:SetLabel(t)
		label.Text = tostring(t)
	end
	function handle:Get()
		return progress
	end
	Library:_registerFlag(config.Flag, handle)
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
	local h, s, v = (config.Default or Color3.fromRGB(237, 66, 69)):ToHSV()
	local color = Color3.fromHSV(h, s, v)

	local holder = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = self._body,
	}, { Utility.Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local row = sectionRow({ _body = holder }, 34)
	rowLabel(row, config.Title or "Color", 60)

	local swatch = Utility.Create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 44, 0, 22),
		BackgroundColor3 = color,
		AutoButtonColor = false, Text = "",
		Parent = row,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIStroke", {
			Thickness = 1, Color = token("Stroke"),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})

	local panel = Utility.Create("Frame", {
		Visible = false,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("SurfaceAlt"),
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(panel, "BackgroundColor3", "SurfaceAlt")

	-- Saturation/Value square ------------------------------------------------
	local svFrame = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 140),
		BackgroundColor3 = Color3.fromHSV(h, 1, 1),
		BorderSizePixel = 0,
		Parent = panel,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
		}, {
			Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Utility.Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		Utility.Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0), BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(0, 0, 0),
		}, {
			Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Utility.Create("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		}),
	})
	local svDot = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 12, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 5,
		Parent = svFrame,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Utility.Create("UIStroke", { Thickness = 2, Color = Color3.new(0.1, 0.1, 0.1) }),
	})
	local svHit = Utility.Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Text = "", ZIndex = 6, Parent = svFrame,
	})

	-- Hue track ----------------------------------------------------------------
	local hueTrack = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, LayoutOrder = 1,
		Parent = panel,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Utility.Create("UIGradient", { Color = rainbowSequence() }),
	})
	local hueKnob = Utility.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, 14, 0, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, ZIndex = 5,
		Parent = hueTrack,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Utility.Create("UIStroke", { Thickness = 2, Color = Color3.new(0.1, 0.1, 0.1) }),
	})
	local hueHit = Utility.Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		Text = "", ZIndex = 6, Parent = hueTrack,
	})

	-- Hex entry + preset swatches -----------------------------------------------
	local bottomRow = Utility.Create("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1, LayoutOrder = 2,
		Parent = panel,
	}, {
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local hexBox = Utility.Create("TextBox", {
		Size = UDim2.new(0, 78, 0, 24),
		BackgroundColor3 = token("Surface"),
		ClearTextOnFocus = false,
		Font = token("FontMedium"), TextSize = 12,
		TextColor3 = token("Text"),
		Parent = bottomRow,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
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
		local p = Utility.Create("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(0, 24, 0, 24),
			BackgroundColor3 = preset,
			AutoButtonColor = false, Text = "",
			Parent = bottomRow,
		}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		p.Activated:Connect(function()
			h, s, v = preset:ToHSV()
			applyAll(true)
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
	UserInputService.InputEnded:Connect(function(i)
		if Utility.IsPrimary(i) then
			activeDrag = nil
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
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
	end
	function handle:Get()
		return color
	end
	Library:_registerFlag(config.Flag, handle)
	applyAll(false)
	return handle
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
		tip = Utility.Create("CanvasGroup", {
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
			Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Utility.Create("UIPadding", {
				PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			}),
			Utility.Create("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Font = token("Font"), TextSize = 12,
				TextColor3 = token("Text"),
				Text = text,
			}),
		})
		T(tip, "BackgroundColor3", "Surface")
		local centerX = target.AbsolutePosition.X + target.AbsoluteSize.X / 2
		local topY = target.AbsolutePosition.Y - 8
		tip.Position = UDim2.fromOffset(
			math.clamp(centerX, 90, math.max(gui.AbsoluteSize.X - 90, 90)),
			topY
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
	target.Destroying:Connect(hide)
end

--------------------------------------------------------------------
-- Service: Modal Dialogs
--------------------------------------------------------------------

function Library:Prompt(config)
	config = config or {}
	local gui = self:_getGui()
	local buttons = config.Buttons or { "Cancel", "Confirm" }

	local overlay = Utility.Create("Frame", {
		Name = "ModalOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Active = true,
		ZIndex = 2000,
		Parent = gui,
	})

	local card = Utility.Create("CanvasGroup", {
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
		Utility.Create("UICorner", { CornerRadius = token("Corner") }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card, "BackgroundColor3", "Surface")
	T(Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local title = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = token("FontBold"), TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("Text"),
		Text = config.Title or "Confirm",
		Parent = card,
	})
	T(title, "TextColor3", "Text")

	local body = Utility.Create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = token("Font"), TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = token("TextDim"),
		Text = config.Text or "",
		LayoutOrder = 1,
		Parent = card,
	})
	T(body, "TextColor3", "TextDim")

	local buttonRow = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 2,
		Parent = card,
	}, {
		Utility.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local closed = false
	local function close(result)
		if closed then
			return
		end
		closed = true
		Utility.Tween(card, Utility.TweenFast, { GroupTransparency = 1 }).Completed:Connect(function()
			overlay:Destroy()
		end)
		safeCall(config.Callback, result)
	end

	for index, label in ipairs(buttons) do
		local isPrimary = (index == #buttons)
		local b = Utility.Create("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(0, 88, 0, 30),
			BackgroundColor3 = isPrimary and token("Accent") or token("SurfaceAlt"),
			AutoButtonColor = false,
			Font = token("FontMedium"), TextSize = 13,
			TextColor3 = isPrimary and token("OnAccent") or token("Text"),
			Text = tostring(label),
			Parent = buttonRow,
		}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
		bind(function()
			b.BackgroundColor3 = isPrimary and token("Accent") or token("SurfaceAlt")
			b.TextColor3 = isPrimary and token("OnAccent") or token("Text")
		end)
		b.Activated:Connect(function()
			close(label)
		end)
	end

	local escConnection
	escConnection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape then
			escConnection:Disconnect()
			close(nil) -- Escape reports no choice
		end
	end)

	Utility.Tween(card, Utility.TweenMed, { GroupTransparency = 0 })
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

function Library:RegisterCommand(config)
	assert(type(config) == "table" and type(config.Name) == "string",
		"[Atlas] RegisterCommand requires a Name")
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

	local overlay = Utility.Create("Frame", {
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

	local card = Utility.Create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.15, 0),
		Size = UDim2.new(0, 420, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = token("Surface"),
		BorderSizePixel = 0,
		ZIndex = 2501,
		Parent = overlay,
	}, {
		Utility.Create("UICorner", { CornerRadius = token("Corner") }),
		Utility.Create("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}),
		Utility.Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	T(card, "BackgroundColor3", "Surface")
	T(Utility.Create("UIStroke", {
		Thickness = 1, Color = token("Stroke"),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = card,
	}), "Color", "Stroke")

	local box = Utility.Create("TextBox", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = token("SurfaceAlt"),
		ClearTextOnFocus = false,
		Font = token("FontMedium"), TextSize = 14,
		TextColor3 = token("Text"),
		PlaceholderColor3 = token("TextDim"),
		PlaceholderText = "Type a command…",
		Text = "",
		Parent = card,
	}, {
		Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Utility.Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	T(box, "BackgroundColor3", "SurfaceAlt")
	T(box, "TextColor3", "Text")
	T(box, "PlaceholderColor3", "TextDim")

	local listFrame = Utility.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = card,
	}, { Utility.Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })

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
		paletteState.index = math.clamp(paletteState.index, 1, math.max(#paletteState.results, 1))
		for i, cmd in ipairs(paletteState.results) do
			if i > 8 then
				break
			end
			local rowBtn = Utility.Create("TextButton", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = token("Hover"),
				BackgroundTransparency = (i == paletteState.index) and 0 or 1,
				AutoButtonColor = false, Text = "",
				Parent = listFrame,
			}, { Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6) }) })
			T(rowBtn, "BackgroundColor3", "Hover")
			Utility.Create("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -130, 1, 0),
				Font = token("FontMedium"), TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = token("Text"),
				Text = cmd.Name,
				Parent = rowBtn,
			})
			Utility.Create("TextLabel", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0, 110, 1, 0),
				Font = token("Font"), TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = token("TextDim"),
				Text = cmd.Category or "",
				Parent = rowBtn,
			})
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
-- Service: Configuration Profiles
--------------------------------------------------------------------

local function encodeValue(v)
	local t = typeof(v)
	if t == "EnumItem" then
		return { __atlas = "enum", enumType = tostring(v.EnumType), name = v.Name }
	elseif t == "Color3" then
		return { __atlas = "color", r = v.R, g = v.G, b = v.B }
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
		end
		local out = {}
		for i, item in ipairs(v) do
			out[i] = decodeValue(item)
		end
		return out
	end
	return v
end

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
			-- Second argument is the toggle's `silent` flag; other setters
			-- harmlessly discard the extra parameter.
			pcall(handle.Set, handle, value, true)
		end
	end
end

function Library:SaveConfig(name)
	assert(type(name) == "string" and name ~= "", "[Atlas] SaveConfig requires a name")
	self._configs[name] = self:ExportConfig()
	return self._configs[name]
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
