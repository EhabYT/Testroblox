--!nonstrict
-- Device.lua — Device classification + adaptive sizing for atlas-ui v2.
--
-- One source of truth for "what device is this and how big should the UI be".
-- Classification follows the Roblox community-standard pattern:
--   1. GuiService:IsTenFootInterface()                -> Console
--   2. TouchEnabled and not MouseEnabled              -> touch device,
--      split by smallest viewport dimension (>600 px) -> Tablet, else Phone
--   3. everything else                                -> Desktop
-- Touch-screen PCs are handled by the MouseEnabled check.
-- Part of atlas-ui (MIT License).

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Device = {}

--------------------------------------------------------------------
-- Classification
--------------------------------------------------------------------

-- Returns "Console" | "Tablet" | "Phone" | "Desktop".
function Device.Class()
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local cam = workspace.CurrentCamera
		local view = cam and cam.ViewportSize or Vector2.new(800, 600)
		if math.min(view.X, view.Y) > 600 then
			return "Tablet"
		end
		return "Phone"
	end
	return "Desktop"
end

-- True for phones/tablets with no mouse+keyboard (legacy helper).
function Device.IsTouchOnly()
	return UserInputService.TouchEnabled
		and not UserInputService.KeyboardEnabled
		and not UserInputService.MouseEnabled
end

-- True when the player is on a handheld touch device class.
function Device.IsMobile()
	local class = Device.Class()
	return class == "Phone" or class == "Tablet"
end

--------------------------------------------------------------------
-- Viewport & safe margins
--------------------------------------------------------------------

-- Usable viewport (camera viewport; GuiService inset is reserved for core UI).
function Device.Viewport()
	local cam = workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(800, 600)
end

-- Safe margin per class (notches, rounded corners, TV overscan).
local MARGINS = { Phone = 12, Tablet = 24, Desktop = 48, Console = 48 }
-- Preferred menu size per class (still clamped to the safe viewport).
local MENU_SIZE = {
	Phone = { 560, 460 },
	Tablet = { 680, 500 },
	Desktop = { 720, 520 },
	Console = { 760, 540 },
}

-- Maximum menu size in pixels for the class (viewport minus margins, floored
-- at the library minimums so tiny windows never disappear).
function Device.MaxMenuSize(class)
	class = class or Device.Class()
	local view = Device.Viewport()
	local margin = MARGINS[class] or 24
	return math.max(view.X - margin * 2, 260), math.max(view.Y - margin * 2, 300)
end

-- Recommended default menu size for the class.
function Device.MenuSize(class)
	class = class or Device.Class()
	local maxW, maxH = Device.MaxMenuSize(class)
	local want = MENU_SIZE[class] or MENU_SIZE.Desktop
	return UDim2.fromOffset(math.min(want[1], maxW), math.min(want[2], maxH))
end

-- Recommended UIScale for the class (handhelds need bigger touch targets).
function Device.UIScale(class)
	class = class or Device.Class()
	local view = Device.Viewport()
	if class == "Phone" then
		return view.Y <= 420 and 1.25 or 1.15
	elseif class == "Tablet" then
		return view.Y <= 640 and 1.1 or 1.0
	end
	return 1
end

-- Notification toast width clamped to the viewport.
function Device.NotifyWidth()
	local view = Device.Viewport()
	return math.clamp(math.floor(view.X - 24), 220, 300)
end

--------------------------------------------------------------------
-- Viewport change notifications (rotation, window resize)
--------------------------------------------------------------------

local listeners = {}

-- Registers fn(viewport: Vector2); returns a handle with :Disconnect().
-- Handles CurrentCamera swaps internally.
function Device.OnViewportChanged(fn)
	assert(type(fn) == "function", "[Atlas] OnViewportChanged expects a function")
	local entry = { fn = fn, Connected = true }
	table.insert(listeners, entry)
	local handle = {}
	function handle:Disconnect()
		entry.Connected = false
	end
	return handle
end

local function fireViewportChanged()
	local view = Device.Viewport()
	local alive = {}
	for _, entry in ipairs(listeners) do
		if entry.Connected then
			table.insert(alive, entry)
			pcall(entry.fn, view)
		end
	end
	listeners = alive
end

local cameraConn
local function bindCamera()
	if cameraConn then
		cameraConn:Disconnect()
		cameraConn = nil
	end
	local cam = workspace.CurrentCamera
	if cam then
		cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(fireViewportChanged)
	end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)
bindCamera()

return Device
