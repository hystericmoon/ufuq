# Progress

Last updated: 2026-11-26

## Next up

**Phase 1 — Notch shell** (see `docs/plan.md`). Run on the Mac.

First prompt to type:

```
Start Phase 1 from docs/plan.md. Read CLAUDE.md, docs/spec.md (Notch states, Architecture, Accessibility) and .claude/rules/ui.md first.
Create the Xcode project "Ufuq" (SwiftUI app, macOS 14+, not sandboxed, bundle ID app.ufuq.mac, LSUIElement so there is no Dock icon).
Build NotchController (NSPanel above the menu bar, sized from NSScreen.safeAreaInsets / auxiliaryTopLeftArea), the collapsed/peek/expanded states with a morph animation and Reduce Motion cross-fade, a global ⌥Space hotkey that moves focus into the panel and Esc that returns it, the floating pill for displays without a notch, the UfuqModule protocol + ModuleRegistry, and stub Prayer and AI modules that render in the left and right wings.
Fill in the Commands section of CLAUDE.md once the build works. Stop when the plan's "done when" for Phase 1 is met.
```

## History

- 2026-11-26: Kickoff. Features, mockups ([design canvas](https://claude.ai/artifact/4HsAKmFv7udUHpofxCsYpi)) and [product spec](https://claude.ai/artifact/TaMXyaqrAM7SMdM7UnRyio) done; name chosen (Ufuq); repo scaffolded with CLAUDE.md, docs, UI rules and start-up hook.
