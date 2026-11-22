# KeyDeck Design System (iOS Anti-Slop Standard)

Grounded in **Impeccable (`ios.md` + `polish`)**, **Anti-Slop Design**, and **Apple Human Interface Guidelines (HIG)**.

## The iOS Slop Test
> *"Would a fluent iPhone user trust this immediately, or pause at off-spec controls that feel ported from a generic AI web template?"*

## Hard Rules (Banned AI Slop Patterns)
1. **No giant indigo/purple filled SaaS cards or unmotivated gradients.** Use semantic iOS surfaces (`systemBackground`, `secondarySystemGroupedBackground`, adaptive keycap fills) and restrain accent color to a single purposeful tint on active controls/icons.
2. **No web-style "card-in-card" stacks in the companion app.** Use native SwiftUI `List` with `.insetGrouped` style, real `Section` headers/footers, and standard `NavigationStack` large titles.
3. **No dead-eyed `.buttonStyle(.plain)` controls.** Every keyboard key uses `KeycapButtonStyle` (physical press-down scale, subtle spring physics, 1pt tactile key lip shadow, and matched haptic feedback).
4. **No duplicate controls.** Never show two identical Undo or status buttons stacked on top of each other.
5. **No hardcoded font pixel sizes or random hex codes.** Use Dynamic Type text styles (`.headline`, `.subheadline`, `.caption`, `.footnote`) and semantic system colors so Light Mode and Dark Mode are both first-class.
6. **Respect 4pt/8pt spacing rhythm and generous touch targets.** Every interactive target must be comfortable for thumb use (`>= 40–44pt` height in keyboard, `>= 44pt` in app).
7. **Eliminate marketing/tutorial clutter on repeat-use controls.** Show live state (`Ready`, `Selection ready`, `Listening`, `Processing`) instead of static onboarding taglines on primary keys.
8. **Respect user privacy & hardware control.** Mic state must always be explicit and killable in one tap from the keyboard without bouncing to the companion app.
