# Suggested Development Commands

## Testing
```bash
swift test                    # Run all tests
swift test --filter <name>    # Run specific test
```

## Building
```bash
swift build                   # Build the project
swift build -c release       # Release build
```

## Formatting
```bash
swift-format --in-place --recursive Sources Tests  # Format code
swift-format --lint --recursive Sources Tests      # Check formatting
```

## Package Management
```bash
swift package update         # Update dependencies
swift package clean         # Clean build artifacts
```

## System Commands (Darwin)
```bash
ls -la                      # List files with details
find . -name "*.swift"      # Find Swift files
grep -r "pattern" Sources   # Search in source files
git status                  # Check git status
git diff                    # Show changes
```