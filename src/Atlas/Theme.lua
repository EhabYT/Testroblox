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
		AccentHover = Color3.fromRGB(112, 123, 247),
		OnAccent    = Color3.fromRGB(255, 255, 255),
		Text        = Color3.fromRGB(236, 238, 241),
		TextDim     = Color3.fromRGB(152, 155, 164),
		Success     = Color3.fromRGB(67, 181, 129),
		Warning     = Color3.fromRGB(250, 168, 26),
		Danger      = Color3.fromRGB(237, 66, 69),
		Font        = Enum.Font.Gotham,
		FontMedium  = Enum.Font.GothamMedium,
		FontBold    = Enum.Font.GothamBold,
		Corner      = UDim.new(0, 8),
		CornerSmall = UDim.new(0, 6),
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
	return clone
end

return Theme
