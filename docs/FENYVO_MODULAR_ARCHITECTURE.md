# FENYVO Modular Architecture

Status: Migration planned; existing code remains active.

## Goals
- Modular Flutter architecture.
- Clear feature ownership.
- Stable Android and Windows builds.
- Explicit dependencies between modules.
- Testable presentation and business logic.
- No behavior changes during structural migration.

## Module boundaries

app/
Application bootstrap, routing and dependency composition.

core/
Shared infrastructure and platform integrations.

features/
Independently organized product capabilities.

shared/
Reusable visual components, localization and utilities.

## Dependency rules

1. Presentation code must not implement network protocols.
2. Domain logic must not depend on Flutter widgets.
3. Feature modules access infrastructure through explicit interfaces.
4. Shared modules must not import feature-specific implementation.
5. Cross-feature dependencies must be deliberate and documented.
6. No circular dependencies.
7. Existing behavior must be preserved during migration.

## Migration rules

1. Preserve the existing working implementation.
2. Move one complete responsibility at a time.
3. Create a backup before modifying source files.
4. Keep release signing and update compatibility unchanged.
5. Run Dart analysis and appropriate tests after migration.
6. Build Android and Windows before accepting major changes.
7. Do not delete legacy code before verifying replacement.
8. Do not refactor E2EE in this migration phase.
9. Do not modify production server behavior.
10. Do not expose credentials or recovery secrets.

## Migration order

1. Architecture skeleton and dependency map.
2. Message presentation components.
3. Chat state and message orchestration.
4. Media presentation and media services.
5. Calls and group calls.
6. Contact and profile features.
7. Update and notification features.
8. Shared infrastructure consolidation.
9. Security refactoring only with separate approval.

## Release policy

Passing flutter analyze does not prove runtime compatibility.
Functional tests and platform builds remain required.