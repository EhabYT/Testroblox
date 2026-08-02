--!nonstrict
-- Theme.lua — Design tokens for the Atlas interface library.
-- Part of atlas-ui (MIT License).

local Theme = {}

Theme.Tokens = {
	Dark = {
		Background  = Color3.fromRGB(16, 17, 20),
		Surface     = Color3.fromRGB(24, 25, 30),
		SurfaceAlt  = Color3.fromRGB(31, 33, 39),
		Hover       = Color3.fromRGB(41, 43, 51),
		Stroke      = Color3.fromRGB(52, 55, 64),
		Accent      = Color3.fromRGB(94, 106, 242),
		OnAccent    = Color3.fromRGB(255, 255, 255),
		Text        = Color3.fromRGB(236, 238, 241),
		TextDim     = Color3.fromRGB(152, 155, 164),
		Success     = Color3.fromRGB(67, 181, 129),
		Danger      = Color3.fromRGB(237, 66, 69),
		Font        = Enum.Font.Gotham,
		FontMedium  = Enum.Font.GothamMedium,
		FontBold    = Enum.Font.GothamBold,
		Corner      = UDim.new(0, 8),
	},
}

-- Light is a sparse override over Dark: clone first so new tokens never go missing.
Theme.Tokens.Light = table.clone(Theme.Tokens.Dark)
Theme.Tokens.Light.Background = Color3.fromRGB(241, 242, 246)
Theme.Tokens.Light.Surface    = Color3.fromRGB(255, 255, 255)
Theme.Tokens.Light.SurfaceAlt = Color3.fromRGB(245, 246, 250)
Theme.Tokens.Light.Hover      = Color3.fromRGB(231, 233, 240)
Theme.Tokens.Light.Stroke     = Color3.fromRGB(206, 209, 218)
Theme.Tokens.Light.Text       = Color3.fromRGB(31, 33, 38)
Theme.Tokens.Light.TextDim    = Color3.fromRGB(104, 107, 116)

-- Midnight is a sparse override over Dark: deep blue-black with a cool accent.
Theme.Tokens.Midnight = table.clone(Theme.Tokens.Dark)
Theme.Tokens.Midnight.Background = Color3.fromRGB(10, 13, 21)
Theme.Tokens.Midnight.Surface    = Color3.fromRGB(17, 21, 33)
Theme.Tokens.Midnight.SurfaceAlt = Color3.fromRGB(23, 28, 43)
Theme.Tokens.Midnight.Hover      = Color3.fromRGB(31, 37, 55)
Theme.Tokens.Midnight.Stroke     = Color3.fromRGB(44, 52, 74)
Theme.Tokens.Midnight.Accent     = Color3.fromRGB(88, 140, 255)
Theme.Tokens.Midnight.Text       = Color3.fromRGB(232, 237, 248)
Theme.Tokens.Midnight.TextDim    = Color3.fromRGB(141, 150, 172)

-- HighContrast: pure black surfaces, bright strokes, TV-safe accent — for
-- ten-foot viewing distance (console) and low-visibility scenarios.
Theme.Tokens.HighContrast = table.clone(Theme.Tokens.Dark)
Theme.Tokens.HighContrast.Background = Color3.fromRGB(0, 0, 0)
Theme.Tokens.HighContrast.Surface    = Color3.fromRGB(10, 10, 10)
Theme.Tokens.HighContrast.SurfaceAlt = Color3.fromRGB(20, 20, 20)
Theme.Tokens.HighContrast.Hover      = Color3.fromRGB(45, 45, 45)
Theme.Tokens.HighContrast.Stroke     = Color3.fromRGB(130, 130, 130)
Theme.Tokens.HighContrast.Accent     = Color3.fromRGB(0, 200, 255)
Theme.Tokens.HighContrast.OnAccent   = Color3.fromRGB(0, 0, 0)
Theme.Tokens.HighContrast.Text       = Color3.fromRGB(255, 255, 255)
Theme.Tokens.HighContrast.TextDim    = Color3.fromRGB(205, 205, 205)

function Theme.Get(name)
	return Theme.Tokens[name] or Theme.Tokens.Dark
end

function Theme.Names()
	local names = {}
	for key in pairs(Theme.Tokens) do
		table.insert(names, key)
	end
	table.sort(names)
	return names
end

function Theme.Register(name, overrides)
	assert(type(name) == "string" and name ~= "", "[Atlas] Theme.Register requires a name")
	local clone = table.clone(Theme.Tokens.Dark)
	for key, value in pairs(overrides or {}) do
		clone[key] = value
	end
	Theme.Tokens[name] = clone
	-- Snapshot defaults so ResetTheme() also works for themes registered at runtime.
	local copy = {}
	for key, value in pairs(clone) do
		copy[key] = value
	end
	Theme.Defaults[name] = copy
	return clone
end

-- Factory snapshot: ResetTheme() copies these back over the working tables.
Theme.Defaults = {}
for name, tokens in pairs(Theme.Tokens) do
	local copy = {}
	for key, value in pairs(tokens) do
		copy[key] = value
	end
	Theme.Defaults[name] = copy
end

return Theme
