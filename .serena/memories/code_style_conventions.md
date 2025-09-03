# Code Style and Conventions

## Swift Formatting
- **Line Length**: 100 characters
- **Indentation**: 4 spaces
- **Tab Width**: 4 spaces
- **Maximum Blank Lines**: 1
- **Respects Existing Line Breaks**: true

## Naming Conventions
- Public APIs use clear, descriptive names
- Structs and classes use PascalCase
- Properties and methods use camelCase
- Public properties and methods are marked `public`
- Sendable conformance for thread-safe types

## Documentation Style
- Currently minimal documentation
- Need to add comprehensive documentation for all public APIs
- Should reference corresponding Beancount Python concepts

## Code Organization
- Core data structures in `Core/` directory
- Functional separation by domain (Loading, Plugins, Utils)
- Test files mirror source structure with `Tests` suffix