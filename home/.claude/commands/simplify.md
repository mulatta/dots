---
description: Systematically refactor a file to make it more idiomatic, readable, and maintainable
---

You are going to systematically refactor and simplify a source file. Follow this
methodology:

## Phase 1: Analysis & Planning

1. **Read the target file** specified by the user (they will provide the path)

2. **List all functions** in the file and create a todo list with:
   - Each function/method name and line numbers
   - Status: pending/in_progress/completed
   - Use TodoWrite tool to track progress

3. **Create REFACTOR-TODO.md** in the project root with:
   - Section: "Code Duplication and Sharing Opportunities"
   - Section: "Completed Simplifications"
   - Section: "Remaining Complex Functions"

## Phase 2: Identify Patterns

Look for these common refactoring opportunities:

### A. Idiomatic Patterns (language-specific)

- Replace verbose constructs with language idioms
- Use built-in functions/methods instead of manual loops
- Apply standard library patterns where appropriate
- Use pattern matching or conditional expressions effectively
- Simplify boolean expressions
- Inline temporary variables when clear

### B. Code Duplication

- **Repeated code blocks**: Extract into helper functions
  - Look for identical or near-identical code in 2+ places
  - Examples: parsing loops, validation logic, data transformation
- **State management patterns**: Use consistent helper methods
- **Similar conditional branches**: Look for patterns that can share code
- **Repeated constant values**: Extract to named constants

### C. Simplification Opportunities

- **Early returns/guard clauses**: Reduce nesting depth
- **Simplify boolean logic**: Remove redundant conditions
- **Reduce temporary variables**: Inline when it doesn't hurt clarity
- **Combine related operations**: Chain operations where natural
- **Remove dead code**: Eliminate unused variables/functions
- **Consolidate error handling**: Use consistent patterns

## Phase 3: Refactor Systematically

For each function (mark as in_progress in todo list):

1. **Analyze the function**:
   - What does it do?
   - Are there repeated patterns within or across functions?
   - Can it be simplified without losing clarity?

2. **Apply improvements**:
   - Start with low-risk changes (formatting, boolean simplification)
   - Extract helpers for duplicated code (only if used 2+ times)
   - Make one logical change at a time

3. **Test after each change**:
   - Run the project's test suite
   - Build/compile to catch errors
   - If tests fail, revert and try a different approach
   - Mark function as completed in todo list when done

4. **Document in REFACTOR-TODO.md**:
   - What pattern was found (with line numbers)
   - What change was made
   - Impact (lines saved, clarity improvement)

## Phase 4: Extract Helpers (if warranted)

When you find the same code pattern 2+ times:

1. **Evaluate if extraction is worth it**:
   - DO extract if: Identical logic, clear purpose, used 2+ times
   - DON'T extract if: Each usage has different edge cases or
     context-specific logic
   - DON'T extract if: Abstraction would make code harder to understand

2. **Create helper function**:
   - Clear, descriptive name that explains what it does
   - Add documentation/comments explaining purpose
   - Place near related functions or in appropriate module

3. **Update all call sites**:
   - Test after updating each site
   - Keep changes focused

## Phase 5: Finalize

1. **Run formatter** (if available): Format the code to project standards

2. **Run all tests**: Verify everything still works

3. **Update REFACTOR-TODO.md** with:
   - Complete list of all improvements made
   - Total lines saved
   - Impact summary (readability, maintainability, consistency)

4. **Commit strategy**:
   - Suggest logical commit boundaries (e.g., one commit per helper extraction)
   - Write clear commit messages explaining WHY not just WHAT
   - Ask user before committing

## Guidelines

### DO:

- **Test frequently**: After every few changes
- **One change at a time**: Keep changes focused and logical
- **Preserve behavior**: Never change semantics, only structure
- **Improve clarity**: Only refactor if it makes code clearer
- **Document decisions**: Note in REFACTOR-TODO.md why some patterns weren't
  refactored
- **Consider maintainability**: Think about future developers reading this code

### DON'T:

- **Don't batch unrelated changes**: Keep refactorings focused
- **Don't over-abstract**: Avoid creating unnecessary indirection
- **Don't sacrifice clarity for brevity**: Shorter isn't always better
- **Don't refactor without tests**: Always verify behavior is preserved
- **Don't force patterns**: If code is already clear, leave it alone
