# Kong Frame Fader Kontinued

A Retail refresh of Xentaros's Kong / King Kong Frame Fader. This branch
targets Retail 12.1.5 (Interface 120105). Forever compatibility is outside
this branch's scope. Static and mocked runtime checks do not establish
in-game compatibility; Retail gameplay validation is still pending.

The original source archive is [Kong 0.29 on CurseForge](https://www.curseforge.com/wow/addons/kingkongframefader/files/7534093).
The initial repository seed preserves that archive's contents; subsequent
commits contain the refresh. Original author attribution remains intact.

## Installation and commands

Copy the `KongKontinued` and `KongKontinuedConfig` directories into Retail's
`Interface/AddOns` directory. Enable Kong Frame Fader Kontinued at character
selection. Its configuration companion loads on demand. Disable legacy
`Kong` and `KongConfig` before using this addon.

- `/kong` or `/kongkontinued` opens configuration
- `/kong help` lists commands
- `/kong profile` lists profile commands
- `/kong import` opens the legacy import window

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
still loaded, `/kongkontinued import` first offers **Disable and Reload**.
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
