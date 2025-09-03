# Task Completion Checklist

## When completing a task, run these commands:

1. **Format the code**:
   ```bash
   swift-format --in-place --recursive Sources Tests
   ```

2. **Check formatting compliance**:
   ```bash
   swift-format --lint --recursive Sources Tests
   ```

3. **Run tests**:
   ```bash
   swift test
   ```

4. **Build the project**:
   ```bash
   swift build
   ```

5. **Check for any warnings or errors**
6. **Verify all public APIs have proper documentation**

## Documentation Standards
- All public types, methods, and properties must have documentation
- Documentation should reference corresponding Beancount concepts where applicable
- Use Swift documentation comments (`///`)
- Include parameter descriptions and return value descriptions
- Add usage examples for complex APIs