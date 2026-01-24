---
name: simplify
description: Systematically refactor a file to make it more idiomatic, readable, and maintainable
disable-model-invocation: true
---

Systematically refactor and simplify a source file.

## Phase 1: Analysis

1. Read the target file specified by the user
2. List all functions with line numbers
3. Identify refactoring opportunities

## Phase 2: Identify Patterns

### Idiomatic Patterns

- Replace verbose constructs with language idioms
- Use built-in functions instead of manual loops
- Simplify boolean expressions
- Inline temporary variables when clear

### Code Duplication

- Repeated code blocks (2+ places) → extract helper
- Similar conditional branches → share code
- Repeated constants → named constants

### Simplification

- Early returns/guard clauses to reduce nesting
- Remove dead code
- Consolidate error handling
- Chain related operations where natural

## Phase 3: Refactor Systematically

For each function:

1. Analyze: what does it do? repeated patterns?
2. Apply: low-risk first, one logical change at a time
3. Test after each change — revert if tests fail

## Phase 4: Extract Helpers (if warranted)

Only extract if:

- Identical logic, clear purpose, used 2+ times
- Abstraction doesn't make code harder to understand

## Phase 5: Finalize

1. Run formatter
2. Run all tests
3. Suggest logical commit boundaries
4. Ask user before committing

## Rules

- Preserve behavior — never change semantics
- Test frequently
- Don't over-abstract
- Don't sacrifice clarity for brevity
- If code is already clear, leave it alone

Target: $ARGUMENTS
