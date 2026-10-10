# Multi-Monitor Workspaces

An [Omarchy](https://omarchy.org) plugin that gives **each monitor its own workspaces 1–9 (and 0)**.

Stock Hyprland has one global set of numbered workspaces. The first time you press `SUPER+1`, workspace 1 is created on whichever monitor has focus, and every later `SUPER+1` jumps there. So the numbers end up scattered across screens (1 and 3 on one, 2 on the other). With this plugin enabled:

- `SUPER` + a number key goes to that workspace **on the monitor you're on**.
- `SUPER+SHIFT` + a number key moves the focused window there, and `SUPER+SHIFT+ALT` + a number key moves it without following.
- `SUPER` + scroll wheel, `SUPER+TAB` and `SUPER+SHIFT+TAB` step through the current monitor's workspaces only (stopping at the first and last, with no wrap-around), and `SUPER+CTRL+TAB` goes back to that monitor's previous one.
- `SUPER+SHIFT+ALT` + arrow sends every window on this workspace to the monitor in that direction. Workspaces themselves stay on their own screen.
- Each screen's bar shows **only that screen's** workspaces, numbered 1–9/0, and marks the one that screen is showing. Left-click focuses a workspace, right-click sends the focused window there, and scrolling steps through them (no wrap-around).
- **Unplug a screen (or undock) and its workspaces move onto the screen you still have, keeping their numbers where they're free**, so `SUPER+1` on the laptop reaches what was on the big screen's 1. Plug it back in (on any port) and they go home, windows and all.
- If [hyprtasking](https://github.com/raybbian/hyprtasking) is installed, its overview grid shows each monitor its own workspaces.

**Keys you bound yourself are never touched.** The plugin loads after your Hyprland config, so before it binds any key it checks your `~/.config/hypr` files, and it skips any key they bind. For example, a `SUPER+TAB` overview of your own stays yours.

Disabling the plugin puts every one of these back to stock Omarchy.

## Settings

Open the Omarchy bar settings and edit **Multi-Monitor Workspaces**, or set them from a terminal:

```bash
omarchy bar set io.github.davidboulay.multi-monitor-workspaces count 5 --json
```

| Setting | Default | What it does |
|---|---|---|
| `count` | 10 | Workspaces per screen, 1–10 (10 is the `0` key). Number keys past this are unbound, so they can't jump to another screen, and workspaces adopted from an unplugged screen are placed within it whenever a slot is free. |
| `extraKeys` | true | The per-screen `TAB` / `CTRL+TAB` / `SHIFT+ALT+arrow` keys above. The number keys and `SUPER` + scroll are always per-screen. |

A change applies within a couple of seconds, with no reload needed on your part.

## Install

```bash
omarchy plugin add https://github.com/davidboulay/omarchy-multi-monitor-workspaces.git --enable
```

Or add it without `--enable` and turn it on from the menu (next section).

Requires Omarchy 4 (Hyprland with the Lua config). Tested on Omarchy 4.0.4 with Hyprland 0.56.2. No extra packages are needed.

## Turn on and off

**Omarchy menu → Setup → Plugins → Enable Plugin / Disable Plugin → Multi-Monitor Workspaces.**

- **Enabling** replaces the stock *Workspaces* bar widget with this plugin's widget, in the same position. The plugin's service then puts a small loader file into Omarchy's Hyprland toggles folder (`~/.local/state/omarchy/toggles/hypr/`, the same folder Omarchy's own *Window Gaps* toggle uses) and reloads Hyprland.
- **Disabling** puts the stock widget back. The Hyprland side notices within about two seconds and reloads to stock.

It never edits your own config files (`~/.config/hypr/*`, your bindings, your monitor setup).

## Remove

```bash
~/.config/omarchy/plugins/io.github.davidboulay.multi-monitor-workspaces/bin/multi-monitor-workspaces remove-loader
omarchy plugin remove io.github.davidboulay.multi-monitor-workspaces
```

The first command deletes the loader file and reloads Hyprland. You can skip it: once the plugin folder is gone the loader does nothing, and deleting it by hand later is always safe. Plugin state lives in `~/.local/state/omarchy/multi-monitor-workspaces/`, which you can delete as well.

## How it works

Every **screen** gets a **block** of real Hyprland workspace ids. Block *B* owns *B*×10+1 … *B*×10+10:

| Block | Real ids | Shown as |
|---|---|---|
| 0 | 1–10 | 1–9, 0 |
| 1 | 11–20 | 1–9, 0 |
| 2 | 21–30 | 1–9, 0 |

- **Blocks belong to the screen, not the port.** A screen is identified by its description (identical panels also get their connector name added), so it keeps its block across unplugging, a different dock port, and reboots. Blocks are remembered in `~/.local/state/omarchy/multi-monitor-workspaces/blocks`.
- **Assignment.** A new screen takes the lowest free block. On the very first run, screens get blocks from left to right, so the leftmost one keeps the plain 1–9.
- **The numbers stay per screen**, so Omarchy's per-workspace layout toggle (`SUPER+L`) and switch animations work as usual.

- **Rules.** Every id is bound to its monitor with a Hyprland workspace rule, so a new workspace always opens on the right screen.
- **Hotplug.** When monitors are added, removed or rearranged, the plugin waits 1.5 s for your monitor setup to apply, then reloads Hyprland if the set of screens changed, so the rules follow.
- **Unplug.** Hyprland moves an unplugged screen's workspaces to a remaining one. The plugin **adopts** each one there: it's renumbered into that screen's block, keeping its number when it's free, and where it came from is recorded in `~/.local/state/omarchy/multi-monitor-workspaces/adopted`. Hover it in the bar to see its origin. When the screen comes back, the workspace is renumbered back and sent home, windows and all. If the returning screen has already opened an empty workspace on that number, the empty one makes way.
- **Stray workspaces** that belong to no known screen (for example, ones created before the plugin was enabled) are renumbered into the block of the screen they're on, keeping their number when it's free.

## Update checks

The plugin checks the system when the shell starts (so after every `omarchy update`) and once a day. It sends **one notification per new problem**:

| Check | Why |
|---|---|
| Omarchy changed `default/hypr/bindings/tiling.lua` | Those are the stock workspace keys this plugin replaces |
| Omarchy changed the stock *Workspaces* bar widget | This plugin's widget is derived from it |
| The Hyprland side failed to load, or is inactive while the plugin is enabled | Otherwise the bar and the keys would disagree |
| Hyprland config errors mention this plugin | |
| The stock *Workspaces* widget is also in the bar | It would show global numbers beside the per-monitor ones |
| The installed hyprtasking build lacks the overview-grid fix | See below |

Run the checks yourself at any time:

```bash
~/.config/omarchy/plugins/io.github.davidboulay.multi-monitor-workspaces/bin/multi-monitor-workspaces status
```

A "changed" warning doesn't mean anything is broken, only that the plugin was tested against the previous version (see `compat.json`).

## hyprtasking (optional)

If you use the hyprtasking overview, builds before [raybbian/hyprtasking#138](https://github.com/raybbian/hyprtasking/pull/138) can place the second monitor's workspaces one tile off after the monitor layout changes, and every tile still *looks* right. The plugin warns when your build doesn't have the fix. Everything else works without hyprtasking.

hyprtasking's default grid is 3×3, so it has no tile for workspace `0`. Set `count` to 9 to match it.

## Dependencies

None beyond Omarchy 4: `hyprctl`, `jq` and `omarchy-notification-send` all ship with it. hyprtasking is optional.

## License

MIT, see [LICENSE](LICENSE). The bar widget is derived from Omarchy's built-in `omarchy.workspaces` widget, which is also MIT licensed.
