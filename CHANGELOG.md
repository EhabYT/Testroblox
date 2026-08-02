# Changelog

All notable changes to atlas-ui are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.14.0] — 2026-08-02

### Added
- **Switch component**: `CreateSwitch{ Title, OnText, OffText, Default, Flag, Callback }` — a labeled two-state control with a sliding indicator and custom text for each state (e.g. "PvP"/"PvE", "On"/"Off"), distinct from Toggle's silent pill
- **TextArea component**: `CreateTextArea{ Title, Placeholder, Height, MaxLength, Flag, Callback }` — multi-line text input with word wrap, configurable height, and optional live character counter with enforcement
- **RangeSlider component**: `CreateRangeSlider{ Title, Min, Max, Step, DefaultMin, DefaultMax, Suffix, Flag, Callback }` — dual-thumb slider for selecting a min/max range; click proximity determines which knob moves; callback receives `(lo, hi)`
- **RadioGroup component**: `CreateRadioGroup{ Title, Options, Default, Flag, Callback }` — vertical exclusive radio buttons with animated inner-dot selection, visually distinct from the horizontal Segmented control
- **Keyboard shortcuts service**: `Atlas:AddShortcut{ Keys, Name, Callback }` — register global modifier+key combos (e.g. `{ Enum.KeyCode.LeftControl, Enum.KeyCode.S }`); returns a handle with `:Disconnect()` and `:SetEnabled(on)`; `Atlas:GetShortcuts()` lists active bindings
- **Status bar service**: `Atlas:SetStatusBar{ Text, Accent, Visible }` — persistent bottom-edge strip with optional accent dot indicator, theme-bound; `Atlas:SetStatusBarText(s)` and `Atlas:SetStatusBarVisible(on)` for live updates
- Demo: new **Components** tab showcasing all five new components plus the shortcut and status bar services; Ctrl+D toggles the status bar, Ctrl+N sends a test notification, Ctrl+S quick-saves; registry stats now include shortcut count
- Demo: context-menu "Jump to Tab" submenu includes the new Components tab

## [2.13.0] — 2026-08-01

### Added
- **Swipe-to-dismiss toasts**: drag a toast sideways — past 64 px it flies off and fades, otherwise it springs back (scale-aware, weak-keyed listeners)
- **Per-row removal in the Notification Center** — each history row gets a × button (removed by identity, safe when newer entries shifted the indices)
- **MultiDropdown `OptionColors` parity** — same swatch dots as Dropdown (checkbox glyph keeps working)
- `Atlas:GetFlagCount()` + `Atlas:GetCommands()` — registry diagnostics
- Demo: live "Registry" stat line in About (flags · commands · themes)

### Fixed
- Notification Center header buttons overlapped by 10 px (Clear All vs Close offset)

## [2.12.0] — 2026-08-01

### Added
- **Notification Center service**: `Atlas:ShowNotificationCenter()` / `HideNotificationCenter()` — modal history panel over the 15-toast ring: accent dots per entry, timestamps, Clear All (clears ring + dismisses live toasts), backdrop-click/Esc/B close, console focus scope, reopening is a no-op
- FAB quick menu gains **"Notification Center"**, demo gets the button + palette command
- **Dropdown `OptionColors`**: `CreateDropdown{ OptionColors = { [option] = Color3 } }` — a 10 px swatch dot before each label (theme accents showcased in the demo's Color Scheme dropdown)

## [2.11.0] — 2026-08-01

### Added
- **Notification history**: every toast is recorded in a 15-entry ring buffer (newest first) — `Atlas:GetNotificationHistory()` returns `{Title, Text, At, AccentToken}` entries for building your own notification center
- **`Window:SetCloseHandler(fn)`** — gates the × close button: `fn(window)` runs on every close click; returning `false` vetoes the hide (e.g. show a confirm prompt and close asynchronously). ToggleKey stays instant
- `Window:IsVisible()` / `Window:IsMinimized()` getters
- Demo: close-confirmation prompt on ×, "Recent Notifications" section with Refresh (Advanced tab)

## [2.10.0] — 2026-08-01

### Added
- **Progress marquee mode**: `CreateProgress{ Marquee = true }` or `handle:SetMarquee(on)` — indeterminate indicator; a 30 % pill sweeps the track (Sine in-out) until cleared, then the determinate bar returns
- **`Section:SetBadge(v)`** — header bubble with Tab-parity semantics (nil/false/0/"" clears); theme-bound like the tab badge
- Demo: Profiles header bubble tracks the stored-profile count (live on save/import/delete), "Queue (indeterminate)" marquee showcase
- README: **Component showcase** table — all 14 components with signature sketches

## [2.9.0] — 2026-08-01

### Added
- **`Window:SetSidebarPosition("left"|"right")`** — flips the sidebar to the other side of the window; the active tab's accent rail follows automatically (single `_layoutSidebar` source shared with `SetSidebarWidth`)
- Demo: **"Sidebar Side"** segmented control in Layout, **"Cycle Theme →"** button in Presets (uses the dynamic theme list)
- Demo: **profile Export/Import as JSON** — Export opens a pre-filled prompt (Ctrl+A/C to copy), Import validates pasted JSON and reports success/failure

## [2.8.0] — 2026-08-01

### Added
- **HighContrast theme**: pure black surfaces, bright strokes, TV-safe cyan accent — built for ten-foot viewing distance (console) and low-visibility setups; appears everywhere automatically (`Atlas:GetThemeNames()` is dynamic)
- **Palette `Priority` field**: `RegisterCommand{ ..., Priority = n }` — higher floats to the top of every query, ties keep registration order (demo: "Open UI Settings" `+1`, "Hide Interface" `-1`)
- **`Window:SetToggleKey(key[, gamepadKey])` / `GetToggleKey()`** — live-rebind the menu toggle at runtime, no rebuild
- Demo: "Menu Toggle Key" keybind in UI Settings (flagged, profile-persisted)

## [2.7.0] — 2026-08-01

### Performance
- **Coalesced theme flush**: `SetToken`/`SetTheme`/`ResetTheme` schedule ONE retheme per frame via `task.defer` instead of re-applying every binding per call. Dragging a ThemeToken-linked color picker fired SetToken per drag-frame before — 200+ binding writes per mouse pixel — now a single deferred repaint

### Added
- **Keybinds capture gamepad buttons**: while listening, pad-1 buttons count (ButtonA..ButtonR3 are KeyCodes, so capture and trigger share one code path) — the last non-pointer feature is in
- Console hint card mentions pad-button capture

### Notes
- Loading screen audited: already a single CanvasGroup build (one GroupTransparency fade), no allocation work needed

## [2.6.1] — 2026-08-01

### Performance
- **Shared input dispatcher** (`Utility.OnInput`): ONE engine connection per signal kind (`Began`/`Ended`/`Changed`) no matter how many controls listen — previously every slider/keybind/colorpicker held 2–3 permanent global connections (and dead controls kept firing forever). Listeners are weak-keyed by their owning GuiObject: destroyed controls are pruned on the next event, no disconnect bookkeeping
- **ONE shared Heartbeat** drives all gamepad slider watchers (was: one connection per slider); same weak-key self-cleanup
- `MakeDraggable` moved onto the dispatcher — window destruction now prunes its drag listener too
- Toast-cap eviction is single-pass and the prompt Escape path disconnects on any close
- Net effect on the 4-tab demo: permanent engine connections drop ~50%; per-event dispatch cost is flat regardless of control count

### Notes
- No API changes — internal architecture only. Modal overlays (prompt/palette/context menu) keep their own short-lived connections by design

## [2.6.0] — 2026-08-01

### Added
- **Gamepad-adjustable sliders**: with a slider track focused, DPad taps step by `Step` and the left thumbstick sweeps continuously (~full range in 1.7 s, dead-zone 0.15). `SelectionLeft/Right` self-links keep horizontal input from navigating away (classic console-slider trick); the knob swells as adjust feedback
- Console hint card now documents slider adjustment

The whole library — buttons, toggles, dropdowns, inputs, sliders — is now playable without a pointer. (Color-picker drag surfaces remain pointer-only by design.)

## [2.5.0] — 2026-08-01

### Added
- **Console gamepad navigation**: every button/box is `Selectable` by default, windows are `SelectionGroup`s (focus stays inside), showing a window on a console hands focus to the active tab, hiding releases it — the menu is fully D-pad/stick navigable with A-to-activate
- **Controller "B" = back**: closes the menu (and reports `nil` from open `Prompt`/`Alert` dialogs), unless a modal handles it first
- Prompts are console-aware modals: own selection scope, focus lands on the input field (or primary action), previous focus restored on close
- `Tab:SetVisible(bool)` + `Section:SetVisible(bool)` — hide sidebar entries/feature groups at runtime; hiding the active tab reselects the first visible one
- Demo: "Show About Tab" behavior toggle, gamepad hint card on consoles

### Fixed
- Prompt Escape handler no longer leaks a dead connection when the dialog is closed via button (now disconnected in `close()`)

## [2.4.2] — 2026-08-01

### Fixed
- **Minimized bar grew wider than the window on touch devices** — `SetMinimized` collapsed to `AbsoluteSize.X`, which already includes the UIScale (1.15–1.25 on phone/tablet); now uses the pre-scale `Size.X.Offset`
- `Window:SetSize` while minimized wrote `root.Size` directly (bar jumped to full height, restore target went stale) — now routes through `_fullSize`
- `Window:_refit` respected the minimized state incorrectly for the same reason — `_fullSize` shrinks, bar keeps title height
- Duplicate `Flag` names are no longer silent: `[Atlas] Duplicate flag "..."` warns, because the overwritten control would never save/restore

## [2.4.1] — 2026-08-01

### Fixed
- **Long-press on the FAB opened the quick menu AND toggled the window** — the release after a stationary long-press also fired `Activated`. `AddContextMenu` now sets `AtlasSuppressClick` on the target when a touch long-press opens a menu (cleared 0.15 s after InputEnded); the FAB checks it — and any of your buttons can too: `if btn.Root:GetAttribute("AtlasSuppressClick") then return end`
- Settings gear / FAB "Open UI Settings" replayed the window pop-in even when the window was already visible — `SetVisible(true)` now only fires when actually hidden

## [2.4.0] — 2026-08-01

### Added
- **Context-menu submenus**: item `{ Name, Submenu = { ...items } }` — one nesting level, ▸ indicator, expands on hover (touch: tap the parent row), flips left at the screen edge; sibling-hover collapses the chain
- **FAB quick menu**: right-click / long-press the floating ≡ toggler — Open UI Settings (with `SettingsTab`), Center Window, Show/Hide Watermark, Show/Hide Interface; labels track live state, works while the window is hidden
- `CreateWindow{ GamepadToggleKey = Enum.KeyCode.ButtonL3 }` — second toggle binding for controllers (consoles have no RightShift)
- `SetWatermark{ RememberLayout = true }` — dragged watermark position rides along in profile saves/loads (clamped to viewport on restore)
- Demo: "Jump to Tab" submenu showcase, FAB quick-menu hint label, gamepad binding wired

### Changed
- Long-press menus require a **stationary** finger — moving >10 px counts as a drag and cancels (no more menus popping up while dragging the FAB)

## [2.3.1] — 2026-08-01

### Added
- **Settings gear in the title bar**: `CreateWindow{ SettingsTab = "UI Settings" }` adds a ⚙ button next to minimize/close — one always-visible entry point to the settings page; it un-minimizes, reveals the window and selects the tab
- `Window:SelectTab` returns `true/false` and **warns on unknown titles** (a silent no-op looked like "tab broken")

### Fixed
- Sidebar tab buttons truncate gracefully (`TextTruncate = AtEnd`) — long titles on narrow touch sidebars no longer overflow into the page area
- Title label width now adapts to the actual control count (2 or 3 buttons)

## [2.3.0] — 2026-08-01

### Added
- **Context menu service**: `Atlas:ContextMenu{ Items, Position? }` — text-only popup (zero-asset) with auto-width from the live themed font, grow-in, Escape/outside-press dismissal, viewport clamping (flips above the cursor near the screen bottom). Items: `{ Name, Callback, Disabled?, Danger? }` or `"separator"`
- `Atlas:AddContextMenu(gui, items|fn)` — attaches right-click (mouse) or 0.55 s long-press (touch) to any GuiObject; pass a function for menus re-built on every open
- `Atlas:CloseContextMenu()` + handle-returned `:Close()`; only one menu open at a time
- **Window layout persistence**: `CreateWindow{ RememberLayout = true | "Flag" }` — a pseudo-flag snapshots `{cx, cy, w, h}` into every profile save and restores it clamped to the live viewport (minimized windows restore into `_fullSize`)
- `Window:SetPosition(udim2)` / `GetPosition()` / `Center()` / `GetSize()` — positions clamp so the window can never be parked off-screen
- Demo: Context Menu section (click-to-open + right-click/long-press target), "Center Window" palette command, profile note about RememberLayout

### Changed
- `Window:_refit` now shares the new `_clampedCenter` helper (single source for the on-screen rule)
- `Window:Destroy` unregisters the window's layout flag

## [2.2.0] — 2026-07-31

### Added
- **Searchable multi-dropdowns**: `CreateMultiDropdown{ Searchable = true, SearchPlaceholder = "..." }` — same filter UX as single dropdowns (pinned box, auto-focus, clean filter on close)
- **Collapsible sections are flaggable**: `CreateSection{ Collapsible = true, Flag = "Sec_X" }` — collapse state saves/restores with profiles
- `Atlas:DismissNotifications()` — fade out every active toast at once (+ "Clear Notifications" palette command in the demo)

### Changed
- Window pop-in uses **Back easing** — tiny overshoot for a snappier open
- Demo: 12-option searchable "Overlay Layers" multi-dropdown, section flags wired for persistence

## [2.1.0] — 2026-07-31

### Added
- `Library:GetScale()` — public getter for the active UIScale
- Demo: live **Device panel** in About — class, viewport and current scale, refreshed on every viewport change (the perfect emulator showcase for v2)

### Fixed
- **Rotation-stranded overlays**: after rotating a phone/iPad, the floating menu toggler and the watermark could end up off-screen (they're draggable) — both are now re-clamped into the viewport on every size change
- Loading screen stack width now follows the device **class** (Phone 240 / Tablet 300 / Desktop 280) instead of a binary touch check

## [2.0.0] — 2026-07-31

### Rebuilt from scratch — device-adaptive by design
The whole tree was deleted and rewritten around one research-backed idea (see README): the interface adapts to the device, not the other way around.

### Added
- **`Device` module** (`src/Atlas/Device.lua`) — single source of truth for adaptation:
  - `Device.Class()` → `"Phone" | "Tablet" | "Desktop" | "Console"` (community-standard classification: `GuiService:IsTenFootInterface()`, touch-vs-mouse with the touch-PC guard, smallest viewport dimension > 600 → Tablet)
  - `Device.Viewport/MaxMenuSize/MenuSize/UIScale/NotifyWidth` — per-class safe margins, default menu sizes (Phone 560×460, Tablet 680×500, Desktop 720×520, Console 760×540) and recommended UIScale (1.25/1.15/1.1/1)
  - `Device.OnViewportChanged(fn)` — survives camera swaps
- **Rotation-safe windows**: every open window re-clamps size and position on viewport changes so a rotated phone/iPad can never strand the menu off-screen
- **Overflow guard**: rendered size (`size × UIScale`) can never exceed the safe viewport
- `Atlas.Device` exposed on the library table

### Changed
- `CreateWindow` with no `Size` now asks the device class for the menu size; explicit sizes clamp to the safe viewport on every platform
- `Library.IsTouchOnly()` is now a compatibility shim over `Device.IsTouchOnly()`
- Notification width comes from `Device.NotifyWidth()` and re-fits on viewport changes
- `Window:SetSize` clamps via `Device.MaxMenuSize()`
- Demo window no longer passes a size — the device decides; title shows the live version
- Single-file builds now inline four modules (Theme, Utility, Device, Library)

### Preserved
Every component, service and API from 1.x (14 controls, loader, watermark, palette, profiles, theme engine) — proven implementations, reorganized; no duplicate files, no duplicate code paths.

## [1.16.0] — 2026-07-30

### Added
- **Prompts with a text field**: `Atlas:Prompt{ Input = true, Placeholder, Default }` — the Callback now receives `(choice, text)`; pressing Enter in the field commits as the primary button
- **Tab badges**: `Tab:SetBadge(value)` — small accent counter bubble on tab buttons (`Tab:SetBadge(nil)` hides it, also for 0/""/false)
- **Double-click title bar** to minimize/restore the window (clicks over the window buttons are excluded)

### Changed
- Demo: "Save Profile…" now opens the input dialog instead of reading the side input; the profiles autosave toggle raises an "A" badge on the Advanced tab while live
- Tab buttons reserve right-side padding so badges never overlap the title

## [1.15.0] — 2026-07-30

### Added — micro-motion polish, round 2
- **Toast grow-in/out**: notifications now fade AND scale (0.9 → 1 on entry, shrink on dismissal) instead of a flat fade
- **Slider knob swell**: the knob grows on hover and enlarges while dragging — instant "grabbable" feedback (mouse + touch)
- **Rotating section chevrons**: collapsible section headers gain a dedicated ▾ glyph that rotates −90° when collapsed (replaces text-prefix re-rendering) plus a hover brightening state

## [1.14.0] — 2026-07-30

### Added — UI/UX polish pass
- **Press feedback everywhere**: new `Utility.AddPressEffect(button)` micro-interaction (≈5% shrink while pressed, eased release, works with mouse and touch) applied to buttons, dropdowns, segmented controls, steppers, keybind boxes, and palette rows
- **Active tab accent rail**: a small rounded accent bar on the left edge of the selected tab, theme-bound, animated on tab switches
- **Window pop-in**: opening the menu now eases in from ~12 px smaller instead of only fading
- **Dropdown chevron rotation**: the ▾ flips 180° while the list is open (single `setOpen` path also owns search focus/reset)
- Dropdown value text no longer wastes width on the baked-in chevron glyph

## [1.13.0] — 2026-07-30

### Added
- **Blur backdrop**: `CreateWindow{ BlurBackdrop = true }` / `Window:SetBlurBackdrop(on)` — tweens a Lighting `BlurEffect` in and out with the menu's open state; cleaned up on `Destroy`. Low-level `Window:SetBlur(on)` also exposed
- `Window:SetSize(w, h)` — runtime resize with the same minimums as the resize grip (420×280) and the touch viewport clamp
- `Dropdown handle:SetOptions(list)` — rebuild the choices at runtime; the current selection is kept if still valid, otherwise it falls back to the first entry (no callback fired)
- **Long-press tooltips on touch** — hover doesn't exist on mobile, so a 0.5 s hold shows the tip and it stays readable 1.5 s after the finger lifts

### Changed
- Demo: "Blur Background" toggle in UI Settings → Behavior

## [1.12.0] — 2026-07-30

### Added
- `Window:SelectTab(tabOrTitle)` — public tab switching by handle **or title string**, for navigation buttons and palette commands
- Demo: "Open UI Settings →" button at the top of the General tab, plus an "Open UI Settings" palette command (Ctrl+K) that also re-shows the window if hidden

## [1.11.0] — 2026-07-29

### Changed
- **Bigger windows**: desktop default size 620×460 → **720×520**; the demo window 640×470 → **760×540**
- **Touch sizing fix**: an explicit `CreateWindow{ Size = ... }` used to bypass the mobile viewport fit — on touch devices every size is now clamped to the viewport minus 24 px margins (min 260×300), while desktop keeps the passed size verbatim

(Quick in-app control is unchanged: Layout → UI Scale slider, and the resize grip with `Resizable = true`.)

## [1.10.0] — 2026-07-29

### Added
- **Searchable dropdowns**: `CreateDropdown{ Searchable = true, SearchPlaceholder = "..." }` — filter box pinned above the options, case-insensitive substring match, auto-focus on open, filter resets when the list closes; `Width` is now honored on dropdowns too
- **Notification action button**: `Atlas:Notify{ ..., Action = { Text = "Undo", Callback = fn } }` — accent-tinted button under the toast body; acting also dismisses the toast
- **Profile autosave**: `Atlas:SetAutoSave(name, seconds)` — period-snapshots every flagged control into a named profile; `SetAutoSave(nil)` stops it and a new call replaces the old loop (generation-guarded)

### Changed
- Demo: searchable 16-option "Channel" dropdown, "Notification with Action" showcase (toast Undo), "Autosave (every 15 s)" profiles toggle

## [1.9.0] — 2026-07-29

### Added
- **Watermark service**: `Atlas:SetWatermark{ Text, ShowFPS, ShowPing }` — draggable top-left pill with live FPS (2 Hz) and optional ping (Stats service, guarded), theme-bound; `Atlas:SetWatermarkVisible(on)`
- **Paragraph component**: `CreateParagraph{ Title, Text }` — auto-sizing titled text card (RichText, wrapped), `SetText`/`SetTitle` handles
- **Numeric inputs**: `CreateInput{ Numeric = true, Min, Max }` — accepts commas/dots, sanitizes and clamps into range on commit
- **Built-in "Midnight" theme** — deep blue-black palette, available everywhere `GetThemeNames()` is used (demo scheme dropdown, palette)
- `Window:SetTitle(text)` — runtime title-bar rename

### Changed
- Demo: watermark enabled by default (Atlas Demo • FPS • ping) with a Behavior toggle, FOV numeric input in Advanced, About tab now uses Paragraph with the live version string

## [1.8.0] — 2026-07-29

### Added
- **Loading screen**: `Atlas:ShowLoadingScreen{...}` — full-screen branded intro (title, subtitle, staging text, animated progress bar + live %) built from pure shapes, theme-bound and touch-scaled, ZIndex 3000 above every overlay. Auto mode with `Duration`, or manual mode via `loader:SetProgress(0..1[, text])` + `loader:Done()`; `OnComplete` fires after the fade-out, `loader:Destroy()` aborts
- `CreateWindow{ LoadingScreen = {...} }` — window stays hidden while the loader plays, then reveals automatically (user `OnComplete` and `Visible = false` respected; defaults to 2.5 s)
- The menu toggle button starts dimmed during the loading screen
- Demo plays a staged loader at startup (theme engine → components → services → ready) and adds a "Replay Loading Screen" palette command

## [1.7.0] — 2026-07-29

### Added
- **Menu toggler on every platform**: the floating ≡ button (previously touch-only) is now a general window feature — `CreateWindow{ ToggleButton = true }` shows it anywhere; tap/click opens & closes the menu, drag repositions it (10 px threshold prevents accidental toggles)
- `Window:SetToggleButton(on)` — show/hide it at runtime, created lazily if the window was built without one; `Window:GetToggleButton()` returns the instance
- The button now mirrors menu state: full opacity while the menu is open, dimmed while closed
- Demo runs with `ToggleButton = true`, plus a Behavior toggle and a palette command ("Toggle Menu Button") to control it live

### Changed
- `ToggleButton` accepts `true` / `false` / `"auto"` (default auto = touch-only, same behavior as before); legacy `MobileButton = false` still forces it off

### Fixed
- `Window:Destroy()` now also destroys the toggle button (it parents to the ScreenGui, so it used to outlive its window and throw on click)

## [1.6.0] — 2026-07-29

### Added
- **Theme sharing**: `Atlas:ExportTheme()` serializes the active theme to shareable JSON; `Atlas:ImportTheme(json[, name])` registers it as a theme and switches to it — themes are now portable text
- `Atlas:GetToken(name)` — public read accessor for the active theme, mirroring `SetToken`
- JSON boxing now covers `UDim` (in addition to EnumItem/Color3), shared by profiles and theme export
- Demo: new "Share Theme" section in UI Settings — one-tap export into a selectable text box, paste-and-apply import, success/failure notifications

### Fixed
- `ThemeToken`-linked color pickers now push profile restores/programmatic `Set` INTO the token, so a later retheme (from any other control) can no longer silently revert a restored swatch
- `Theme.Register` snapshots defaults for runtime-registered themes, so `ResetTheme()` works on imported themes too

## [1.5.0] — 2026-07-29

### Added
- **Live font bindings**: text created with `Font = "@Token"` (every built-in component) re-renders instantly on `SetToken("Font"/"FontMedium"/"FontBold", ...)` — the demo's Font Family dropdown now retypes the whole window in place, no rebuild
- `Atlas:OnThemeChanged(fn)` — runs `fn` now and after every `SetTheme`/`SetToken`/`ResetTheme`; dead listeners (destroyed UI) are purged automatically like theme bindings
- `CreateColorPicker{ ThemeToken = "Accent" }` — links a picker to a token: seeds its default from the theme and silently re-syncs the swatch on scheme switches and `ResetTheme` (no stale colors, no callback loops)
- The color picker's Accent preset swatch now follows live theme edits and always applies the *current* accent
- `tools/build.py` — the amalgamation script, now versioned: `python3 tools/build.py` regenerates both `releases/` builds from `src/` and fails on unresolved sibling requires

### Changed
- Demo color pickers use `ThemeToken` instead of snapshot defaults, so Reset Theme and the Color Scheme dropdown keep all eight swatches in sync

## [1.4.0] — 2026-07-29

### Added
- Live theme-token editing: `Atlas:SetToken(name, value)` re-applies every binding instantly, `Atlas:ResetTheme()` restores factory values via the new `Theme.Defaults` snapshot, `Atlas:GetThemeName()`
- Public module access: `Atlas.Theme` and `Atlas.Utility` exposed on the library table
- `Window:SetSidebarWidth(px)`, `Window:SetTransparency(t)`, `Atlas:SetNotifySide("Left"/"Right")`, `Utility.SetAnimSpeed(multiplier)`
- Corner radius is now theme-bound on window roots, notification cards, modals, and the palette — `SetToken("Corner", UDim)` reshapes them live
- Demo: the Appearance tab is now a full UI control center (scheme & font presets, eight live color pickers, layout/behavior sliders, notification side toggle, guarded reset)

### Changed
- `SetTheme` internals extracted to `Library:_retheme()` (shared by SetToken/ResetTheme)

## [1.3.0] — 2026-07-29

### Added
- Automatic touch-only profile (`Library.IsTouchOnly()`): adaptive window size clamped to the viewport minus 24 px margins
- Auto `UIScale` bump on phones (1.25 at ≤420 px height, 1.15 on larger touch screens; opt out via `CreateWindow{ AutoMobileScale = false }`)
- Floating draggable toggle button on touch devices — tap shows/hides the window, drag repositions (disable via `CreateWindow{ MobileButton = false }`)
- `Library:OpenPalette()` public API
- Keybind rows degrade gracefully without a keyboard (placeholder + explanatory notice instead of a dead capture box)

### Changed
- Sidebar compacts from 150 px to 112 px on touch devices and narrow (<560 px) windows
- Notification width adapts to viewport (clamped 220–300 px)

## [1.2.0] — 2026-07-29

### Added
- Silent setters: `handle:Set(value, true)` restores values without firing callbacks on Slider, Stepper, Dropdown, and Segmented control — loading a profile no longer triggers gameplay side effects
- Notification cap: at most 8 visible toasts; the oldest is evicted when a ninth arrives

### Changed
- `SetTheme` now purges dead bindings from destroyed windows instead of accumulating them
- Notification layer renders above windows (`ZIndex = 1500`) so toasts are no longer hidden behind open panels

## [1.1.3] — 2026-07-29

### Removed
- Optional `ConfigSync.server.lua` DataStore integration together with its demo and README wiring; in-library session profiles and `SerializeConfigs`/`DeserializeConfigs` remain for custom transports

## [1.1.2] — 2026-07-29

### Changed
- Distribution folder renamed `dist/` → `releases/` (snapshot-safe name)

### Removed
- Dead code identified by usage audit: `Utility.TweenSlow`, theme tokens `AccentHover` / `Warning` / `CornerSmall`, and the internal `Library._windows` registry (no readers)

## [1.1.1] — 2026-07-28

### Added
- `Library.VERSION` field and `Atlas:GetVersion()`
- `dist/Atlas.lua` — single-file ModuleScript build (amalgamated Theme + Utility + Library)
- `dist/AtlasComplete.client.lua` — all-in-one LocalScript build (library + demo bootstrap)
- This CHANGELOG

### Changed
- Dropdown value button is now left-aligned, matching `CreateMultiDropdown` density

### Removed
- `examples/` folder (superseded by `AtlasDemo.client.lua` and the `dist/` builds)

## [1.1.0] — 2026-07-28

### Added
- Component tier 2: Segmented control, Multi-select dropdown, Number stepper, Progress bar, HSV Color picker, Divider
- Services: Tooltips (`Atlas:AddTooltip`), Modal dialogs (`Prompt`/`Alert`), Command palette (`Ctrl+K`), Configuration profiles with JSON-safe EnumItem/Color3 boxing
- Window resize grip (`CreateWindow{ Resizable = true }`), collapsible sections (`CreateSection{ Collapsible = true }`)
- Optional DataStore persistence (`ConfigSync.server.lua`)
- All component handles expose `Root` for tooltip attachment

## [1.0.0] — 2026-07-28

### Added
- Initial release: windows (drag/minimize/close/toggle key), tabs with scrollable pages, sections
- Components: Button, Toggle, Slider, Dropdown, Keybind capture, Text input, RichText labels
- Notification system with accent tokens and auto-dismiss
- Runtime theming (Dark/Light + `Theme.Register`), flag registry, UI scaling
