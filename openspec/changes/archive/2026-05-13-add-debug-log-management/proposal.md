## Why

The app currently mixes `Logger` and `print` for diagnostics, but does not provide an app-owned debug logging system that users can inspect in production. Existing logs are visible in Xcode during development, yet there is no persistent, queryable, exportable log surface inside the app.

This creates three problems:

- Production issues are hard to diagnose because logs are not retained in an app-controlled store.
- Sensitive payloads can leak into console output because some code still prints raw responses.
- A future Settings-based debug UI cannot reliably support query, filter, clear, or export if its only source is unified logging.

## What Changes

- Add a unified debug logging architecture that writes each app event to both `os.Logger` and an app-owned persistent log store.
- Define a retention and rotation policy for the persistent log store so old logs are automatically evicted.
- Add a Debug tab in Settings that lets users query, filter, clear, and export persistent logs.
- Replace high-risk `print`-style diagnostics in app code with structured debug logging and redaction rules.

## Capabilities

### New Capabilities
- `debug-log-management`: Capture, retain, query, clear, and export app debug logs across development and production environments.

### Modified Capabilities
- `settings-management`: Add a Debug tab to Settings for log inspection and management.

## Impact

- `SettingsView.swift`: Add Debug tab and log management UI.
- Logging-related services: Introduce a shared debug logging facade and persistent sink.
- Existing services using `Logger` or `print`: Migrate selected diagnostics to the unified logging path.
- Tests: Add unit and UI coverage for retention, filtering, clearing, and export flows.
