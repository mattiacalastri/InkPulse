# Contributing to InkPulse

Thanks for your interest in contributing to InkPulse! This guide covers everything you need to get started.

## Prerequisites

- macOS 14.0 Sonoma or later
- Swift 5.9+ (included with Xcode 15+)
- Git

## Building

```bash
swift build
```

## Running Tests

```bash
swift test
```

All tests must pass before submitting a pull request.

## Architecture Overview

InkPulse follows a pipeline architecture:

```
Parser -> Metrics -> Engine -> UI
```

- **Parser** (`JSONLParser`) -- Reads Claude Code JSONL session files and produces typed `ClaudeEvent` values.
- **Metrics** (`MetricsEngine`) -- Computes 8 health metrics using sliding windows over parsed events.
- **Engine** (`SessionWatcher`, `FileTailer`) -- Polls the filesystem for new JSONL data and feeds it through the pipeline.
- **UI** (`TabbedDashboard`, `LiveTab`, `TrendsTab`, `ReportsTab`) -- SwiftUI views rendering real-time data in a macOS menu bar popover.

When adding a new metric or anomaly pattern, work through each layer in order: parse the raw data, compute the metric, then surface it in the UI.

## Making Changes

### Fork and PR Workflow

1. **Fork** the repository on GitHub and clone your fork locally.
2. **Create a branch** from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```
3. Make your changes, ensuring tests pass (`swift test`).
4. **Commit** with a clear message following the existing convention:
   ```
   feat: description of new feature
   fix: description of bug fix
   refactor: description of refactor
   docs: description of documentation change
   test: description of test change
   chore: description of maintenance task
   ```
5. **Push** your branch and open a Pull Request against `main`.

## Code Style

- Follow standard Swift conventions and the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- No force unwraps (`!`) in production code -- use `guard let`, `if let`, or `??` with a default.
- No force casts (`as!`) -- use `as?` with proper handling.
- Keep files focused -- one primary type per file.
- Use meaningful names; avoid abbreviations except well-known ones (e.g., `URL`, `JSON`).

## Reporting Issues

Use [GitHub Issues](https://github.com/mattiacalastri/InkPulse/issues) to report bugs or request features. Please check existing issues before creating a new one.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
