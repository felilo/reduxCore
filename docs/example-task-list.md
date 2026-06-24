# Full Example — Task List

This example wires together every ReduxCore concept in a single realistic feature: a task list that fetches from an API, supports live search with debouncing, and lets users create and delete tasks.

**What it covers:**
- Actions with associated values
- State with loading and error cases
- A pure reducer handling all transitions
- Async middleware fetching from an API
- Debounced search via `TaskCancellationManager`
- Navigation state modelled as an enum
- `@StoreView` with `@MiddlewareResultBuilder`
- A second `@StoreView` for the detail screen, communicating via callbacks

---

## Domain types

```swift
struct TaskItem: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var isDone: Bool
}
```

> **Why `TaskItem` and not `Task`?** Swift's concurrency library defines `Swift.Task`. Naming your domain type `Task` in the same module creates an ambiguity — `Task.sleep(for:)` would resolve to your struct, not the concurrency primitive. `TaskItem` avoids that collision without any other trade-off.

Navigation destinations live in their own type, separate from action or state:

```swift
enum TaskNavigation: Equatable, Sendable {
    case detail(TaskItem)
}
```

---

## Actions

```swift
enum TaskAction: Actionable {
    // User intent
    case appeared
    case searchChanged(String)
    case createTapped(title: String)
    case deleteTapped(id: UUID)
    case navigate(to: TaskNavigation)
    case resetNavigation

    // Middleware results
    case tasksLoaded([TaskItem])
    case taskCreated(TaskItem)
    case taskUpdated(TaskItem)
    case taskDeleted(UUID)
    case failed(String)
}
```

Each case is a named intent or a named result. No raw strings, no untyped payloads.

---

## State

```swift
struct TaskState: Statable {
    var tasks: [TaskItem]           = []
    var searchQuery                 = ""
    var isLoading                   = false
    var errorMessage: String?       = nil
    var navigation: TaskNavigation? = nil

    // Derived — never stored, always computed
    var filteredTasks: [TaskItem] {
        guard !searchQuery.isEmpty else { return tasks }
        return tasks.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }
}
```

`filteredTasks` is computed — not stored — so there is no risk of it going out of sync with `tasks` or `searchQuery`. `navigation` is `nil` when no destination is active; there is no `idle` case.

---

## Reducer

```swift
struct TaskReducer: ReducerType {
    func reduce(action: TaskAction, state: inout TaskState) {
        switch action {

        case .appeared:
            state.isLoading    = true
            state.errorMessage = nil

        case .searchChanged(let query):
            state.searchQuery = query

        case .createTapped:
            state.isLoading = true

        case .deleteTapped:
            break   // optimistic delete: middleware dispatches .taskDeleted after API confirms

        case .navigate(to: let destination):
            state.navigation = destination

        case .resetNavigation:
            state.navigation = nil

        case .tasksLoaded(let tasks):
            state.tasks        = tasks
            state.isLoading    = false
            state.errorMessage = nil

        case .taskCreated(let task):
            state.tasks.append(task)
            state.isLoading = false

        case .taskUpdated(let updated):
            state.tasks = state.tasks.map { $0.id == updated.id ? updated : $0 }

        case .taskDeleted(let id):
            state.tasks.removeAll { $0.id == id }

        case .failed(let message):
            state.errorMessage = message
            state.isLoading    = false
        }
    }
}
```

The reducer is pure. It never decides *when* to fetch or *how* — that belongs to middleware.

---

## Middleware

```swift
struct TaskMiddleware: MiddlewareType, Sendable {

    private let taskManager = TaskCancellationManager()
    private let api: any TaskAPIClient

    init(api: any TaskAPIClient) {
        self.api = api
    }

    func process(
        action: TaskAction,
        state: TaskState,
        next: @escaping @concurrent @Sendable (TaskAction) async -> Void
    ) async {
        switch action {

        case .appeared:
            await fetchTasks(next: next)

        case .searchChanged:
            await taskManager.run(key: "search") {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
                await self.fetchTasks(next: next)
            }

        case .createTapped(let title):
            do {
                let task = try await api.createTask(title: title)
                await next(.taskCreated(task))
            } catch {
                await next(.failed(error.localizedDescription))
            }

        case .deleteTapped(let id):
            do {
                try await api.deleteTask(id: id)
                await next(.taskDeleted(id))
            } catch {
                await next(.failed(error.localizedDescription))
            }

        default:
            break
        }
    }

    private func fetchTasks(next: @escaping @Sendable (TaskAction) async -> Void) async {
        do {
            let tasks = try await api.fetchTasks()
            await next(.tasksLoaded(tasks))
        } catch {
            guard !(error is CancellationError) else { return }
            await next(.failed(error.localizedDescription))
        }
    }
}
```

**Key points:**
- `TaskCancellationManager` is an actor stored as a property. Calling `taskManager.run(key:)` with the same key cancels the previous in-flight task before starting the new one.
- `appeared` triggers an immediate fetch; `searchChanged` debounces before fetching.
- Debounce uses a real `try/catch` — if `Task.sleep` throws `CancellationError`, `catch` returns immediately without hitting the API.
- `fetchTasks` guards against `CancellationError` explicitly so stale network responses never dispatch `.tasksLoaded`.
- `struct` + `Sendable` (not `final class @unchecked Sendable`) — all stored properties are themselves `Sendable`, so the compiler verifies this automatically.

---

## Additional middleware — Analytics

`AnalyticsTracker` is a `Sendable` protocol — any concrete tracker (Mixpanel, Amplitude, console) can be swapped in at the call site.

```swift
protocol AnalyticsTracker: Sendable {
    func track(_ event: String)
    func track(_ event: String, properties: [String: String])
}

extension AnalyticsTracker {
    func track(_ event: String) {
        track(event, properties: [:])
    }
}
```

Each middleware has a single responsibility. `AnalyticsMiddleware` tracks user behaviour events without touching the reducer, the API, or any other middleware.

```swift
struct AnalyticsMiddleware: MiddlewareType, Sendable {

    let tracker: any AnalyticsTracker

    init(tracker: any AnalyticsTracker) {
        self.tracker = tracker
    }

    func process(
        action: TaskAction,
        state: TaskState,
        next: @escaping @concurrent @Sendable (TaskAction) async -> Void
    ) async {
        switch action {
        case .appeared:
            await tracker.track("task_list_viewed")
        case .createTapped(let title):
            await tracker.track("task_create_tapped", properties: ["title_length": "\(title.count)"])
        case .taskCreated:
            await tracker.track("task_created")
        case .deleteTapped:
            await tracker.track("task_delete_tapped")
        case .failed(let message):
            await tracker.track("task_error", properties: ["message": message])
        default:
            break
        }
        // Analytics middleware never calls next() — it has no follow-up actions to dispatch.
    }
}
```

---

## Additional middleware — Logger

`LoggerMiddleware` is generic over any `Action`/`State` pair — the same type works in any `@StoreView` without changes.

```swift
struct LoggerMiddleware<Action: Actionable, State: Statable>: MiddlewareType, Sendable {
    func process(
        action: Action,
        state: State,
        next: @escaping @concurrent @Sendable (Action) async -> Void
    ) async {
#if DEBUG
        print("[Store] ▶ \(action)")
#endif
        // Logger never calls next() — it has no follow-up actions to dispatch.
    }
}
```

---

## How all three middleware work together

All middleware registered in the stack receive **every action in parallel** via `withTaskGroup`. None of them know the others exist.

```
store.dispatch(.createTapped(title: "Buy milk"))
        │
        ├──▶  TaskReducer        → state.isLoading = true  (sync, immediate)
        │
        │     (then, concurrently:)
        │
        ├──▶  TaskMiddleware     → await api.createTask(...)
        │                           await next(.taskCreated(task))
        │
        ├──▶  AnalyticsMiddleware → await tracker.track("task_create_tapped", ...)
        │                           (no next call)
        │
        └──▶  LoggerMiddleware   → print("[Store] ▶ createTapped(title: "Buy milk")")
                                    (no next call)
```

A slow network call in `TaskMiddleware` never blocks `AnalyticsMiddleware` or `LoggerMiddleware` — they complete independently.

### Isolation checklist

| | `TaskMiddleware` | `AnalyticsMiddleware` | `LoggerMiddleware` |
|---|---|---|---|
| Calls the API | ✅ | ✗ | ✗ |
| Dispatches follow-up actions | ✅ | ✗ | ✗ |
| Tracks analytics events | ✗ | ✅ | ✗ |
| Prints to console | ✗ | ✗ | ✅ |
| Knows other middleware exist | ✗ | ✗ | ✗ |

Adding or removing any one of them has zero impact on the others.

---

## Row view — plain closures

`TaskRowView` is a pure display component. It accepts the task value and two callbacks — it knows nothing about `TaskReducer`, `TaskState`, or `TaskAction`.

```swift
struct TaskRowView: View {
    let task: TaskItem
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isDone ? .green : .secondary)
                .imageScale(.large)
            Text(task.title)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}
```

The closures are bound at the call site in `TaskContentView`, mapping gestures directly to dispatched actions. No `ScopedStore`, no intermediate action enum needed for the row.

---

## Screen

```swift
@StoreView(reducer: TaskReducer.self)
struct TaskListScreen: View {

    @Environment(\.taskAPIClient) private var api
    @Environment(\.analyticsTracker) private var tracker

    @MiddlewareResultBuilder
    var middleware: [Middleware] {
        TaskMiddleware(api: api)
        AnalyticsMiddleware(tracker: tracker)
        LoggerMiddleware()
    }

    @ViewBuilder
    func content(store: Store) -> some View {
        let state = store.state

        taskStack(store: store, state: state)
            .overlay { loadingOverlay(isLoading: state.isLoading) }
            .task { store.dispatch(.appeared) }
    }

    @ViewBuilder
    private func taskStack(store: Store, state: TaskState) -> some View {
        NavigationStack {
            TaskContentView(
                filteredTasks: state.filteredTasks,
                searchQuery: state.searchQuery,
                onTaskTapped: { store.dispatch(.navigate(to: .detail($0))) },
                onTaskDeleted: { store.dispatch(.deleteTapped(id: $0.id)) }
            )
            .navigationTitle("Tasks")
            .searchable(
                text: Binding(
                    get: { state.searchQuery },
                    set: { store.dispatch(.searchChanged($0)) }
                ),
                prompt: "Search tasks"
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton { store.dispatch(.createTapped(title: "New Task")) }
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { state.errorMessage != nil }, set: { _ in }),
                presenting: state.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .sheet(item: Binding<TaskItem?>(
                get: {
                    guard case .detail(let task) = state.navigation else { return nil }
                    return task
                },
                set: { _ in store.dispatch(.resetNavigation) }
            )) { task in
                TaskDetailView(
                    initialTask: task,
                    onDismiss: { store.dispatch(.resetNavigation) },
                    onTaskChanged: { store.dispatch(.taskUpdated($0)) }
                )
            }
        }
    }

    @ViewBuilder
    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Task")
    }

    @ViewBuilder
    private func loadingOverlay(isLoading: Bool) -> some View {
        ProgressView("Loading tasks…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .opacity(isLoading ? 1 : 0)
            .animation(.default, value: isLoading)
    }
}

// MARK: - Content View

private struct TaskContentView: View {
    let filteredTasks: [TaskItem]
    let searchQuery: String
    let onTaskTapped: (TaskItem) -> Void
    let onTaskDeleted: (TaskItem) -> Void

    var body: some View {
        List {
            ForEach(filteredTasks) { task in
                TaskRowView(
                    task: task,
                    onTap: { onTaskTapped(task) },
                    onDelete: { onTaskDeleted(task) }
                )
            }
        }
        .overlay {
            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? "No Tasks" : "No Results",
                    systemImage: searchQuery.isEmpty ? "checklist" : "magnifyingglass",
                    description: Text(
                        searchQuery.isEmpty
                            ? "Tap + to add your first task."
                            : "No tasks match \"\(searchQuery)\"."
                    )
                )
            }
        }
    }
}
```

**Key points:**
- Dependencies arrive via `@Environment` — the screen is instantiated with no arguments.
- `content(store:)` immediately delegates to `taskStack(store:state:)` and attaches the loading overlay and `.task` lifecycle modifier outside the `NavigationStack`.
- `TaskContentView` is a private struct that accepts pure value inputs and closures. It has no store reference and re-renders only when its inputs change.
- Navigation uses a `Binding<TaskItem?>` that reads `state.navigation` and dispatches `.resetNavigation` on `set`, keeping the sheet in sync with state.
- The add button is `Image(systemName: "plus")` with `.accessibilityLabel`, not a text button.
- `.task { store.dispatch(.appeared) }` runs once when the view appears and is automatically cancelled if the view is removed from the hierarchy.

---

## Detail view

`TaskDetailView` has its own `@StoreView`, its own reducer, and its own middleware. The list screen knows nothing about how the detail view manages its state — it only provides the initial task and two callbacks.

```swift
@StoreView(reducer: TaskDetailReducer.self)
struct TaskDetailView: View {

    let initialTask: TaskItem
    let onDismiss: () -> Void
    var onTaskChanged: ((TaskItem) -> Void)? = nil

    @Environment(\.taskAPIClient) private var api
    @Environment(\.analyticsTracker) private var tracker

    @MiddlewareResultBuilder
    var middleware: [Middleware] {
        TaskDetailMiddleware(api: api)
        TaskDetailAnalyticsMiddleware(tracker: tracker)
        LoggerMiddleware()
    }

    @ViewBuilder
    func content(store: Store) -> some View {
        let task = store.state.task ?? initialTask

        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 64))
                    .foregroundStyle(task.isDone ? .green : .secondary)
                Text(task.title)
                    .font(.title2)
                Button(task.isDone ? "Mark as Undone" : "Mark as Done") {
                    store.dispatch(.toggleDoneTapped)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Task Detail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task { store.dispatch(.appeared(initialTask)) }
        .onChange(of: store.state.task) { oldTask, newTask in
            guard oldTask != nil, let newTask else { return }
            onTaskChanged?(newTask)
        }
    }
}
```

`onTaskChanged` fires whenever the task changes inside the detail view (e.g. after toggling done). The list screen receives the updated task via that callback and dispatches `.taskUpdated(_:)` to keep its own state in sync — no shared state, no direct coupling between screens.

---

## Dependency injection

Both screens read their dependencies through `@Environment`. The app entry point injects concrete implementations once; the environment carries them down automatically.

```swift
extension EnvironmentValues {
    @Entry var taskAPIClient: any TaskAPIClient = LocalTaskAPIClient()
    @Entry var analyticsTracker: any AnalyticsTracker = ConsoleAnalyticsTracker()
}

@main
struct TaskListApp: App {
    private let api: any TaskAPIClient = LocalTaskAPIClient()
    private let tracker: any AnalyticsTracker = ConsoleAnalyticsTracker()

    var body: some Scene {
        WindowGroup {
            TaskListScreen()
                .environment(\.taskAPIClient, api)
                .environment(\.analyticsTracker, tracker)
        }
    }
}
```

Previews swap in lightweight stubs without touching the app entry point:

```swift
#Preview("Loaded") {
    TaskListScreen()
        .environment(\.taskAPIClient, PreviewAPIClient(tasks: [
            TaskItem(id: UUID(), title: "Buy groceries", isDone: false),
            TaskItem(id: UUID(), title: "Read a book",   isDone: true),
        ]))
}
```

---

## How the pieces connect

```
User taps "Add"
    │
    ▼
store.dispatch(.createTapped(title: "New Task"))
    │
    ├──▶  TaskReducer.reduce(.createTapped, &state)
    │         state.isLoading = true          → loading overlay appears
    │
    └──▶  TaskMiddleware.process(.createTapped, state, next)
              await api.createTask(...)
              await next(.taskCreated(task))
                  │
                  ├──▶  TaskReducer.reduce(.taskCreated(task), &state)
                  │         state.tasks.append(task)
                  │         state.isLoading = false   → new row appears
                  │
                  └──▶  TaskMiddleware.process(.taskCreated, ...)
                            default: break             → no further action
```

```
User types "buy" in search bar
    │
    ▼  (each keystroke)
store.dispatch(.searchChanged("b"))
store.dispatch(.searchChanged("bu"))
store.dispatch(.searchChanged("buy"))
    │
    ├──▶  TaskReducer: state.searchQuery = "buy"   → filteredTasks updates immediately
    │
    └──▶  TaskMiddleware: taskManager.run(key: "search") { sleep(300ms); fetchTasks() }
              — first two tasks are cancelled before they wake —
              — third fires after 300ms of no new keystrokes —
              await next(.tasksLoaded([...]))
```

The reducer keeps the UI responsive on every keystroke (instant local filter via `filteredTasks`). The middleware debounces the API call so the server is only hit once after the user pauses.
