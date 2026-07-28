# Atlas

A zero-asset, component-based UI library for Roblox, written in plain Luau. Every element is constructed from `Instance` graphs at runtime — no image uploads, no plugins, no external tooling required. Intended for in-experience settings panels, admin consoles, and debug interfaces in your own Studio projects.

## Features

**Core components**

- Windows (draggable, minimizable, optional resize grip, global toggle key)
- Tabs and scrollable pages, collapsible sections
- Button, Toggle, Slider, Dropdown, Keybind capture, Text input, RichText labels

**Expanded component tier**

- Segmented control, multi-select dropdown, number stepper, progress bar
- Full HSV color picker (SV square + hue track + hex entry + presets)

**Services**

- Notifications (stacking, fading, auto-dismiss, accent tokens)
- Tooltips attachable to any component handle (`handle.Root`)
- Modal dialogs (`Prompt` / `Alert`)
- Command palette (`Ctrl+K`) with a command registry
- Configuration profiles: save/load/delete in-session, JSON serialization with safe EnumItem/Color3 boxing, optional DataStore round trip via the included server script
- Runtime theming (`Dark`/`Light` built in, custom themes via `Theme.Register`), UI scaling

## Installation

### Option A — Roblox Studio (manual)

1. In `ReplicatedStorage`, insert a **Folder** named `Atlas`.
2. Inside it, insert three **ModuleScript** instances named `Theme`, `Utility`, and `Library`, and paste the contents of the corresponding files from `src/Atlas/`.
3. In `StarterPlayer > StarterPlayerScripts`, insert a **LocalScript** and paste `src/StarterPlayerScripts/AtlasDemo.client.lua`.
4. Press **Play**. Toggle the window with <kbd>RightShift</kbd>; open the command palette with <kbd>Ctrl</kbd>+<kbd>K</kbd>.

### Option B — Rojo

```bash
git clone <your-repo-url> atlas-ui
cd atlas-ui
rojo serve        # then connect from the Rojo Studio plugin
```

`default.project.json` maps `src/Atlas` to `ReplicatedStorage.Atlas`, the demo to `StarterPlayerScripts`, and the optional persistence script to `ServerScriptService`.

## Project structure

```
atlas-ui/
├── LICENSE
├── README.md
├── default.project.json
└── src/
    ├── Atlas/
    │   ├── Theme.lua                     # design tokens (Dark / Light, custom themes)
    │   ├── Utility.lua                   # instance factory, tweens, dragging, connection bags
    │   └── Library.lua                   # manager, all components, all services
    ├── StarterPlayerScripts/
    │   └── AtlasDemo.client.lua          # demo harness / usage reference
    └── ServerScriptService/
        └── ConfigSync.server.lua         # OPTIONAL DataStore persistence for profiles
```

> The library must be `require`d from a **LocalScript** — it builds under `Players.LocalPlayer.PlayerGui`. Requiring it from a server Script raises an error by design.

## Quick start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"):WaitForChild("Library"))

local window = Atlas:CreateWindow({ Title = "Settings", Resizable = true })
local tab = window:CreateTab({ Title = "Gameplay" })
local section = tab:CreateSection({ Title = "Camera" })

section:CreateToggle({
    Title = "Field of View Lock",
    Flag = "FovLock",
    Callback = function(on) print(on) end,
})

section:CreateSlider({
    Title = "Field of View",
    Min = 60, Max = 120, Step = 1, Default = 70,
    Flag = "Fov",
    Callback = function(v) workspace.CurrentCamera.FieldOfView = v end,
})
```

## API overview

| Category | Entry points | Notes |
|---|---|---|
| Windows | `Atlas:CreateWindow{...}`, `Window:SetVisible/SetMinimized/Destroy` | `ToggleKey` defaults to RightShift |
| Tabs / Sections | `Window:CreateTab{...}`, `Tab:CreateSection{...}` | `Collapsible = true` supported |
| Inputs | `CreateButton/Toggle/Slider/Dropdown/Keybind/Input/Label` | All flaggable via `Flag = "..."` |
| Inputs (tier 2) | `CreateSegmented/MultiDropdown/Stepper/Progress/ColorPicker/Divider` | Color picker returns `Color3` |
| Overlays | `Atlas:Notify{...}`, `Atlas:AddTooltip(gui, text)`, `Atlas:Prompt/Alert{...}` | Notifications auto-dismiss |
| Palette | `Atlas:RegisterCommand{Name, Category, Callback}` | `Ctrl+K` to open |
| Theming | `Atlas:SetTheme(name)`, `Atlas:GetThemeNames()`, `Theme.Register(name, overrides)` | Live rebind, no rebuild |
| Scaling | `Atlas:SetScale(0.5–2)` | ScreenGui-level `UIScale` |
| Profiles | `Atlas:Save/Load/Delete/GetConfigs`, `SerializeConfigs`, `DeserializeConfigs`, `GetFlag(flag)` | JSON-safe; EnumItems/Color3 boxed |

## Persistence (optional)

Settings profiles are session-scoped by default. For durable per-player storage, keep `ConfigSync.server.lua` in `ServerScriptService`, then uncomment the footer block in `AtlasDemo.client.lua`. The server script whitelists the `save` action and caps payloads at 60 KB — treat client-supplied data as untrusted and clamp gameplay-sensitive values server-side.

## Contributing

Issues and pull requests welcome. Keep additions within the library's invariants: zero assets, event-driven updates (no `RenderStepped` polling), theme rebindability via `bind()`/`T()`, and `pcall`-isolated user callbacks.

## License

MIT — see [LICENSE](LICENSE).
