#!/usr/bin/env python3
"""build.py — regenerates the single-file release builds from src/.

Outputs:
  releases/Atlas.lua               — library only (ModuleScript form)
  releases/AtlasComplete.client.lua — library + demo (LocalScript form)

Run from anywhere:  python3 tools/build.py
(Paths are resolved relative to this file, so the CWD does not matter.)
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "releases"

ATLAS_HEADER = """--!nonstrict
-- Atlas.lua — single-file amalgamated build (generated from src/Atlas/*).
-- Part of atlas-ui (MIT License).
--
-- Usage in Studio: insert ONE ModuleScript named "Atlas" into ReplicatedStorage,
-- paste this file, then from a LocalScript:
--     local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"))
-- Or publish the ModuleScript to the Toolbox (public) and use:
--     local Atlas = require(<your-asset-id>)
"""

COMPLETE_HEADER = """--!nonstrict
-- AtlasComplete.client.lua — ALL-IN-ONE build: full Atlas library + demo window.
-- Part of atlas-ui (MIT License). Generated from src/Atlas/* + AtlasDemo.
--
-- USAGE (nothing else needed):
--   1. In Roblox Studio, insert ONE LocalScript into
--      StarterPlayer > StarterPlayerScripts.
--   2. Paste this entire file.
--   3. Press Play (F5). RightShift toggles the window, Ctrl+K opens the palette.
--
-- No ModuleScripts, no folders, no other files required.
"""

DEMO_BANNER = """-- ============================================================
-- Demo bootstrap (merged from src/StarterPlayerScripts/AtlasDemo.client.lua)
-- ============================================================
"""


def read(path):
    return path.read_text(encoding="utf-8")


def inline_module(name, text):
    """Wraps a ModuleScript source in an IIFE assigned to a local."""
    return "local %s = (function()\n%send)()\n" % (name, text.rstrip("\n") + "\n")


def build_atlas():
    theme = read(SRC / "Atlas" / "Theme.lua")
    utility = read(SRC / "Atlas" / "Utility.lua")
    device = read(SRC / "Atlas" / "Device.lua")
    library = read(SRC / "Atlas" / "Library.lua")
    # Sibling requires are satisfied by the inlined locals above.
    library = library.replace("local Theme = require(script.Parent.Theme)\n", "")
    library = library.replace("local Utility = require(script.Parent.Utility)\n", "")
    library = library.replace("local Device = require(script.Parent.Device)\n", "")
    assert "require(script.Parent" not in library, "unresolved sibling require in Library.lua"
    return (
        ATLAS_HEADER
        + "\n"
        + inline_module("Theme", theme)
        + "\n"
        + inline_module("Utility", utility)
        + "\n"
        + inline_module("Device", device)
        + "\n"
        + library.rstrip("\n")
        + "\n"
    )


def build_complete(atlas_text):
    demo = read(SRC / "StarterPlayerScripts" / "AtlasDemo.client.lua")
    demo = demo.replace(
        'local Atlas = require(ReplicatedStorage:WaitForChild("Atlas"):WaitForChild("Library"))\n',
        "",
    )
    assert "require(" not in demo, "unresolved require in demo"
    # The demo runs in the same chunk as the library, so the library's
    # final "return Library" must go or it would abort before the demo.
    assert atlas_text.endswith("return Library\n"), "unexpected Atlas tail"
    atlas_inner = atlas_text[: -len("return Library\n")].rstrip("\n") + "\n"
    return (
        COMPLETE_HEADER
        + "\n"
        + atlas_inner
        + "\n"
        + DEMO_BANNER
        + "\ndo\n\tlocal Atlas = Library\n\n"
        + demo.rstrip("\n")
        + "\nend\n"
    )


def main():
    OUT.mkdir(exist_ok=True)
    atlas_text = build_atlas()
    complete_text = build_complete(atlas_text)
    (OUT / "Atlas.lua").write_text(atlas_text, encoding="utf-8")
    (OUT / "AtlasComplete.client.lua").write_text(complete_text, encoding="utf-8")
    print("wrote releases/Atlas.lua (%d bytes)" % len(atlas_text.encode("utf-8")))
    print("wrote releases/AtlasComplete.client.lua (%d bytes)" % len(complete_text.encode("utf-8")))


if __name__ == "__main__":
    main()
