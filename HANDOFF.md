# Vata — Handoff Context

Date: 2026-10-28. App: dual-pane macOS file browser, Swift/AppKit, no Xcode
project (`build.sh` compiles with `swiftc`). Source of truth for behavior:
`Docs/USER-GUIDE.md`. Evidence for RE claims: `ForkLift-RE/*.json|md`.

## Where things stand

- Source is ahead of the last published DMG (`Vata-0.2.1.dmg`, identifies
  as 0.2.0 — version hard-coded in `build.sh`). Source = "0.2.2-dev",
  documented under "Unreleased" in `Docs/CHANGELOG.md`.
- Current source builds clean (`UNIT-GATE-PASS`), launches with 1 window,
  zero console assertions. Budgets pass headless (launch ~1 s, 2k files
  ~250 ms, leak flat).
- Last verified end-to-end by driving the real app over AX (no activation,
  no screenshots): launch, Settings → Themes → Add → editor opens → Save
  closes it. **Remove-button proof did NOT complete** (see blockers).

## Resume queue (in order)

0. **Verify-copy instances**: if `GuppyLift/VataVerify.app` exists from a
   verification run, it is disposable — delete it. Never ship it in a DMG.

1. **Version string**: `build.sh` writes `CFBundleShortVersionString 0.2.0`;
   parameterize per release. About reads from bundle already.
2. **Remove-button proof: STILL OPEN.** Status 2026-10-29: Add+Save proven
   live 3× (editor opens, Custom persists in defaults). Remove itself
   unproven — ~15 attempts died to ENVIRONMENT, not code:
   System Events process resolution is nondeterministic in this machine
   state (`tell process` alternates between working and -1728 for a
   healthy PID; `whose unix id` once matched loginwindow). Suspected
   contributors: rapid launch/quit cycles confusing System Events' cache,
   plus possible user co-testing. The fix that unblocked Add applies
   identically to Remove (same BlockTarget mechanism, same table);
   deleteCustom itself is unit-gated. Cleanest next attempt: fresh boot
   or idle machine, isolated copy via helpers/verify-copy.sh, single
   scripted run, no interleaved launches.
   NOTE 2026-10-29: user's real defaults were cleaned once (Custom
   removed, current back to Vata). Re-check before re-polluting.
3. **DMG**: rebuild `Vata-0.2.2.dmg`, mount-verify, publish.
4. **Known issue — Ask Siri**: system-injected at top of our row context
   menu; tag/strip + manual `popUpContextMenu` both fail (injection lands
   after our hooks). Custom `MenuPanel.swift` was written then deleted.
   Next idea if revisited: find what differs from ForkLift (whose menu is
   clean on the same machine) — presentation path or linked SDK behavior.
5. Next slices (user-approved): linked navigation, full custom accents,
   then remote backends (order TBD), sync engine, privileged helper.

## Decisions the user made (do not relitigate)

- 2 panes, ForkLift parity — the 4-pane grid was built then deleted.
- Pins live in the **sidebar Favorites**, NOT the title bar. The
  title-bar strip (pins + actions) still exists in source but is unwanted;
  remove it when touching that area (user: "header buttons not needed").
- No glass pills: flat `.inline` small buttons. Tahoe wraps NSToolbar
  items in glass — do not go back to NSToolbar for custom controls.
- `.top` titlebar accessories require `.fullSizeContentView` on the
  window or AppKit throws NSInternalInconsistencyException (proven by
  minimal repro in /tmp/tbtest, since cleaned).
- Archives always extract, never browse. No search UI (Spotlight TBD).
- No Vim bindings. Copy Path (`⌘⌥C`) is sacred. Swift/AppKit stays —
  GPUI explicitly rejected for this app (deep macOS integration wins).
- Verification must not take over the screen: no activation, no clicks
  that steal focus, no screenshots by the agent. AX tree reads + `open -g`
  + unit gate are the allowed tools. User sends their own screenshots.

## Traps already hit (do not repeat)

- `NSButton`/`NSMenuItem` hold targets **weakly**: inline `BlockTarget{}`
  deallocs instantly. `BlockTarget` now self-retains (`SettingsWindow.swift`).
  `ThemeEditor` needed the same via static `open[]` — window controllers
  are not retained by their windows.
- Table `reloadData()` inside `tableViewSelectionDidChange` wipes the
  selection → Remove/Edit can never fire. Fixed by reselecting after reload
  (`SettingsWindow.swift` ThemeTable).
- `NSOutlineView` has no `selectedItems`/`expandedItems`; track manually.
  Its `children` collides with `NSViewController.children` — ours is
  `childCache`. `NSBrowserCell.leaf` is now `isLeaf`.
- `NSMetadataItem.userTagsKey/pathKey` don't exist in Swift — use
  `"kMDItemUserTags"` / `"kMDItemPath"` strings.
- `NSWindow.constrainFrameRect(_:to:)` (not `toScreen:`).
- `edit` tool: `edits[]` must be objects, oldText exact, non-overlapping.
- `timeout`/`setsid` don't exist on macOS. `open -g` launches backgrounded.
- AX tables hide inside scroll areas (`tables of splitter` finds nothing;
  walk `tables of scroll areas`). `entire contents` dumps can exceed
  output limits — scope queries tightly.
- `defaults read` races cfprefsd; `defaults export` + plistlib is reliable.
- Never `rm -rf` the user's real `vata.*` defaults keys; test residue is
  removed by UI proof (Remove button), not by hand. (One exception made
  2026-10-29: removed MY OWN "Custom" test theme + restored current=Vata
  via defaults CLI after proving Save twice — documented here, not repeated.)
- Phantom "app quits": twice the app vanished mid-probe with clean
  `terminate:` logs. Cause was the operator, not the app — first my own
  audit clicking the red close button (last-window-closed terminates),
  later the user co-testing live (⌘Q). Rule: exclude window chrome from
  button audits (filter y-offset), and use isolated VataVerify copies.

## Verification setup (must keep honest)

- `build.sh` runs `UnitGate/main.swift` first; build fails if it fails.
  Covers: target retention, theme save/select/apply/delete/fallback,
  command-id integrity, icon-map PNG coverage, pin add/remove.
- Skill: `/Users/amrit/ars-docs/alldocs/90skills/verify-vata/` (budgets,
  harnesses, feature map). UI journeys proven so far: launch, Settings,
  Themes Add + Save. **Remove + Edit unproven.** Proof artifacts:
  `GuppyLift/verify-evidence/<slice>/`.
- Budgets: launch <1500 ms, 2k files <800 ms, 15k <4000 ms, leak ≤5 MB
  over 200 listings (leakcheck only — perf-harness RSS lines include its
  own retained arrays).

## REA deconstruction (reference only, do not rerun lightly)

- Target: `ForkLift.app` 4.7.7 (486), SHA `068bfbea…2c55`.
- `dispatch-evidence.json` (ev_17aabce9…): 353 classes / 879 methods /
  1105 ivars / 51 protocols. `CLASSES.md` is the readable map.
- `ib-graph.json`: full NIB graph (14 docs, 1804 nodes, 898 edges);
  MainMenu titles/shortcuts/SF Symbols mined from it. BLUEPRINT.md +
  RECONSTRUCTION.md summarize.
- Hopper MCP bridge never paired (60 s call cap vs 80 s analysis);
  `rea function` CLI per-address works. MCP session may hold a stale
  Hopper lock — `close_binary` can't clear it without the bridge; killing
  the `rea mcp` node process does (respawns on next call).
