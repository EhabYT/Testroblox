--!nonstrict
-- Utility.lua — Instance factory, tweens, dragging, connection bags.
-- Part of atlas-ui (MIT License).

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Utility = {}

Utility.TweenFast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Utility.TweenMed  = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local BASE_FAST, BASE_MED = 0.15, 0.25

-- Recreates the shared TweenInfos with a global speed multiplier.
-- Tweens read Utility.TweenFast/TweenMed at event time, so this applies live.
function Utility.SetAnimSpeed(mult)
	mult = Utility.Clamp(mult or 1, 0.2, 4)
	Utility.TweenFast = TweenInfo.new(BASE_FAST * mult, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	Utility.TweenMed  = TweenInfo.new(BASE_MED * mult, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
end

-- Creates an instance, applies properties, parents CHILDREN first,
-- and sets Parent last so properties replicate/apply in one batch.
function Utility.Create(className, properties, children)
	local instance = Instance.new(className)
	local parent
	for key, value in pairs(properties or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	-- Gamepad navigation: interactive classes are Selectable unless the caller
	-- said otherwise. Harmless for mouse/touch, required for console focus.
	if (className == "TextButton" or className == "TextBox")
		and (properties == nil or properties.Selectable == nil) then
		instance.Selectable = true
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	instance.Parent = parent
	return instance
end

function Utility.Tween(instance, tweenInfo, goals)
	local tween = TweenService:Create(instance, tweenInfo, goals)
	tween:Play()
	return tween
end

function Utility.Clamp(n, a, b)
	return math.max(a, math.min(b, n))
end

function Utility.Round(n, step)
	if not step or step == 0 then
		return n
	end
	return math.floor(n / step + 0.5) * step
end

function Utility.IsPrimary(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

--------------------------------------------------------------------
-- Shared input dispatch (2.6.1): ONE engine connection per signal kind, no
-- matter how many controls listen — instead of N components × 3 permanent
-- UserInputService connections. Listeners are keyed by their owning
-- GuiObject in weak tables, so dead controls are pruned on the next event
-- and collect without any disconnect bookkeeping.
--------------------------------------------------------------------
local inputBuckets = {
	Began = setmetatable({}, { __mode = "k" }),
	Ended = setmetatable({}, { __mode = "k" }),
	Changed = setmetatable({}, { __mode = "k" }),
}
local inputConnected = {}

local function ensureInputConnected(kind)
	if inputConnected[kind] then
		return
	end
	inputConnected[kind] = true
	local bucket = inputBuckets[kind]
	UserInputService["Input" .. kind]:Connect(function(input, arg2)
		for owner, fns in pairs(bucket) do
			if owner.Parent == nil then
				bucket[owner] = nil -- dead control: stop paying for it
			else
				for _, fn in ipairs(fns) do
					fn(input, arg2)
				end
			end
		end
	end)
end

-- Utility.OnInput("Began"|"Ended"|"Changed", ownerGuiObject, fn)
-- fn receives (input, arg2); arg2 is gameProcessed for Began only.
function Utility.OnInput(kind, owner, fn)
	assert(inputBuckets[kind] ~= nil and owner ~= nil and type(fn) == "function",
		"[Atlas] Utility.OnInput(kind, owner, fn) — kind must be Began/Ended/Changed")
	ensureInputConnected(kind)
	local fns = inputBuckets[kind][owner]
	if fns == nil then
		fns = {}
		inputBuckets[kind][owner] = fns
	end
	table.insert(fns, fn)
	return fn
end

-- Micro-interaction: shrinks a button ~5% while pressed (mouse or touch),
-- then eases back. Uses a child UIScale so it composes with other effects.
function Utility.AddPressEffect(guiButton)
	local scale = guiButton:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Instance.new("UIScale")
		scale.Parent = guiButton
	end
	guiButton.InputBegan:Connect(function(input)
		if Utility.IsPrimary(input) then
			Utility.Tween(scale, Utility.TweenFast, { Scale = 0.95 })
		end
	end)
	local function release()
		Utility.Tween(scale, Utility.TweenMed, { Scale = 1 })
	end
	guiButton.InputEnded:Connect(function(input)
		if Utility.IsPrimary(input) then
			release()
		end
	end)
	guiButton.MouseLeave:Connect(release)
end

-- Dragging. scaleFn (optional) returns the active UIScale value; pointer
-- deltas live in screen pixels while Position offsets live in scaled pixels,
-- so the delta must be divided by the scale or the frame outruns the cursor.
function Utility.MakeDraggable(frame, handle, scaleFn)
	local dragging = false
	local dragOrigin = Vector3.zero
	local startPosition

	handle.InputBegan:Connect(function(input)
		if not Utility.IsPrimary(input) then
			return
		end
		dragging = true
		dragOrigin = input.Position
		startPosition = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end)

	Utility.OnInput("Changed", frame, function(input) -- weak: dies with the window
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local scale = scaleFn and scaleFn() or 1
		if scale <= 0 then
			scale = 1
		end
		local delta = (input.Position - dragOrigin) / scale
		frame.Position = UDim2.new(
			startPosition.X.Scale, startPosition.X.Offset + delta.X,
			startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
		)
	end)
end

-- A tiny RAII-style container for RBXScriptConnections.
function Utility.ConnectionBag()
	local bag = { _connections = {} }
	function bag:Add(connection)
		table.insert(self._connections, connection)
		return connection
	end
	function bag:DisconnectAll()
		for _, connection in ipairs(self._connections) do
			connection:Disconnect()
		end
		table.clear(self._connections)
	end
	return bag
end

return Utility
