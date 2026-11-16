# Kong Frame Fader Kontinued

A Retail refresh of Xentaros's Kong / King Kong Frame Fader. This branch
targets Retail 12.1.5 (Interface 120105). Forever compatibility is outside
this branch's scope. On Retail 12.1.5, opening configuration and importing
legacy settings have been user-confirmed working without errors through
KI-5 R20. Static and mocked runtime checks cover additional failure paths;
broader in-game behavior remains to be validated.

The original source archive is [Kong 0.29 on CurseForge](https://www.curseforge.com/wow/addons/kingkongframefader/files/7534093).
The initial repository seed preserves that archive's contents; subsequent
commits contain the refresh. Original author attribution remains intact.

## Installation and commands

Copy the `KongKontinued` and `KongKontinuedConfig` directories into Retail's
`Interface/AddOns` directory. Enable Kong Frame Fader Kontinued at character
selection. Its configuration companion loads on demand. Disable legacy
`Kong` and `KongConfig` before using this addon.

- `/kong` or `/kongkontinued` opens native Options
- `/kong help` lists commands
- `/kong profile` lists profile commands
- `/kong import` opens the legacy import window
- `/kong advanced` or `/kongkontinued advanced` opens Advanced Config directly

Native Options is also available under Settings > AddOns > Kong Frame
Fader Kontinued. It provides a character-specific enable checkbox and
current-profile selector. Profile switching retains the previous profile's
configured frames, conditions and groups. Blizzard's shared Defaults
button is hidden for this category, and its default-setting operations do
not change Kong's controls.

**Reset Profile** asks for confirmation naming the selected profile, then
permanently clears all of its frames, fade settings, conditions and groups.
The profile keeps its name, and this character's enabled state stays the
same. Profiles are shared across characters, so this also clears the
configuration used by any other characters selecting that profile. Other
profiles and WoW settings are untouched. Cancelling changes nothing.
`/kong reset` and `/kong profile reset` use the same confirmation. A reset
is rejected if combat begins or the selected profile changes before
confirmation.

**Import Legacy Profiles** opens the existing previewed paste importer.
**Advanced Config** opens the existing frame picker and rule editor.
Options closes before either window opens. The configuration companion
and its AceGUI controls load only when importing or opening Advanced
Config; native Options works without that companion. Configuration
changes through Options are unavailable during combat. The configuration
key binding now opens Options and retains its existing action ID.

KI-6 R01 adds the Options foundation. Import destination/name controls and
preset checkboxes are planned for subsequent revisions. The new Options
workflow still requires in-game validation.

Account-wide profiles use `KongKontinued_Profiles`; character selection and
enabled state use `KongKontinued_Settings`. Both are declared only by the
new main addon. Legacy `Kong_Profiles` and `Kong_Settings` are neither loaded
nor written by Kontinued. Key bindings appear under Kong Frame Fader
Kontinued. Legacy Kong assignments use different action IDs and must be
reassigned there; Kontinued does not automatically rewrite saved bindings.

## Importing legacy Kong settings

The game cannot read arbitrary files through an addon. Import therefore
uses pasted SavedVariables data and does not require legacy Kong to run.

If the known `Kong` or `KongConfig` addons are enabled for any character or
still loaded, opening configuration or `/kongkontinued import` first offers
**Disable and Reload**.
Accepting disables those installed addon IDs for all characters, saves the
enablement changes and reloads the UI. Cancelling changes nothing. Reopen
the importer after reloading, then paste your data. Import is blocked until
neither legacy addon is enabled or loaded; disabling alone does not unload
code from the current session. The action is unavailable in combat and
does not delete addon folders or legacy settings. Renamed forks with other
addon IDs must be disabled manually.

1. Keep a backup of the legacy SavedVariables files
2. Open the account-wide `WTF/Account/<account>/SavedVariables/Kong.lua`
   in a text editor and copy its contents, including `Kong_Profiles = ...`
3. In game, use `/kong import` and paste into the input box
4. Optionally append the contents of that character's
   `WTF/Account/<account>/<realm>/<character>/SavedVariables/Kong.lua`
   containing `Kong_Settings = ...` to retain its profile selection and
   enabled state
5. Click **Preview** and review the profile names and counts
6. Leave the selection checkbox off to copy profiles only, or check it to
   switch this character to the displayed imported profile
7. Click **Import Profiles**, then `/reload` to save the new addon data

Existing Kontinued profiles are preserved. Name collisions gain an
`_imported`, `_imported_2`, etc. suffix. Profile names are lowercased and
whitespace becomes underscores to match profile commands. Without a
matching character selection, a single imported profile can be selected;
multiple profiles can be selected later with `/kong profile load <name>`.

The importer accepts literal Lua SavedVariables data up to 4 MiB, validates
all profiles before copying, and rejects executable expressions, unknown
condition types and unsupported settings. It supports the Kong 0.29
profile structure and older flat character settings containing `Frames`.
It retains configured fades, conditions and frame groups, while dropping
runtime caches and resetting hover counts. Saved frame paths support
global/table fields and `:GetParent()` traversal without compiling Lua.

Import is unavailable in combat; entering combat closes the window and
clears the paste. Closing the window also clears it. Original legacy files
remain untouched. Imported rules can still refer to frames or conditions
that changed between clients or addon versions, so test those rules in
Retail before relying on them.
