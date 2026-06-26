# Testing

ReduxCore is designed to be tested without mocks, dependency containers, or async machinery. Reducers are pure functions; state is a value type; middleware side effects are isolated.

---

## Testing reducers

A reducer is a pure function — the only setup is constructing a state value. No stores, no async, no injection.

```swift
import Testing
@testable import YourFeature

@Suite struct TaskReducerTests {

    @Test func loadedTasksReplacesExistingList() {
        var state = TaskState()
        TaskReducer().reduce(action: .tasksLoaded([task1, task2]), state: &state)
        #expect(state.tasks.count == 2)
        #expect(state.isLoading == false)
    }

    @Test func appearedSetsLoadingFlag() {
        var state = TaskState()
        TaskReducer().reduce(action: .appeared, state: &state)
        #expect(state.isLoading == true)
        #expect(state.errorMessage == nil)
    }

    @Test func failedStoresMessageAndClearsLoading() {
        var state = TaskState(isLoading: true)
        TaskReducer().reduce(action: .failed("Network error"), state: &state)
        #expect(state.errorMessage == "Network error")
        #expect(state.isLoading == false)
    }

    @Test func deleteRemovesMatchingTask() {
        let target = Task(id: UUID(), title: "Buy milk", isDone: false)
        var state = TaskState(tasks: [target])
        TaskReducer().reduce(action: .taskDeleted(target.id), state: &state)
        #expect(state.tasks.isEmpty)
    }
}
```

The test constructs state, calls the reducer, asserts the result. One input, one output — no infrastructure involved.

---

## Testing computed state

Computed properties on state are just functions of their inputs. Test them by setting up the inputs:

```swift
@Suite struct TaskStateTests {

    @Test func filteredTasksMatchesCaseInsensitively() {
        var state = TaskState(tasks: [
            Task(id: UUID(), title: "Buy Milk", isDone: false),
            Task(id: UUID(), title: "Read book", isDone: false),
        ])
        state.searchQuery = "milk"
        #expect(state.filteredTasks.count == 1)
        #expect(state.filteredTasks[0].title == "Buy Milk")
    }

    @Test func filteredTasksReturnsAllWhenQueryIsEmpty() {
        var state = TaskState(tasks: [
            Task(id: UUID(), title: "A", isDone: false),
            Task(id: UUID(), title: "B", isDone: false),
        ])
        state.searchQuery = ""
        #expect(state.filteredTasks.count == 2)
    }
}
```

---

## Testing middleware

Middleware is an async function that receives an action, the current state, and a `dispatch` closure. Test it by passing a mock `dispatch` closure and asserting what gets dispatched.

```swift
@Suite struct TaskMiddlewareTests {

    @Test func appearedDispatchesTasksLoaded() async {
        let api = MockTaskAPIClient(stubbedTasks: [task1])
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let dispatch: @Sendable (TaskAction) async -> Void = { dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), dispatch: dispatch)

        #expect(dispatched.count == 1)
        guard case .tasksLoaded(let tasks) = dispatched[0] else {
            Issue.record("Expected tasksLoaded"); return
        }
        #expect(tasks.count == 1)
    }

    @Test func createTappedDispatchesTaskCreated() async {
        let newTask = Task(id: UUID(), title: "Buy milk", isDone: false)
        let api = MockTaskAPIClient(stubbedCreatedTask: newTask)
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let dispatch: @Sendable (TaskAction) async -> Void = { dispatched.append($0) }

        await middleware.process(
            action: .createTapped(title: "Buy milk"),
            state: TaskState(),
            dispatch: dispatch
        )

        #expect(dispatched == [.taskCreated(newTask)])
    }

    @Test func apiFailureDispatchesFailed() async {
        let api = MockTaskAPIClient(shouldThrow: true)
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let dispatch: @Sendable (TaskAction) async -> Void = { dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), dispatch: dispatch)

        guard case .failed = dispatched.first else {
            Issue.record("Expected failed action"); return
        }
    }
}
```

### When middleware must not dispatch

Some middleware (analytics, logging) never calls `dispatch`. Assert the dispatch list stays empty:

```swift
@Test func analyticsMiddlewareNeverDispatchesActions() async {
    let tracker = MockAnalyticsTracker()
    let middleware = AnalyticsMiddleware(tracker: tracker)

    var dispatched: [TaskAction] = []
    let dispatch: @Sendable (TaskAction) async -> Void = { dispatched.append($0) }

    await middleware.process(action: .appeared, state: TaskState(), dispatch: dispatch)

    #expect(dispatched.isEmpty)
    #expect(tracker.trackedEvents == ["task_list_viewed"])
}
```

---

## What to mock

| Layer | What to mock |
|---|---|
| Reducer | Nothing — pure function, construct state directly |
| Computed state | Nothing — set up the relevant state fields |
| Middleware | External dependencies (API clients, repositories). Pass a real `dispatch` closure. |
| View | Nothing — test reducers and middleware in isolation instead |

Mock only the I/O boundary (network, disk, system clock). Everything inside the Redux layer is a pure function or a deterministic async operation — mock-free by design.
