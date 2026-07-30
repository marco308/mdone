# Issue #17 Date Ranges Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Make Vikunja task start/end dates editable and display date-range tasks on every applicable calendar day without losing those dates during other task mutations.

**Architecture:** Normalize Vikunja zero-date sentinels in `VTask`, centralize calendar-day membership there, and let `AppState` use that pure behavior for day/month grouping. Extend request encoding and the SwiftData cache before wiring one shared SwiftUI schedule editor into both iOS and macOS task details.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, XCTest, Vikunja REST API v1.

---

## Acceptance criteria

- Start and end are independently optional and editable with date and time.
- Vikunja's year-1 zero date is treated as absent.
- If both values are present, end must be greater than or equal to start; the UI prevents saving an invalid range.
- A task with both start and end appears on every local calendar day touched by the inclusive range.
- A task with only start appears on its start day; a task with only end appears on its end day.
- A due-only task keeps the current behavior.
- If a due date and range resolve to the same day, the task appears only once on that day.
- Date iteration uses `Calendar` operations, not fixed 86,400-second increments.
- Setting and clearing start/end encodes `start_date`/`end_date` correctly, including Vikunja's zero-date sentinel for clearing.
- Existing start/end dates survive ordinary edits, completion toggles, rescheduling, progress changes, and undo operations.
- Start/end survive a `CachedTask` round trip and lightweight migration from an existing store.
- The same editor behavior is used on iOS and macOS.
- No external dependencies are added.

## Out of scope

- Continuous multi-day bars in the month grid; existing dots and day-list rows are sufficient.
- Projecting repeating-task occurrences (Issue #35).
- Completing the currently unconnected generic offline mutation queue.
- Start/end controls in Quick Add; creation support can follow separately.

### Task 1: Add normalized task-date behavior

**Files:**
- Modify: `mDone/Models/VTask.swift`
- Test: `mDoneTests/TaskServiceTests.swift`

1. Add failing tests for effective start/end dates and day membership.
2. Verify the tests fail because the APIs do not exist.
3. Add minimal pure computed properties/methods.
4. Cover only-start, only-end, same-day, multi-day, due-only, mixed due/range, invalid range, month boundary, and DST-safe iteration.
5. Run the focused tests and then all unit tests on macOS CI.

### Task 2: Encode setting, clearing, and preservation

**Files:**
- Modify: `mDone/Models/VTask.swift`
- Modify: `mDone/Services/TaskService.swift`
- Modify: `mDone/App/AppState.swift`
- Test: `mDoneTests/TaskServiceTests.swift`
- Test: `mDoneTests/AppStateTests.swift`

1. Add failing encoding tests for set/clear start and end.
2. Extend `TaskUpdateRequest` with dates and explicit clear flags.
3. Add a narrow central preservation mechanism so unrelated mutations retain start/end and existing repeat metadata.
4. Test completion, reschedule, progress, undo, and ordinary detail save requests.

### Task 3: Persist ranges in SwiftData

**Files:**
- Modify: `mDone/Services/CacheService.swift`
- Test: `mDoneTests/SyncServiceTests.swift`

1. Add a failing cache round-trip test.
2. Add optional `startDate`/`endDate` fields to `CachedTask` and every conversion/update path.
3. Test nil and populated values.
4. Verify an existing-store lightweight migration on a macOS/iOS runner.

### Task 4: Use ranges in calendar grouping

**Files:**
- Modify: `mDone/App/AppState.swift`
- Test: `mDoneTests/AppStateTests.swift`

1. Add failing tests for `tasksForDate` and `datesWithTasks`.
2. Make both methods consume the pure day-membership behavior.
3. Clip month traversal correctly and deduplicate by task id per day.
4. Verify month boundaries and DST transitions.

### Task 5: Add shared schedule editor

**Files:**
- Create: `mDone/Views/Components/TaskScheduleEditor.swift`
- Modify: `mDone/Views/Tasks/TaskDetailSheet.swift`
- Modify: `mDone/Views/Mac/MacTaskDetailView.swift`

1. Add shared bindings for due/start/end optional dates.
2. Show independent toggles and date/time pickers.
3. Prevent save when end precedes start and provide an accessible explanation.
4. Include dates and clear flags in both save paths.
5. Keep macOS `.onChange` state synchronized using effective dates.

### Task 6: Display range metadata

**Files:**
- Modify: `mDone/Views/Tasks/TaskRow.swift`
- Test: add formatter tests in the most suitable existing/new XCTest file.

1. Add failing formatter tests.
2. Render a compact localized range while retaining due-date semantics.
3. Extend the accessibility label with start/end information.
4. Ensure narrow/compact rows do not overflow.

### Task 7: Integration verification and PR

**Files:**
- Modify: `scripts/seed-dev-vikunja.sh`
- Modify: `CHANGELOG.md`

1. Seed same-day, multi-day, and month-crossing tasks.
2. Run `swiftformat .` and `swiftlint lint --quiet` on macOS.
3. Generate the project with XcodeGen.
4. Run iOS unit tests and both iOS/macOS builds.
5. Manually verify against disposable Vikunja, including set, edit, clear, complete, reschedule, restart/cache, and calendar display.
6. Review the complete diff for API data loss, migration risk, accessibility, and scope creep.
7. Open a focused upstream PR with `Fixes #17`.
