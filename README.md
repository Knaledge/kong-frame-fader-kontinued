# Kong Frame Fader Kontinued

Kong Frame Fader Kontinued lets you fade World of Warcraft UI elements
based on conditions you choose. Keep frames out of the way until you need
them, reveal them on mouseover, and customize their opacity and fade timing.

It continues Xentaros's Kong / King Kong Frame Fader, with support for
Retail 12.1.5 and WoW Forever 1.60.1.

## Features

- Select UI frames with an in-game frame picker
- Set fade-in and fade-out opacity, timing and fade-out delay
- Reveal frames on mouseover or when configured conditions are met
- Group frames to coordinate their visibility
- Manage shared profiles through native WoW Options
- Import profiles from legacy Kong without running the old addon

## Installation

Copy the `KongKontinued` and `KongKontinuedConfig` directories into the
chosen client's `Interface/AddOns` directory. Enable Kong Frame Fader
Kontinued at character selection. Its configuration companion loads on
demand. Disable legacy `Kong` and `KongConfig`, if installed, before using
this addon.

## Getting started

Open **Settings > AddOns > Kong Frame Fader Kontinued**, or use `/kong`.
Enable the addon for your character and select or create a profile.

Choose **Advanced Config** to open the frame picker and rule editor.
Select a frame, enable **Hide Selected Frame(s)**, then adjust its fade
settings and **Show When** conditions. Use groups when several frames
should respond together.

The configuration companion loads only when opening Advanced Config or
importing profiles. Native Options provides profile controls without
loading the editor. Configuration changes through Options are unavailable
during combat.

## Commands

- `/kong` or `/kongkontinued` opens native Options
- `/kong help` lists commands
- `/kong profile` lists profile commands
- `/kong import` opens the legacy import window
- `/kong advanced` or `/kongkontinued advanced` opens Advanced Config directly

Key bindings are listed under **Kong Frame Fader Kontinued**. The
configuration binding opens Options. Legacy Kong bindings must be
reassigned to Kontinued.

## Profiles

Profiles contain configured frames, fade settings, conditions and groups.
They are shared across characters; each character chooses its own profile
and enabled state. Switching profiles retains the previous profile's
configuration.

**Add Profile** asks for a new name, creates an empty profile and selects
it. Names are trimmed, lowercased and have whitespace replaced by
underscores. Empty names, control characters, names over 128 bytes and
existing names are rejected. The command `/kong profile create <name>`
uses the same creation path.

**Copy from** lists other profiles. Selecting a source asks for
confirmation naming both profiles before replacing the selected profile's
configuration. The destination keeps its name and this character's enabled
state. The copy is independent of the source, which remains unchanged.
Other characters using the destination profile receive the copied settings.

**Reset Profile** asks for confirmation naming the selected profile, then
permanently clears all of its frames, fade settings, conditions and groups.
The profile keeps its name, and this character's enabled state stays the
same. Profiles are shared across characters, so this also clears the
configuration used by any other characters selecting that profile. Other
profiles and WoW settings are untouched. `/kong reset` and
`/kong profile reset` use the same confirmation.

Cancelling a confirmation leaves the profile unchanged. Pending profile
dialogs close when profiles change, an editor opens or combat begins.

**Import Legacy Profiles** opens the importer described below.

## Importing legacy Kong settings

Import uses pasted SavedVariables data and does not require legacy Kong
to run. Kontinued keeps its settings separate and leaves legacy files
untouched.

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
5. Choose an **Import action**, then click **Preview** to populate the
   incoming-profile selector and review the names and counts
6. For a single-profile action, choose the incoming profile and preview
   again; for rename, also enter the new destination name
7. Click **Import Profiles** or **Replace Profile...**, confirm any
   destructive replacement, then `/reload` to save the new addon data

Import actions:

- **Copy all profiles (preserve existing)** imports every incoming profile without overwriting existing data
- **Import into current profile** replaces its complete configuration under its existing name
- **Rename current profile and import** replaces its configuration under a chosen new name
- **Import selected as separate profile** copies one incoming profile without overwriting existing data

Preview displays the original incoming name and the actual destination
name. Copy-all and separate-profile imports preserve existing profiles;
collisions gain a visible `_imported`, `_imported_2`, etc. suffix. Names
are trimmed, lowercased and use underscores for whitespace. Generated
collision names stay within the 128-byte limit.

For safe copy actions, leave the selection checkbox off to copy only, or
check it to switch this character to the displayed imported selection and
enabled state. Bulk import without a matching character selection can
automatically offer a single imported profile; otherwise choose later in
Options. Current-profile and rename imports always retain this character's
enabled state and require confirmation naming the incoming and destination
profiles. Other profiles are untouched.

Renaming preserves other characters' selections through account-wide
old-name lookup records. When another character loads, it follows the
rename and retains its own enabled state. Old names are reserved against
unrelated profile creation/import, and repeated renames keep the lookup
current. Renaming back to an old name belonging to that same profile is
allowed. The old names are accepted by profile load/delete commands; they
are not duplicate entries in the Options profile list.

Changes to the paste, action, source, destination or relevant profile state
require another preview. Closing the importer or entering combat clears
the paste and dismisses replacement confirmation. All input profiles are
validated before any writes, even when selecting only one to import.

The importer accepts legacy SavedVariables data up to 4 MiB. It supports
Kong 0.29 profiles and older flat character settings, retaining configured
fades, conditions and frame groups. Executable code, unknown condition
types and unsupported settings are rejected.

Import is unavailable in combat; entering combat closes the window and
clears the paste. Closing the window also clears it. Original legacy files
remain untouched. Imported rules can still refer to frames or conditions
that changed between clients or addon versions, so test those rules in
the destination client before relying on them.

## Compatibility

| Client | Version | Interface |
|---|---|---|
| Retail | 12.1.5 | 120105 |
| WoW Forever | 1.60.1 | 16001 |

Available conditions depend on the client. Forever supports mount, Macro
and NPC-interaction conditions, hunter-pet Focus and target-based combo
points. Retail-only power selectors and boss, arena and vehicle conditions
are not exposed on Forever.

When the client restricts a value needed by a condition, that condition
becomes unavailable and keeps the frame visible. Protected frames and
minimap artwork can behave differently from ordinary UI elements; check
the frames you configure during normal gameplay, including combat.

## Credits

Based on Xentaros's
[Kong / King Kong Frame Fader 0.29](https://www.curseforge.com/wow/addons/kingkongframefader/files/7534093).
Original author attribution is retained in the source.
