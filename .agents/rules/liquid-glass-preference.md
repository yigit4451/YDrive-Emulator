# Native Liquid Glass Preference

**Context**: The user prefers strict adherence to Apple's native system rendering for "Liquid Glass" effects in the SwiftUI iOS application (`YDrive.iOS.Native`), rather than custom blur modifiers.

**Rule**:
When the user asks to "add Liquid Glass" (or "Lquid Glass ekle") to a button or a set of UI controls:
1. **DO NOT** use `.background(.ultraThinMaterial)`, `.thinMaterial`, `UIBlurEffect`, or fake dark/opacity-based circles (e.g., `Circle().fill(...)`).
2. **DO NOT** write custom modifiers like `applyLiquidGlass()`.
3. **DO** use the native iOS `.toolbar` mechanism. Wrap the view hierarchy in a `NavigationStack` (if it isn't already) and place the actions inside `.toolbar { ToolbarItem(...) }` or `ToolbarItemGroup`. 
4. This allows the iOS system `NavigationBar` to naturally render the organic Apple Liquid Glass background layer underneath the buttons without manual manipulation.
