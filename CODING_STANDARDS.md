# Oplix Coding Standards

## File Size Guidelines

### Maximum File Size
- **Maximum**: 600 lines of code per file
- **Ideal**: ~400 lines of code per file
- **Target**: Keep files focused and maintainable

### Rationale
- **Readability**: Smaller files are easier to understand and navigate
- **Maintainability**: Easier to locate and fix bugs
- **Collaboration**: Multiple developers can work on different files without conflicts
- **Testing**: Smaller files are easier to test in isolation

### Current Status
As of the latest code review:
- **Largest file**: `LocationDetailView.swift` (576 lines) - ✅ Within limit
- **Average file size**: ~119 lines - ✅ Well within target
- **Total files**: 26 Swift files

### When to Refactor
If a file exceeds 600 lines, consider:

1. **Extract Subviews**
   - Break large views into smaller, reusable components
   - Example: Extract `LocationRow`, `TaskCard`, etc.

2. **Extract ViewModels**
   - Move business logic to separate ViewModel files
   - Keep views focused on UI only

3. **Extract Helper Functions**
   - Move utility functions to separate files
   - Create helper extensions

4. **Split Large Services**
   - Break large service classes into smaller, focused services
   - Example: Split `FirebaseService` by feature (Auth, Locations, Employees, etc.)

### Examples of Good Refactoring

**Before** (Large file):
```swift
// LocationDetailView.swift - 800 lines
struct LocationDetailView: View {
    // All employees, tasks, lottery logic in one file
}
```

**After** (Refactored):
```swift
// LocationDetailView.swift - 200 lines
struct LocationDetailView: View {
    // Main view structure only
}

// EmployeesSection.swift - 150 lines
struct EmployeesSection: View {
    // Employee-specific UI
}

// TasksSection.swift - 150 lines
struct TasksSection: View {
    // Task-specific UI
}

// LotterySection.swift - 150 lines
struct LotterySection: View {
    // Lottery-specific UI
}
```

### Enforcement
- **Code Reviews**: Check file sizes during pull requests
- **Pre-commit**: Consider adding a pre-commit hook to warn about large files
- **Refactoring**: Prioritize refactoring files that exceed 600 lines

### Exceptions
In rare cases, files may exceed 600 lines if:
- The file contains a large but cohesive data structure (e.g., complex model with many computed properties)
- The file is auto-generated code
- Splitting would create more complexity than it solves

**Note**: Always document the reason for exceptions in code comments.

---

## Additional Guidelines

### File Organization
- **One class/struct per file** (when possible)
- **Group related functionality** together
- **Use extensions** to organize code within files

### Naming Conventions
- **Views**: `*View.swift` (e.g., `ManagerDashboardView.swift`)
- **ViewModels**: `*ViewModel.swift` (e.g., `LocationDetailViewModel.swift`)
- **Models**: Singular noun (e.g., `User.swift`, `Location.swift`)
- **Services**: `*Service.swift` (e.g., `FirebaseService.swift`)

### Code Structure
- Keep related code together
- Use MARK comments to organize sections:
  ```swift
  // MARK: - Properties
  // MARK: - Initialization
  // MARK: - Public Methods
  // MARK: - Private Methods
  ```

---

**Last Updated**: 2025-01-17
**Maintained By**: Oplix Development Team

