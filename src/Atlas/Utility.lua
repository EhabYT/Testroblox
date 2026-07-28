--!nonstrict
-- Utility.lua — Instance factory, tweens, dragging, connection bags.
-- Part of atlas-ui (MIT License).

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Utility = {}

Utility.TweenFast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Utility.TweenMed  = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
Utility.TweenSlow = TweenInfo.new(0.40, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

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

	UserInputService.InputChanged:Connect(function(input)
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
