# YDrive Design & Engineering Guidelines

This document outlines the mandatory UI design and coding standards for YDrive iOS. All AI agents and developers working on this codebase must adhere to these rules for every UI modification.

---

## Core Philosophy

**YDrive's design goal: A clean, minimal, native Apple Human Interface Guidelines-compliant, and professional retro emulator for iOS.**

Never create custom "neon", "cyberpunk", or decorative glowing aesthetics. The app must feel like it was designed and built by Apple.

---

## Permanent Design Principles

1. **Native Apple UI First**
   - Use standard SwiftUI controls and components (`Button`, `List`, `ScrollView`, `Form`, `Section`, `NavigationStack`, `contextMenu`, etc.).
   - Follow Apple Human Interface Guidelines (HIG) strictly.

2. **No Neon or Glow Effects**
   - Never use colored shadow glows (e.g., `.shadow(color: Color.blue.opacity(...))` or `.shadow(color: consoleColor.opacity(...))`).
   - Shadows must only be used for functional elevation and depth using subtle system black/gray tones (e.g., `.shadow(color: Color.black.opacity(0.08...0.15), radius: ..., y: ...)`).

3. **No Decorative Gradients**
   - Do not use `LinearGradient`, `RadialGradient`, or `AngularGradient` for decorative backdrops, ambient glows, buttons, or border strokes.
   - Use standard Apple semantic fills: `Color(UIColor.systemBackground)`, `Color(UIColor.secondarySystemBackground)`, `Color(UIColor.secondarySystemFill)`, etc.

4. **No Fake Liquid Glass**
   - Do not imitate glass using stacked gradient overlays, custom stroke borders, or artificial specular white highlights.
   - When Liquid Glass is appropriate (e.g. on iOS 26+), use Apple's genuine native APIs directly:
     - `.glassEffect(.regular, in: shape)`
     - `.buttonStyle(.glass)`
     - `.buttonStyle(.glassProminent)`
   - Let the system render its own natural optical reflections and refractions without interfering overlays.

5. **Preserve Existing Layout and Dimensions**
   - Do not resize ROM cards, change grid spacing, or alter existing screen layouts unless explicitly requested.
   - Do not arbitrarily enlarge or shrink buttons.
   - Do not invent extra wrapper capsules or unnecessary container views.

6. **Use Semantic System Colors**
   - Use dynamic semantic colors: `.primary`, `.secondary`, `.tertiary`, `Color(UIColor.systemBackground)`, `Color(UIColor.secondarySystemFill)`.
   - Preserve YDrive's standard blue accent color (`Color.accentColor` / `.blue`) for primary actions and active states.
   - Retain console-specific identity colors only where needed for content tagging (e.g. console badges).

7. **Prefer SF Symbols**
   - Always use standard Apple SF Symbols (`Image(systemName: ...)`) for icons with consistent weights (`.regular`, `.semibold`, `.bold`).
   - Never draw custom icons or composite fake symbol shapes with multiple overlapping gradients.

8. **Avoid Unnecessary Visual Complexity**
   - Keep views concise, readable, and performant.
   - Do not add unrequested animations, bouncy transitions, or distracting micro-effects.

9. **Never Redesign Unrelated Screens**
   - Strictly limit modifications to the screens and components specified in the user request.
   - Never touch game controls, the emulator viewport, or unrelated menus when working on a specific screen.
