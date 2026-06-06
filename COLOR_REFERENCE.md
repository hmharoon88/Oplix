# Color Reference - Oplix App

## Theme Colors (Defined in Theme.swift)

### Primary Colors
- **`Theme.cloudBlue`**: `Color(red: 0.3, green: 0.7, blue: 1.0)` - Primary action color, buttons, navigation titles
- **`Theme.sunshineYellow`**: `Color(red: 1.0, green: 0.85, blue: 0.3)` - Secondary action color, employee button
- **`Theme.skyBlue`**: `Color(red: 0.5, green: 0.8, blue: 1.0)` - Gradient accent
- **`Theme.softGray`**: `Color(red: 0.9, green: 0.9, blue: 0.92)` - Background accents
- **`Theme.cloudWhite`**: `Color.white` - Card backgrounds, white elements
- **`Theme.darkGray`**: `Color(red: 0.4, green: 0.4, blue: 0.4)` - High contrast dark gray for text

### Gradients
- **`Theme.primaryGradient`**: `[skyBlue, cloudBlue]` - Primary gradient
- **`Theme.secondaryGradient`**: `[cloudWhite, softGray]` - Secondary gradient (background)

## System Colors

### Standard System Colors
- **`.black`**: Primary text, titles, headers
- **`.white`**: Text on colored backgrounds, icons
- **`.gray`**: Disabled states, borders (with opacity)
- **`.secondary`**: Secondary text (replaced with `Theme.darkGray` in most places)

### Semantic System Colors
- **`.blue`**: System blue (used in various UI elements)
- **`.green`**: Success states, completed tasks, clocked-in status
- **`.red`**: Error states, delete actions, expired documents
- **`.orange`**: Warnings, expiring documents, lottery forms
- **`.purple`**: Supervisor role, supervisor controls
- **`.indigo`**: Document icons, some UI accents
- **`.teal`**: Manage tasks card, some UI elements
- **`.yellow`**: New row highlights in game database

## Custom RGB Colors

### Authentication Screens (Dark Blue Gradient)
- **Dark Blue**: `Color(red: 0.1, green: 0.3, blue: 0.6)` - Used in:
  - Role selection screen background
  - Manager login/signup backgrounds
  - Employee login background
  - Supervisor login/signup backgrounds
  - Manager dashboard backgrounds
  - Various manager screens

- **Medium Dark Blue**: `Color(red: 0.15, green: 0.4, blue: 0.7)` - Gradient end color

### Tab Bar Colors (Manager Dashboard)
- **Tab Bar Background**: `UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)`
- **Selected Tab Icon/Text**: `UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)` - Gold/Yellow

### Other Custom Colors
- **Light Blue Background**: `Color(red: 0.95, green: 0.95, blue: 1.0)` - Used in lottery forms
- **Light Gray Background**: `Color(red: 0.9, green: 0.9, blue: 0.95)` - Used in lottery customization

## Color Usage by Context

### Text Colors
- **Primary Text**: `.black` or `Theme.darkGray`
- **Secondary Text**: `Theme.darkGray` (replaced `.secondary`)
- **Navigation Titles**: `Theme.cloudBlue` (in supervisor controls)
- **Location Names**: `Theme.cloudBlue`
- **Icons on Colored Backgrounds**: `.white`
- **Completed/Active States**: `.green`
- **Error/Expired States**: `.red`
- **Warning/Expiring States**: `.orange`

### Background Colors
- **Main Backgrounds**: `Theme.secondaryGradient` (white to soft gray)
- **Card Backgrounds**: `Theme.cloudWhite`
- **Authentication Screens**: Dark blue gradient `[Color(red: 0.1, green: 0.3, blue: 0.6), Color(red: 0.15, green: 0.4, blue: 0.7)]`
- **Tab Bar**: `UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0)`

### Button Colors
- **Primary Buttons**: `Theme.cloudBlue`
- **Employee Button**: `Theme.sunshineYellow`
- **Supervisor Button**: `Color.purple`
- **Owner Button**: `Theme.cloudBlue`
- **Success Actions**: `.green`
- **Destructive Actions**: `.red`

### Status Colors
- **Clocked In**: `Color.green.opacity(0.2)` background, `.green` text
- **Clocked Out**: `Theme.darkGray.opacity(0.2)` background
- **Task Completed**: `.green`
- **Task Incomplete**: `Theme.darkGray`
- **Document Expired**: `.red`
- **Document Expiring Soon**: `.orange`

### Card/Icon Colors (Supervisor Controls)
- **View Employee Schedules**: `.blue`
- **View Tasks**: `.green`
- **Edit Employee Schedules**: `.indigo`
- **Manage Tasks**: `.teal`
- **Manage Documents**: `.orange`

### Shadow Colors
- **Card Shadows**: `Color.black.opacity(0.05)` to `Color.black.opacity(0.1)`
- **Button Shadows**: `backgroundColor.opacity(0.3)`

## Color Opacity Variations

Common opacity values used:
- **0.1**: Very light backgrounds, subtle highlights
- **0.2**: Light backgrounds, semi-transparent overlays
- **0.3**: Medium transparency, shadows
- **0.5**: Borders, dividers
- **0.6-0.7**: Placeholder text
- **0.8**: Semi-opaque backgrounds
- **0.9**: Almost opaque text

## Notes

- Most `.secondary` colors have been replaced with `Theme.darkGray` for better visibility
- Navigation titles in supervisor controls use `Theme.cloudBlue`
- The app uses a consistent dark blue theme for authentication and manager screens
- Tab bar uses gold/yellow for selected state to contrast with dark blue background
- All shadows use black with low opacity (0.05-0.1) for subtle depth

