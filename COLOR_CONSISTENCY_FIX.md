# Color Consistency Fix

## Problem
Colors appear different between iOS Simulator and real devices. This is a common issue caused by several factors:

1. **Display Settings**: Real devices may have True Tone, Night Shift, or color filters enabled
2. **Color Space**: Colors might be rendered in different color spaces
3. **Dark Mode**: Device might be in dark mode while simulator is in light mode
4. **System Colors**: Colors like `.blue`, `.green` adapt to appearance mode

## Solution Applied

### 1. Explicit sRGB Color Space
All colors in `Theme.swift` now use explicit sRGB color space:
```swift
Color(.sRGB, red: 0.3, green: 0.7, blue: 1.0, opacity: 1.0)
```

This ensures colors are rendered consistently across all devices regardless of display settings.

### 2. System Color Replacements
Added explicit system color replacements in Theme:
- `Theme.systemBlue` - Replaces `.blue`
- `Theme.systemGreen` - Replaces `.green`
- `Theme.systemRed` - Replaces `.red`
- `Theme.systemOrange` - Replaces `.orange`
- `Theme.systemPurple` - Replaces `.purple`
- `Theme.systemIndigo` - Replaces `.indigo`
- `Theme.systemTeal` - Replaces `.teal`

### 3. Force Light Mode
Added `.preferredColorScheme(.light)` at the app level to ensure consistent appearance.

## Additional Recommendations

### For Users
If colors still look different on real devices, check:
1. **Settings > Display & Brightness**: Disable True Tone and Night Shift
2. **Settings > Accessibility > Display & Text Size > Color Filters**: Disable if enabled
3. **Settings > Display & Brightness > Appearance**: Ensure it's set to Light (though app forces this)

### For Developers
When adding new colors, always use:
```swift
Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
```

Instead of:
```swift
Color(red: r, green: g, blue: b) // May vary by device
```

## Testing
Test on real devices with:
- True Tone ON/OFF
- Night Shift ON/OFF
- Different brightness levels
- Different color filter settings

Colors should now be consistent across all devices.

