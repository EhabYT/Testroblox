# Atlas UI

**Atlas** is a zero-asset, component-based interface library for Roblox, written in Luau.
Every element is built from plain `Instance` graphs at runtime — no images, no models, no external dependencies. One module, paste, play.

Rebuilt from scratch in **v2.0.0** around a single idea: **the interface adapts to the device** — phone, tablet/iPad, desktop, or console — automatically.

> Current version: **2.15.0** — see [CHANGELOG.md](CHANGELOG.md).

## Features

- **Device-adaptive by design (v2)**: a dedicated `Device` module classifies the player as **Phone / Tablet / Desktop / Console** (community-standard pattern: `IsTenFootInterface`, touch-vs-mouse, smallest viewport dimension) and drives everything
- **Menu size follows the device**: `CreateWindow()` with no `Size` picks a per-class default, clamps explicit sizes to the safe viewport (notch/overscan margins), and never lets `size × UIScale` overflow the screen
- **Rotate-safe**: turn a phone/iPad (or resize the window) and every open Atlas window re-clamps size and keeps its title bar reachable — live, via `ViewportSizeChanged`
- Handhelds get automatic UIScale (1.25/1.15/1.1), compact sidebar, floating menu toggler, degraded keybind hints, and 44 px-friendly targets
- 24 components: Button, Toggle, Switch, Slider (knob swell), RangeSlider (dual-thumb), Dropdown (searchable, `SetOptions`), MultiDropdown, Keybind, Input (numeric mode), TextArea (multi-line, char limit), Label, Paragraph, Segmented, Stepper, Progress, ColorPicker (live `ThemeToken`), RadioGroup, ChipList (removable tags), Accordion (collapsible panels), Breadcrumb (navigation path), Rating (star selector), TimePicker (h:m steppers), Divider
- Services: notifications (action buttons, grow-in, cap 8, toast queue), tooltips (hover **and** long-press), prompts/alerts (optional text field), command palette (Ctrl+K), loading screen, watermark (FPS/ping), keyboard shortcuts (`AddShortcut`), status bar (persistent bottom strip), profiles (JSON, autosave)
- Live theming everywhere: `SetToken` rebinds colors, corners **and fonts** instantly; Dark / Light / Midnight built in; themes export/import as JSON
- Polished motion: press feedback on every control, tab accent rail, window pop-in, rotating chevrons
- Zero assets, zero dependencies, MIT licensed

## Installation

### Option A — Roblox Studio (manual)

1. In **ReplicatedStorage**, insert a **Folder** named `Atlas`.
2. Inside it add four **ModuleScripts**: `Theme`, `Device`, `Utility`, `Library` — paste the matching file from `src/Atlas/` into each.
3. In **StarterPlayer > StarterPlayerScripts**, insert a **LocalScript** and paste `src/StarterPlayerScripts/AtlasDemo.client.lua`.
4. Press **Play** — try it with Studio's device emulator (Test tab) to watch the menu adapt per device.

### Option B — Rojo

Uses the included `default.project.json`:

```bash
rojo serve
```

### Option C — Single-file build (one ModuleScript)

Paste `releases/Atlas.lua` into ONE ModuleScript named `Atlas` in ReplicatedStorage, then from any LocalScript:

```lua
local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"))
```

Or publish the ModuleScript and `require(assetId)`. For a zero-setup demo, paste `releases/AtlasComplete.client.lua` into ONE LocalScript in StarterPlayerScripts.

## Project structure

```
atlas-ui/
├── CHANGELOG.md
├── LICENSE
├── README.md
├── default.project.json
├── releases/
│   ├── Atlas.lua                       # single-file build (ModuleScript)
│   └── AtlasComplete.client.lua        # ALL-IN-ONE: library + demo (LocalScript)
├── src/
│   ├── Atlas/
│   │   ├── Device.lua                    # v2 core: device class, safe viewport, adaptive size/scale
│   │   ├── Theme.lua                     # design tokens (Dark / Light / Midnight, custom themes)
│   │   ├── Utility.lua                   # instance factory, tweens, dragging, press feedback
│   │   └── Library.lua                   # manager, all components, all services
│   └── StarterPlayerScripts/
│       └── AtlasDemo.client.lua          # demo harness / usage reference
└── tools/
    └── build.py                          # regenerates releases/ from src/ (python3 tools/build.py)
```

> The library must be `require`d from a **LocalScript** — it builds under `Players.LocalPlayer.PlayerGui`. Requiring it from a server Script raises an error by design.

## Quick start

```lua
local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"):WaitForChild("Library"))

local window = Atlas:CreateWindow({
	Title = "My Menu",
	-- no Size: the device class picks an adaptive size automatically
	ToggleKey = Enum.KeyCode.RightShift, -- desktop toggle
	ToggleButton = true,                 -- floating toggler for phones/tablets
	Resizable = true,
})

local tab = window:CreateTab({ Title = "Main" })
local section = tab:CreateSection({ Title = "Controls" })

section:CreateToggle({
	Title = "Enabled",
	Flag = "Enabled",
	Callback = function(on) print(on) end,
})
```

Device info, if you need it in your own code:

```lua
Atlas.Device.Class()          -- "Phone" | "Tablet" | "Desktop" | "Console"
Atlas.Device.Viewport()       -- usable viewport (Vector2)
Atlas.Device.OnViewportChanged(function(v) ... end) -- rotation/resize
```

## API overview

| Category | Entry points | Notes |
|---|---|---|
| Device (v2) | `Atlas.Device.Class/IsMobile/IsTouchOnly/Viewport/MaxMenuSize/MenuSize/UIScale/NotifyWidth/OnViewportChanged` | One source of truth for adaptive sizing |
| Windows | `Atlas:CreateWindow{...}`, `Window:SetVisible/SetMinimized/SetSize/GetSize/SetTitle/Destroy` | `ToggleKey` defaults to RightShift (+ optional `GamepadToggleKey` for controllers; rebind live via `Window:SetToggleKey`); `BlurBackdrop = true` adds a Lighting blur while open; `SettingsTab = "Title"` adds a ⚙ title-bar button that jumps to that tab |
| Window layout | `Window:SetPosition(udim2)`, `Window:GetPosition()`, `Window:Center()`, `CreateWindow{ RememberLayout = true \| "Flag" }` | Positions clamp on-screen; RememberLayout snapshots position+size into every profile save/load; `SetSidebarPosition("left"/"right")` flips the sidebar |
| Menu toggler | `CreateWindow{ ToggleButton = true/false/"auto" }`, `Window:SetToggleButton(on)`, `Window:GetToggleButton()` | Floating ≡ button; tap toggles, drag moves, **right-click/long-press opens a quick menu**; auto-shows on touch devices |
| Loading screen | `Atlas:ShowLoadingScreen{...}`, `CreateWindow{ LoadingScreen = {...} }` | Auto `Duration` or manual `loader:SetProgress`/`Done()` |
| Console / gamepad | all controls Selectable by default, window + modal SelectionGroups, auto focus on show, B = back | D-pad/stick navigates, A activates, focused sliders adjust via D-pad/stick; pair with `GamepadToggleKey` |
| Tabs / Sections | `Window:CreateTab{...}`, `Tab:CreateSection{...}`, `Window:SelectTab(tabOrTitle)`, `Tab:SetBadge(v)` | `Collapsible = true`; badges on both levels: `Tab:SetBadge(v)` / `Section:SetBadge(v)` |
| Inputs | `CreateButton/Toggle/Slider/Dropdown/Keybind/Input/Label` | All flaggable via `Flag = "..."`; Input `Numeric = true, Min, Max`; Dropdown `Searchable = true` + `Width` |
| Inputs (tier 2) | `CreateSegmented/MultiDropdown/Stepper/Progress/ColorPicker/Divider` | ColorPicker: `ThemeToken = "Accent"` follows theme edits/resets; MultiDropdown supports `Searchable = true`; Progress has indeterminate `Marquee` mode (`handle:SetMarquee(on)`) |
| Inputs (tier 3) | `CreateSwitch/TextArea/RangeSlider/RadioGroup` | Switch: labeled two-state with custom on/off text; TextArea: multi-line with `MaxLength`; RangeSlider: dual-thumb min/max with `DefaultMin`/`DefaultMax`; RadioGroup: exclusive vertical radios |
| Inputs (tier 4) | `CreateChipList/Accordion/Breadcrumb/Rating/TimePicker` | ChipList: add/remove tags with input; Accordion: collapsible FAQ-style panels (exclusive or multi); Breadcrumb: clickable path; Rating: 1–N star selector with hover preview; TimePicker: h:m steppers (12/24h) |
| Text | `CreateLabel{...}`, `CreateParagraph{ Title, Text }` | RichText + wrapping; `SetText`/`SetTitle` handles |
| Overlays | `Atlas:Notify{...}`, `Atlas:AddTooltip(gui, text)`, `Atlas:Prompt/Alert{...}` | `Notify{ Action = {...} }`; `Prompt{ Input = true }` passes `(choice, text)`; `GetNotificationHistory()` = last 15 toasts; `ShowNotificationCenter()` modal panel with Clear All + per-row ×, toasts are swipe-to-dismiss |
| Context menu | `Atlas:ContextMenu{ Items, Position? }`, `Atlas:AddContextMenu(gui, items\|fn)`, `Atlas:CloseContextMenu()` | Right-click / 0.55 s stationary long-press; items support `Disabled`, `Danger`, `"separator"` and `Submenu = {...}` (one level); auto-width, viewport-clamped; touch long-press sets `AtlasSuppressClick` on the target (swallow it in your own Activated handlers) |
| Watermark | `Atlas:SetWatermark{...}`, `Atlas:SetWatermarkVisible(on)` | Draggable pill, live FPS (+ ping); `RememberLayout = true` persists the position in profiles |
| Palette | `Atlas:RegisterCommand{Name, Category, Callback}` | `Ctrl+K` to open; optional `Priority` sorts results |
| Toast queue | `Atlas:QueueNotifications(list, config?)` | Sequential batch: each toast plays after the prior dismisses; `Gap` between; `OnComplete` fires at end |
| Shortcuts | `Atlas:AddShortcut{Keys, Name, Callback}`, `Atlas:GetShortcuts()` | Modifier+trigger combos; returns a handle with `:Disconnect()` and `:SetEnabled(on)` |
| Status bar | `Atlas:SetStatusBar{Text, Accent, Visible}`, `SetStatusBarText(s)`, `SetStatusBarVisible(on)` | Persistent bottom strip; accent dot indicator; theme-bound |
| Theming | `Atlas:SetTheme(name)`, `Atlas:GetThemeNames()`, `Theme.Register(name, overrides)` | Live rebind, no rebuild |
| Live tokens | `Atlas:SetToken(name, value)`, `Atlas:GetToken(name)`, `Atlas:ResetTheme()`, `Atlas:OnThemeChanged(fn)` | Colors, corner radius **and fonts** rebind live |
| Theme sharing | `Atlas:ExportTheme()`, `Atlas:ImportTheme(json[, name])` | Active theme ⇄ shareable JSON |
| Scaling | `Atlas:SetScale(0.5–2)`, `Atlas:GetScale()` | ScreenGui-level `UIScale` |
| Profiles | `Atlas:Save/Load/Delete/GetConfigs`, `SerializeConfigs`, `DeserializeConfigs`, `GetFlag(flag)`, `SetAutoSave(name, secs)` | JSON-safe; silent restores; autosave loops replace each other |

## Component showcase

Every `Section:CreateX` supports `Flag = "..."` (profile persistence) and returns a handle with `Set`/`Get` (plus extras noted below).

| Component | Signature sketch | Extras |
|---|---|---|
| Button | `CreateButton{ Title, Callback }` | — |
| Toggle | `CreateToggle{ Title, Default, Callback }` | — |
| Slider | `CreateSlider{ Title, Min, Max, Step, Default, Suffix }` | gamepad-adjustable |
| Dropdown | `CreateDropdown{ Title, Options, Default, Width }` | `Searchable`, `SetOptions`, `OptionColors` swatch dots |
| MultiDropdown | `CreateMultiDropdown{ Title, Options, Default }` | `Searchable`, multi-select set |
| Keybind | `CreateKeybind{ Title, Default, Callback }` | keyboard + pad capture |
| Input | `CreateInput{ Title, Placeholder, Default }` | `Numeric, Min, Max` |
| Segmented | `CreateSegmented{ Title, Options, Default }` | `Width` |
| Stepper | `CreateStepper{ Title, Min, Max, Step, Default }` | — |
| Progress | `CreateProgress{ Title, Default, ShowPercent }` | `Marquee`, `SetLabel` |
| ColorPicker | `CreateColorPicker{ Title, Default }` | `ThemeToken` two-way sync, hex field |
| Label | `CreateLabel{ Text, Dim?, TextSize? }` | `SetText` |
| Paragraph | `CreateParagraph{ Title, Text }` | `SetTitle`/`SetText` |
| Switch | `CreateSwitch{ Title, OnText, OffText, Default }` | labeled two-state with sliding indicator |
| TextArea | `CreateTextArea{ Title, Placeholder, Height, MaxLength }` | multi-line, char counter |
| RangeSlider | `CreateRangeSlider{ Title, Min, Max, Step, DefaultMin, DefaultMax }` | dual-thumb min/max |
| RadioGroup | `CreateRadioGroup{ Title, Options, Default }` | exclusive vertical radios |
| ChipList | `CreateChipList{ Title, Default, MaxTags, Placeholder }` | add/remove tags, `Add`/`Remove` handles |
| Accordion | `CreateAccordion{ Title, Items, DefaultOpen, Exclusive }` | collapsible panels, `Open`/`CloseAll` |
| Breadcrumb | `CreateBreadcrumb{ Items, Callback }` | clickable nav path, `SetItems` |
| Rating | `CreateRating{ Title, Max, Default }` | star selector with hover preview |
| TimePicker | `CreateTimePicker{ Title, DefaultHour, DefaultMinute, MinuteStep, Use24Hour }` | h:m steppers |
| Divider | `CreateDivider()` | — |

## Persistence

Settings profiles are session-scoped. `Atlas:SerializeConfigs()` / `Atlas:DeserializeConfigs(json)` produce and consume plain JSON, so durable storage can be wired to any transport you own (DataStore, profile services, etc.) — sanitize client-supplied data server-side as always.

## Contributing

Issues and PRs are welcome. Keep the library zero-asset: if a feature needs an image, draw it with frames or don't ship it. Run `python3 tools/build.py` after editing `src/` and make sure both release files regenerate cleanly.

## License

MIT — see [LICENSE](LICENSE).
