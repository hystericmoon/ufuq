# Motion: the black jelly

Owner, 27 Nov 2026: Ufuq should be very interactive with smooth animation and behave like a black blob of jelly. This file is the source of truth for every animation in the Mac app; the Android and Windows islands follow it where their toolkits allow.

## Principles

1. **One body.** Collapsed wings, peek, open panel, HUD capsule, floating tray and the drag "neck" are all the same black mass. Shapes morph; they never swap or pop. Only the content inside cross-fades.
2. **Hangs from the top edge.** The top edge is attached to the hardware notch and never moves. Only the sides and bottom deform, like a drop hanging from a ceiling. At rest the body always covers the camera housing exactly. Bulges go outward, never inward.
3. **Springs with overshoot.** Every size or position change is a spring that overshoots a little and settles. The overshoot is what reads as jelly. Bigger moves feel heavier (longer response).
4. **Squash and stretch.** When it widens it first gets a little shorter, then the height catches up (height lags width by 40 ms), so the area stays roughly constant.
5. **Budding.** Secondary bodies (HUD capsule, peek bubble, floating tray, drag neck) are born from the main body and reabsorbed into it with a gooey neck (metaball), never faded in on their own.
6. **Reacts to touch.** It leans toward the pointer, squashes when pressed, stretches when pulled, and swallows dropped files.
7. **Content follows the shape.** Content fades in once the shape is about 60% of the way there (delay 80 ms) and fades out before the shape closes. Text never scales or stretches; only the black body deforms.
8. **Still at rest.** No idle wobble or breathing. Motion always answers something: the user, an alert, a state change.

## Spring tokens

SwiftUI `.spring(response:dampingFraction:)`. Web/Compose equivalent with mass 1: stiffness = (2π / response)², damping = 4π · ζ / response.

| Token | response (s) | damping ζ | Used for |
|---|---|---|---|
| `jelly.touch` | 0.28 | 0.55 | Hover lean, press squash, release |
| `jelly.morph` | 0.42 | 0.62 | Collapsed ↔ peek, wing width when activities rotate |
| `jelly.open` | 0.50 | 0.68 | Collapsed → open panel (height starts 40 ms after width) |
| `jelly.close` | 0.36 | 0.80 | Any close: snappier, almost no wobble |
| `jelly.bud` | 0.45 | 0.50 | A secondary body budding off or being reabsorbed |
| `content.in` | ease-out 0.16 s, delay 0.08 s | | Content appearing |
| `content.out` | ease-in 0.10 s | | Content leaving |

Overshoot ceiling: no dimension overshoots more than 8% or 10 pt, whichever is smaller. If a value is tuned past that, raise ζ.

## Interactions

Every pointer gesture has a keyboard or VoiceOver path (CLAUDE.md: the hotkey always opens the panel).

| Input | Body response | Keyboard / VoiceOver path |
|---|---|---|
| Pointer enters the notch area | Swells 3% wider and leans up to 6 pt toward the pointer's x (`jelly.touch`); opens after 0.3 s if "open on hover" is on | Hotkey opens |
| Press | Squashes to 96% width and 92% height, then springs open on release | Return on focus |
| Two-finger pull down over the notch | Stretches downward with rubber-band resistance (offset = d · 0.55, capped at 60 pt); past 40 pt it opens on release | Hotkey |
| Swipe up / scroll up in the open panel | Contracts with the gesture; past 40 pt it closes | Esc |
| Horizontal swipe on the collapsed body | Leans in the swipe direction (skew up to 4°), then: next track when media plays, otherwise the next right-wing activity | Media keys; ←→ on the focused tile |
| File drag within 160 pt of the top edge | A neck reaches down toward the pointer (budding); within 60 pt it opens into the tray drop zone | "Add to Ufuq Tray" Services menu item; ⌥⇧T opens the tray |
| Shaking a drag anywhere (3 direction changes within 0.5 s) | A floating tray buds off a small drop at the pointer | Same as above |
| Dropping a file on the tray | The tray swallows it: a 6% bulge, then it settles | VoiceOver announces "Added <name> to tray" |
| Peek alert (80/95%, needs input, CI failed) | Buds a peek bubble; critical alerts jiggle once (±3 pt, `jelly.touch`), never in a loop | VoiceOver announcement (existing) |
| Volume, brightness or backlight key (Phase 7b) | A capsule buds from the bottom of the body and its level fills with a spring | VoiceOver announces the value |
| Right-wing activity rotates (8 s) | The wing width morphs (`jelly.morph`); the text cross-fades | n/a |

## Rendering

- **Crisp at rest.** The resting shape is a plain `Shape` path (notch radii from `.claude/rules/ui.md`: 14 / 22 / 28) so corners stay exact.
- **Goo only while budding.** During a bud or reabsorb, draw the bodies in a SwiftUI `Canvas` with `.alphaThreshold(min: 0.5, color: .black)` over a blur of radius 8–12, then switch back to the crisp path when the spring settles.
- **Squash.** `JellyShape: Shape, Animatable` animates width and height as separate animatable values driven by springs; the 40 ms lag gives squash and stretch for free.
- **Frame budget.** 120 Hz on ProMotion. Keep the goo pass under 2 ms per frame (check in Instruments → Animation Hitches). Use `drawingGroup()` only around the Canvas.
- **Low Power Mode.** Keep the springs, drop the goo (buds slide out of the body instead).

## Accessibility

- **Reduce Motion:** every spring becomes a 0.2 s cross-fade. No lean, squash, goo or jiggle. Sizes snap after the fade.
- **Reduce Transparency / Increase Contrast:** unchanged here (the body is solid black); borders per `ui.md`.
- **Motion is never information.** Every jiggle or bud pairs with text, and with an announcement for VoiceOver.
- **No vestibular triggers.** No full-screen motion, no parallax, no movement larger than the panel itself.

## Open questions (tune on the prototype)

- The ζ values above are a starting point. The owner tunes them in the HTML prototype and the chosen numbers are copied back into this table.
