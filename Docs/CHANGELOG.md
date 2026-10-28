# Changelog

Docs process: every slice ships its user docs with the code. The guide
(`Docs/USER-GUIDE.md`) is cumulative — new slices extend it, never rewrite
history. Each entry below lists what the user can now do.

## 0.2.2 — Published (revamp round)

- Sidebar (Devices/Recent/Favorites/Tags), breadcrumbs + free-space
  subtitle, outline disclosure, title-bar strip removed (pins in sidebar).
- List/Columns/Icons/Gallery per pane; Miller columns rewritten
  (parent | current | children); gallery layout fixed (unused preview
  collapses instead of black slab).
- Columns: Last Opened, Added, direct-children Items; persisted + sortable.
- Drag and drop (move/copy/`⌥`, cross-volume copies, Favorites pin).
  Decision logic unit-tested; gesture is manual-test.
- Unit gate executes every safe command + audits all buttons and header
  menus headless — build fails on dead controls.
- Known issues: Ask Siri is system-injected into the context menu; Remove
  theme button needs one live confirmation run.

## Unreleased (source only — revamp round)

- Back to 2 panes in a plain split (4-pane grid deleted); Swap/Clone Pane.
- Sidebar: Devices, Recent Folders, Favorites (pins moved here from the
  title bar), Tags with Spotlight search.
- Breadcrumbs + free-space subtitle; outline disclosure in list view.
- Title-bar strip (pins + actions) without NSToolbar; flat inline buttons.
- ForkLift menu vocabulary + shortcuts; column header menu (Kind/Created).
- Theme engine: built-ins, add/duplicate/edit/remove, JSON persistence.
- Known issues: About shows 0.2.0 (hard-coded); Ask Siri item is
  system-injected into the context menu; a leftover "Custom" test theme
  may exist — one-click Remove.

## 0.2.1 — Fixes

- Themes Add/Duplicate/Edit/Remove work (dead target bug fixed; engine
  unit-proven: save → select → apply → delete → fallback).
- Flat lean toolbar buttons (icon-only, small) instead of glass pills.

## 0.2.0 — Slice 2: hygiene + UX (Vata rename)

- Renamed to Vata (Vātā in-window), new app icon, `com.vata.app`.
- ForkLift-parity chrome: sidebar (Devices/Recent/Tags), breadcrumbs with
  selection + free-space subtitle, title-bar pins + actions, outline
  disclosure, Siri-proof custom context menu panel.
- ForkLift menu vocabulary + shortcuts (Go locations, as Icons/List/Columns
  `⌘1/2/3`, Select All, Show Invisible Files, Swap/Clone Pane).
- Settings: General / Shortcuts / Themes / Tags / Tools sections; full theme
  engine (built-ins, add/duplicate/edit, swatches, dark style, sidebar colors).
- Per-pane List/Columns/Icons/Gallery views; preview pane slot logic.
- Per-pane List/Columns/Icons/Gallery views; preview pane slot logic.
- Header defaults (Home/Apps/Desktop/Downloads) + drag reorder; Copy
  Path (`⌘⌥C`); archives extract-on-open + Extract Here; column header
  menu (Kind/Created toggles).

## 0.1.0 — Slice 1: app shell + local files

- Install from DMG; first-launch right-click Open.
- Dual-pane window (home | /Applications), independent navigation.
- Path field, back/forward history, double-click to descend or open.
- Name / Size / Modified columns.
