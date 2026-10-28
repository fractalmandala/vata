# Vata User Guide — v0.2.2

> Shipped DMGs end at 0.2.2. Unreleased source changes are marked.
> See CHANGELOG for the split.

## What Vata is

Vata (styled **Vātā** in the app) is a dual-pane file browser for macOS.
This release browses files stored on your Mac. Remote servers, transfers,
and sync arrive in later slices.

## Install (0.2.2 DMG — latest published)

1. Open `Vata-0.2.2.dmg`.
2. Drag `Vata.app` onto the `Applications` alias.
3. Eject the disk image.
4. First launch only: right-click `Vata` in Applications and choose
   **Open**, then confirm. (Ad-hoc signature; macOS asks once.)

Requires macOS 14.6 or later, Apple silicon or Intel.

## Panes

- Windows open with two resizable panes (drag dividers; sizes persist).
  Left shows your starting folder, right shows `/Applications`.
- Click any pane to make it active — menus, palette, and shortcuts act on it.
- **Swap Panes** and **Clone Pane** live in View, the palette, and the
  command set. There is deliberately no 3rd/4th pane: parity with
  ForkLift's two-pane model won over our earlier 4-pane grid (removed).

## Sidebar

Devices (mounted volumes), Recent Folders (last 10 navigations),
**Favorites** (your pins), Tags (seven standard colors → Spotlight
search listed in the active pane). Double-click navigates; favorites of
files/apps open them. Right-click a favorite → Remove from Favorites.

## Title-bar strip

Pins plus action buttons (view switcher, refresh, new folder, trash,
info) sit in the title bar next to Vātā. Buttons are flat and small by
design — if macOS renders them as glass pills again, that's a regression:
report it with a screenshot.

## Views (per pane)

Each pane has its own List / Columns / Icons / Gallery switcher (View →
as Icons/List/Columns `⌘1/2/3`, Gallery, or the palette). List view
expands folders inline with disclosure triangles (loaded lazily).
Double-click opens files, extracts archives beside themselves.

## Navigate

| Action | How |
|---|---|
| Open a folder | Double-click it, or click a breadcrumb segment |
| Open a file | Double-click it (opens in its default app) |
| Back / forward / up | `‹` `›` `⌃` buttons, or `⌘[` `⌘]` `⌘↑` |
| Home / Apps / Desktop / Downloads | Go menu, or `⇧⌘H/A/D/L` |
| Command palette | `⇧⌘P`, type, Return |
| Quick Look | Select, press Space (or right-click → Quick Look) |
| Preview pane | Select → View → Preview Pane (`⇧⌘Y`); replaces the inactive pane temporarily, same command closes |

The breadcrumb shows the current path; the subtitle under it reads
"N of M selected, X available" (real free-space stat).

## Columns

Default: **Name**, **Size**, **Modified**. Right-click any column header
for the column menu — toggle **Kind** and **Created**. Click a header to
sort (`⌃⌘1–0` also sorts by column); visible columns and sort persist.
Kind knows folders, aliases, apps, images, music, movies, archives, PDFs,
and text.

## File operations

Right-click (or File/Edit menus, or palette): Open, Open in New Window,
Show Preview, Cut, Copy, **Copy Path** (`⌘⌥C`), **Paste Item** (enabled
only with file URLs on the clipboard), Rename, Duplicate, Make Alias,
**Extract Here** (archives only), Move to Trash, Get Info, Add to Header,
Quick Look, **Quick Actions** submenu.

Note: macOS may prepend an **Ask Siri** item to this menu. It is injected
by the system, not built by Vata; there is currently no app-side removal.

## Settings (Vata → Settings…, `⌘,`)

Sidebar sections, ForkLift-style: **General** (starting directory,
restore windows, hidden files, archives handling, drag confirmation),
**Shortcuts** (searchable list of every command + shortcut, Restore
Defaults), **Themes**, **Tags** (sidebar visibility), **Tools**
(Quick Actions editor: Add/Remove, double-click cells to edit).

## Themes

Built-ins: System, Light, Dark, Vata (dark, orange highlight). Selecting
applies instantly (appearance + selection + sidebar colors). Add creates
an editable copy; Duplicate/Edit open the editor (name, dark-style
toggle, content + sidebar color wells, Save/Cancel); Remove deletes
custom themes only. Customs persist across launches.

Known rough edge: a leftover test theme named **Custom** may exist from
verification runs — remove it in one click (select → Remove). It is
visually identical to Vata.

## Quick Actions

Shell commands with the selected path appended. Ships with Open in
Terminal and Reveal in Finder. Edit in Settings → Tools.

## Speed notes

Listing runs off the main thread with a spinner; huge folders stream in
in 500-row chunks. Budgets enforced every build: cold launch < 1500 ms,
2,000 files < 800 ms, 15,000 files < 4000 ms, zero RSS growth over 200
listings (see `verify-vata` skill; evidence under `verify-evidence/`).

## Current limits

Local files only. No copy/move progress, search, tabs, remote
connections, drag-and-drop between panes, or batch rename — scheduled
slices. linked navigation and full custom accents are next-slice
decisions already made: yes to both.
