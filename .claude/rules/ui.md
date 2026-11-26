---
paths:
  - "**/*.swift"
---

# UI rules

- The notch is always black (#000000) in light and dark mode. Use the tokens in `docs/spec.md` (Visual tokens); no other colors without updating that table.
- SF Pro (system font) only. Collapsed text 13/600, titles 26/700, countdown 44/600. Numbers that change use `.monospacedDigit()`.
- Spacing in steps of 4; notch corner radius 14 collapsed, 22 peek, 28 expanded.
- Text contrast on black: primary #FFFFFF, secondary #A1A1A6, muted #8E8E93. Nothing darker for text (WCAG AA).
- Color never carries meaning alone: rings and bars always show a % or label.
- Every live activity, ring and bar has an accessibility label and value; peeks post a VoiceOver announcement.
- Keyboard: the hotkey moves focus into the panel, Tab/arrows reach every control, Esc closes and restores focus. Visible focus ring.
- Click targets at least 28 pt (pointer UI); icon-only buttons get an accessibility label.
- Respect Reduce Motion (cross-fade, no pulses) and Increase Contrast (thicker strokes, borders).
- Compare screenshots against `refs/` and the design canvas before calling UI done.
