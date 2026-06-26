# ReduxCore

A lightweight Redux library for SwiftUI built on Swift structured concurrency. Unidirectional data flow, composable reducers, async middleware, and a macro that eliminates store boilerplate.


[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS 16.0+](https://img.shields.io/badge/iOS-17.0+-blue.svg)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/Framework-SwiftUI-green.svg)](https://developer.apple.com/xcode/swiftui/)
[![MIT License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

```
  ┌─────────────────────────────────────────────────────┐
  │                                                     │
  │   View  ──── dispatch ────▶  Action                 │
  │    ▲                            │                   │
  │    │                 ┌──────────┴──────────┐        │
  │    │                 ▼                     ▼        │
  │    │          Reducer (sync)        Middleware      │
  │    │                 │               (async)        │
  │    └──── State ◀─────┘                 │            │
  │                                   next(Action) ─────┘
  │
  └─── unidirectional, @MainActor
```

## Why ReduxCore

Redux discipline usually comes bundled with ceremony — effect types to learn,
dependency containers to wire, test harnesses to set up. ReduxCore keeps the
unidirectional guarantees and drops the rest.

- **One macro per screen.** `@StoreView` generates the store, the `Store` and
  `Middleware` typealiases, and the `body`. You write actions, a reducer, and a
  view — the boilerplate is gone.

- **Zero runtime dependencies.** The only package is `swift-syntax`, and it's a
  build-time macro plugin — nothing ships in your app binary.

- **Side effects are plain `async/await`.** Middleware is just an async
  function. No custom `Effect` type, no scheduler. All middleware run in
  parallel, so one slow effect never blocks the others.

- **Debouncing built in.** Conform to `CancellableTask` and call `run(key:)` —
  the previous task under that key is cancelled before the next starts. Search-
  as-you-type, delayed autosave, and any "only the last one matters" flow work
  out of the box, backed by an actor that keeps memory bounded.

- **Cycle detection out of the box.** Two diagnostics catch runaway dispatch
  loops — a frequency detector ("action fired 21× in under a second") and a
  depth detector for re-entrant chains. Both are DEBUG-only and never drop or
  delay a real dispatch.

- **Tests without mocks or machinery.** Reducers are pure functions: build a
  state value, call `reduce`, assert the result. Middleware is tested by passing
  a plain `next` closure and checking what it dispatched. You mock only the I/O
  boundary — everything inside the Redux layer is mock-free by design.

- **Small enough to read in an afternoon.** Three protocols, one macro, two
  composition operators (`Scope` and `combined(with:)`). You can hold the whole
  framework in your head.

If you've felt that unidirectional data flow shouldn't require this much
ceremony, that's the gap ReduxCore fills.

---

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

---

## Installation

Add via **File → Add Package Dependencies** in Xcode, or in `Package.swift`:

```swift
.package(url: "https://github.com/felilo/ReduxCore", from: "1.0.0")
```

Then import:

```swift
import ReduxCore
```

---

## Examples

### Task List

A complete real-world feature: async API calls, debounced search, navigation, a detail screen with its own store, and three composable middleware.

- [Full walkthrough](docs/example-task-list.md) — step-by-step breakdown of every piece
- [Source code](https://github.com/felilo/ReduxCore/tree/main/Examples/TaskList) — runnable Xcode project

---

## Quick Start

The counter below shows the full pattern in one shot.

**1 — Actions and state**

```swift
enum CounterAction: Actionable {
    case increment
    case decrement
}

struct CounterState: Statable {
    var count = 0
}
```

**2 — Reducer**

```swift
struct CounterReducer: ReducerType {
    func reduce(action: CounterAction, state: inout CounterState) {
        switch action {
        case .increment: state.count += 1
        case .decrement: state.count -= 1
        }
    }
}
```

**3 — Screen**

```swift
@StoreView(reducer: CounterReducer.self)
struct CounterScreen: View {

    var middleware: [Middleware] { [] }

    func content(store: Store) -> some View {
        VStack {
            Text("\(store.state.count)")
            Button("+") { store.dispatch(.increment) }
            Button("−") { store.dispatch(.decrement) }
        }
    }
}
```

`@StoreView` generates `body`, the `Store` typealias, and the `Middleware` typealias. The store lives in a `@State` property inside `StoreContainerView` — it is created once and cancelled automatically when the view leaves the hierarchy.

---

## Protocols

### `Actionable`

Actions describe intent. They are pure values — no logic, no side effects.

```swift
enum SearchAction: Actionable {
    case queryChanged(String)
    case resultsLoaded([Item])
    case failed(Error)
}
```

Requires `Equatable` and `Sendable`. Swift synthesises both for enums automatically.

### `Statable`

State is a value type initializable with no arguments.

```swift
struct SearchState: Statable {
    var query = ""
    var results: [Item] = []
    var isLoading = false
}
```

Requires `Equatable`, `Sendable`, and `init()`. Swift synthesises `Equatable` for structs automatically.

---

## Reducer

Reducers are pure and synchronous. No async code, no I/O, no side effects.

```swift
struct SearchReducer: ReducerType {
    func reduce(action: SearchAction, state: inout SearchState) {
        switch action {
        case .queryChanged(let q):
            state.query = q
            state.isLoading = true
        case .resultsLoaded(let items):
            state.results = items
            state.isLoading = false
        case .failed:
            state.isLoading = false
        }
    }
}
```

`state` is `inout` — mutate it directly, return nothing.

---

## Reducer Composition

### `Scope`

`Scope` delegates a slice of parent state to a child reducer. The child type knows nothing about the parent — it only sees its own `Action` and `State`.

```swift
// Parent wraps child actions in a dedicated case
enum HomeAction: Actionable {
    case header(HeaderAction)
    case list(ListAction)
}

struct HomeState: Statable {
    var header = HeaderState()
    var list   = ListState()
}

struct HomeReducer: ReducerType {
    func reduce(action: HomeAction, state: inout HomeState) {

        Scope(
            state: \.header,
            action: { guard case .header(let a) = $0 else { return nil }; return a }
        ) {
            HeaderReducer()
        }
        .reduce(action: action, state: &state)

        Scope(
            state: \.list,
            action: { guard case .list(let a) = $0 else { return nil }; return a }
        ) {
            ListReducer()
        }
        .reduce(action: action, state: &state)
    }
}
```

`Scope` calls the `action` closure on every dispatch. If it returns `nil` the child reducer is skipped. Adding a new sub-feature is one new `Scope` block — nothing else changes.

### `combined(with:)`

Runs two reducers sequentially on the same action and state. Both must share the same types.

```swift
let pipeline = CoreReducer().combined(with: AnalyticsReducer())
```

For full details on both patterns → [Reducer Composition](docs/reducer-composition.md)

---

## Middleware

Middleware handles async side effects. It receives every action *after* the reducer has already applied it to state.

```swift
struct SearchMiddleware: MiddlewareType, Sendable {
    let api: APIClient

    func process(
        action: SearchAction,
        state: SearchState,
        dispatch: @escaping DispatchClosure<SearchAction>
    ) async {
        guard case .queryChanged(let query) = action else { return }
        let results = (try? await api.search(query)) ?? []
        await dispatch(.resultsLoaded(results))
    }
}
```

All middleware run **in parallel** via `withTaskGroup`. A slow middleware never blocks others.

For debouncing, task cancellation, and cycle detection → [Advanced Middleware](docs/middleware.md)

---

## `@StoreView`

Apply to any `View` struct. Declare `middleware` and `content` — the macro generates everything else.

```swift
@StoreView(reducer: SearchReducer.self)
struct SearchScreen: View {

    let api: APIClient

    @MiddlewareResultBuilder
    var middleware: [Middleware] {
        SearchMiddleware(api: api)
    }

    func content(store: Store) -> some View {
        List(store.state.results) { item in
            Text(item.name)
        }
        .searchable(
            text: Binding(
                get: { store.state.query },
                set: { store.dispatch(.queryChanged($0)) }
            )
        )
    }
}
```

### What the macro generates

```swift
typealias Store                   = ObservableStore<SearchReducer>
typealias Middleware              = AnyMiddleware<SearchReducer.Action, SearchReducer.State>
typealias MiddlewareResultBuilder = MiddlewareBuilder<SearchReducer.Action, SearchReducer.State>

var body: some View {
    StoreContainerView(
        reducer: SearchReducer(),
        middleware: middleware,
        content: { store in content(store: store) }
    )
}
```

### Lifecycle

The store is held in `@State`. In-flight middleware effects are cancelled when the view is **permanently** removed (navigation pop, sheet dismiss). Transient disappearances — pushing a child screen, switching tabs — do not cancel it.

### Reducers take no arguments

Reducers are pure functions — same inputs always produce the same output. Injecting a dependency into a reducer's initializer breaks that guarantee: the output now depends on hidden state invisible to the rest of the system.

If you need configuration, put it in state and dispatch a setup action on first appearance. If you need data from an external source, let middleware fetch it and dispatch the result.

For the full reasoning and patterns for each common case → [Reducer Purity](docs/reducer-purity.md)

---

## Scoping state to child views

`store.scope(state:action:)` creates a `ScopedStore` that a child view subscribes to. The child re-renders only when its derived state slice changes — not on every parent state update.

```swift
// In the parent content function
let headerStore = store.scope(
    state: \.header,
    action: { SearchAction.header($0) }
)
HeaderView(store: headerStore)
```

```swift
struct HeaderView: View {
    let store: ScopedStore<SearchReducer, HeaderState, HeaderAction>

    var body: some View {
        Text(store.state.title)
        Button("Refresh") { store.dispatch(.refresh) }
    }
}
```

`HeaderView` knows nothing about `SearchReducer` or `SearchState`. Dispatched `HeaderAction` values are mapped to `SearchAction` transparently.

---

## Boundaries

**What ReduxCore manages:**
`Actionable` / `Statable` conformances, reducers, middleware, `Scope` composition, and `@StoreView` screens.

**What lives outside it:**
- Navigation and routing (see [SUICoordinator](https://github.com/felilo/SUICoordinator))
- UI layout — views are wired to the store but their structure is plain SwiftUI
- External API clients — injected into middleware, never owned by the framework
- Raw domain models (`TaskItem`, `User`, etc.) — no `import ReduxCore` needed

**Hard rules:**
- Reducers must be pure — no `async`, no I/O.
- Middleware owns all async work.
- Views only read `store.state` and write via `store.dispatch(_:)`. No business logic in views.
- Domain models and service protocols carry zero framework or UI imports.

For testing patterns → [Testing](docs/testing.md)

---

## Navigation

For coordinator-based navigation that pairs cleanly with ReduxCore's decoupled views, see [SUICoordinator](https://github.com/felilo/SUICoordinator) — the [Decoupled Views](https://github.com/felilo/SUICoordinator/blob/main/Docs/DecoupledViews.md) guide shows exactly how screens built with `@StoreView` plug in.
