# Reducer Purity

## What a reducer actually is

A reducer is a pure function:

```
state' = reduce(state, action)
```

Given the same `state` and the same `action`, it must always produce the same `state'`. No exceptions. This is not a style guideline — it is the guarantee that makes the entire Redux model work.

When you inject a dependency into a reducer's initializer, you break this guarantee. The output now depends on three things instead of two: `state`, `action`, and whatever the injected value contains. The reducer is no longer a pure function — it is a stateful object pretending to be one.

---

## What breaks when a reducer takes arguments

### Testability degrades

A pure reducer tests in one line:

```swift
var state = SearchState()
SearchReducer().reduce(action: .queryChanged("swift"), state: &state)
#expect(state.query == "swift")
```

A reducer with an injected `Config` now requires construction at every test site:

```swift
let config = SearchConfig(minQueryLength: 3, maxResults: 20)
var state = SearchState()
SearchReducer(config: config).reduce(action: .queryChanged("sw"), state: &state)
// What should this assert? It depends on config.minQueryLength.
// Now every test must set up the right config to get predictable results.
```

Multiply this across dozens of tests and the friction compounds. Tests should focus on logic, not on constructing the right combination of injected values.

### Reasoning becomes harder

Redux's core promise is that state is the single source of truth. When config lives inside the reducer, it is invisible state — it affects output but isn't reflected anywhere in the state tree. You cannot look at a `SearchState` value and know why a particular action produced a particular result.

If config is in state, a bug report reproduces with: "start from this state, dispatch this action". With config in the reducer, you also need: "and make sure the reducer was constructed with these arguments". Replay and time-travel debugging become impractical.

### Reuse is blocked

A `FeedReducer(userID: userID)` cannot be used in a different screen with a different user without reconstructing it. A `FeedReducer` that reads `state.userID` works anywhere.

---

## The correct pattern for each temptation

### "I need configuration in my reducer"

Put it in state. Populate it once via a `configured` action dispatched on first appearance.

```swift
// Wrong
struct SearchReducer: ReducerType {
    let config: SearchConfig  // ❌ hidden dependency
    func reduce(action: SearchAction, state: inout SearchState) {
        if state.query.count < config.minQueryLength { return }
        ...
    }
}

// Correct
struct SearchState: Statable {
    var config: SearchConfig = .default  // ✅ visible in state
    var query = ""
}

struct SearchReducer: ReducerType {
    func reduce(action: SearchAction, state: inout SearchState) {
        if case .configured(let config) = action { state.config = config }
        if state.query.count < state.config.minQueryLength { return }
        ...
    }
}
```

The view dispatches `.configured(config)` on `.onAppear`. The config is now part of the state tree — visible, loggable, and testable without any constructor arguments.

### "I need the current user"

The current user is data, not a dependency. Load it via middleware and store it in state.

```swift
// Wrong
struct FeedReducer: ReducerType {
    let currentUser: User  // ❌
    ...
}

// Correct — middleware loads the user and dispatches it into state
final class FeedMiddleware: MiddlewareType, @unchecked Sendable {
    let userRepo: UserRepository

    func process(action: FeedAction, state: FeedState, next: ...) async {
        if case .appeared = action {
            let user = await userRepo.currentUser()
            await next(.userLoaded(user))
        }
    }
}

struct FeedState: Statable {
    var currentUser: User? = nil  // ✅ now visible and testable
}
```

### "I need a date or number formatter"

Formatters are presentation logic — they belong in the view layer, not in the reducer. Store raw values in state; format at render time.

```swift
// Wrong — reducer formats for display
struct EventReducer: ReducerType {
    let dateFormatter: DateFormatter  // ❌
    func reduce(action: EventAction, state: inout EventState) {
        if case .loaded(let event) = action {
            state.displayDate = dateFormatter.string(from: event.date)  // ❌ presentation in state
        }
    }
}

// Correct — reducer stores raw data, view formats
struct EventState: Statable {
    var eventDate: Date? = nil  // ✅ raw value
}

// In the view:
Text(store.state.eventDate?.formatted(.dateTime.month().day()) ?? "—")
```

### "I need feature flags"

Feature flags are configuration. Load them from your feature flag service via middleware on app start and store them in state.

```swift
struct AppState: Statable {
    var flags: FeatureFlags = .defaults
}

// Middleware fetches flags and dispatches them once
struct FeatureFlagMiddleware: MiddlewareType, Sendable {
    let flagService: FlagService

    func process(action: AppAction, state: AppState, next: ...) async {
        if case .appLaunched = action {
            let flags = await flagService.fetch()
            await next(.flagsLoaded(flags))
        }
    }
}
```

Now `AppReducer` reads `state.flags` — it is pure, testable, and the flag state is visible in the state tree.

---

## The architectural boundary

```
Outside world (network, disk, user, time)
        ↓
   Middleware  ← owns all impure, async work
        ↓  (dispatches actions)
    Reducer   ← pure function, state + action → state'
        ↓
     State    ← single source of truth
        ↓
      View    ← renders state, dispatches actions
```

The boundary is clean by design:

- **Middleware** is the only layer that touches the outside world. It converts external events into actions.
- **Reducers** only know about actions and state. They are isolated from the outside world by definition.

When you feel the urge to inject something into a reducer, the question to ask is: *"Should this be data in state, or should middleware handle the async work and dispatch the result?"*

The answer is almost always one of those two. If the value is static configuration, it belongs in state. If it requires I/O to obtain, it belongs in middleware.

---

## The testing payoff

A reducer with no arguments has zero setup cost in tests:

```swift
@Test func queryBelowMinLengthIsIgnored() {
    var state = SearchState(config: .init(minQueryLength: 3))
    SearchReducer().reduce(action: .queryChanged("sw"), state: &state)
    #expect(state.isLoading == false)
}

@Test func queryAtMinLengthTriggersLoad() {
    var state = SearchState(config: .init(minQueryLength: 3))
    SearchReducer().reduce(action: .queryChanged("swi"), state: &state)
    #expect(state.isLoading == true)
}
```

The test constructs state, calls the reducer, asserts the result. No mocks, no factories, no dependency containers. The entire test is the assertion.
