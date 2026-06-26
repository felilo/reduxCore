# Reducer Composition

## The problem Scope solves

As a screen grows, its reducer grows with it. Without composition, a single `HomeReducer` that owns a feed, a profile header, and notifications ends up looking like this:

```swift
struct HomeReducer: ReducerType {
    func reduce(action: HomeAction, state: inout HomeState) {
        switch action {

        // Feed logic
        case .feedLoaded(let posts):   state.feedPosts = posts
        case .feedRefresh:             state.feedIsLoading = true
        case .feedScrolledToEnd:       state.feedPage += 1
        case .postLiked(let id):       state.feedPosts[id]?.isLiked.toggle()
        case .postDeleted(let id):     state.feedPosts.removeAll { $0.id == id }

        // Profile header logic
        case .profileLoaded(let u):    state.profileUser = u
        case .avatarTapped:            state.profileIsExpanded.toggle()
        case .followTapped:            state.profileIsFollowing.toggle()

        // Notifications logic
        case .notificationsLoaded(let n): state.notifications = n
        case .notificationRead(let id):   state.notifications[id]?.isRead = true
        case .notificationsDismissAll:    state.notifications.removeAll()

        // Cross-cutting
        case .logout:
            state = HomeState()
        }
    }
}
```

This works until it doesn't. Problems that emerge:
- Every new sub-feature adds more cases to the same switch.
- Testing feed logic requires constructing a full `HomeState`, even though feed tests don't care about profile or notifications.
- Reusing `FeedReducer` in a different screen is impossible — it only knows how to mutate `HomeState`.

---

## Scope

`Scope` connects a **child reducer** that owns its own `Action`/`State` types to a **named property inside parent state**. The parent reducer stays small; each child reducer is isolated and independently testable.

### Full example — Home screen

```swift
// MARK: - Feed sub-feature

enum FeedAction: Actionable {
    case loaded([Post])
    case refresh
    case scrolledToEnd
    case postLiked(Post.ID)
    case postDeleted(Post.ID)
}

struct FeedState: Statable {
    var posts: [Post] = []
    var isLoading = false
    var page = 0
}

struct FeedReducer: ReducerType {
    func reduce(action: FeedAction, state: inout FeedState) {
        switch action {
        case .loaded(let posts):     state.posts = posts; state.isLoading = false
        case .refresh:               state.isLoading = true
        case .scrolledToEnd:         state.page += 1
        case .postLiked(let id):     state.posts[id: id]?.isLiked.toggle()
        case .postDeleted(let id):   state.posts.removeAll { $0.id == id }
        }
    }
}


// MARK: - Profile sub-feature

enum ProfileAction: Actionable {
    case loaded(User)
    case avatarTapped
    case followTapped
}

struct ProfileState: Statable {
    var user: User? = nil
    var isExpanded = false
    var isFollowing = false
}

struct ProfileReducer: ReducerType {
    func reduce(action: ProfileAction, state: inout ProfileState) {
        switch action {
        case .loaded(let user):   state.user = user
        case .avatarTapped:       state.isExpanded.toggle()
        case .followTapped:       state.isFollowing.toggle()
        }
    }
}


// MARK: - Parent

enum HomeAction: Actionable {
    case feed(FeedAction)
    case profile(ProfileAction)
    case logout
}

struct HomeState: Statable {
    var feed    = FeedState()
    var profile = ProfileState()
}

struct HomeReducer: ReducerType {
    func reduce(action: HomeAction, state: inout HomeState) {

        // Cross-cutting logic that belongs to the parent
        if case .logout = action {
            state = HomeState()
            return
        }

        Scope(
            state: \.feed,
            action: { guard case .feed(let a)    = $0 else { return nil }; return a }
        ) { FeedReducer() }
        .reduce(action: action, state: &state)

        Scope(
            state: \.profile,
            action: { guard case .profile(let a) = $0 else { return nil }; return a }
        ) { ProfileReducer() }
        .reduce(action: action, state: &state)
    }
}
```

`FeedReducer` and `ProfileReducer` have zero knowledge of `HomeAction` or `HomeState`. You can test them with their own types:

```swift
func testPostLike() {
    var state = FeedState(posts: [Post(id: "1", isLiked: false)])
    FeedReducer().reduce(action: .postLiked("1"), state: &state)
    #expect(state.posts[id: "1"]?.isLiked == true)
}
```

---

## Connecting Scope to views with `ScopedStore`

`Scope` (in the reducer layer) and `store.scope(state:action:)` (in the view layer) are two halves of the same idea. The reducer splits state apart; the view layer subscribes to each slice independently.

```swift
func content(store: Store) -> some View {
    VStack {
        ProfileHeaderView(
            store: store.scope(
                state: \.profile,
                action: { HomeAction.profile($0) }
            )
        )
        FeedView(
            store: store.scope(
                state: \.feed,
                action: { HomeAction.feed($0) }
            )
        )
        Button("Log out") { store.dispatch(.logout) }
    }
}
```

`FeedView` only re-renders when `FeedState` changes. A profile update — `ProfileState` changing — does not trigger `FeedView` to re-render, even though they share the same root store.

```swift
struct FeedView: View {
    // Knows nothing about HomeReducer or HomeState
    let store: ScopedStore<HomeReducer, FeedState, FeedAction>

    var body: some View {
        List(store.state.posts) { post in
            PostRow(post: post)
                .onTapGesture { store.dispatch(.postLiked(post.id)) }
        }
        .refreshable { await store.dispatchAsync(.refresh) }
    }
}
```

---

## Nested Scope

Scope composes recursively. A child reducer can use `Scope` itself to delegate to grandchild reducers.

```swift
// Grandchild — completely isolated
enum CommentsAction: Actionable { case loaded([Comment]); case posted(String) }
struct CommentsState: Statable { var items: [Comment] = [] }
struct CommentsReducer: ReducerType { ... }

// Child — owns PostState and delegates \.comments to CommentsReducer
enum PostAction: Actionable {
    case liked
    case comments(CommentsAction)
}

struct PostState: Statable {
    var isLiked   = false
    var comments  = CommentsState()
}

struct PostReducer: ReducerType {
    func reduce(action: PostAction, state: inout PostState) {
        if case .liked = action { state.isLiked.toggle() }

        Scope(
            state: \.comments,
            action: { guard case .comments(let a) = $0 else { return nil }; return a }
        ) { CommentsReducer() }
        .reduce(action: action, state: &state)
    }
}
```

The parent only knows about `FeedAction.post(PostAction)` — it has no idea `CommentsAction` even exists.

---

## `initialState()` propagation

If a child reducer overrides `initialState()` to provide custom startup values (loading from a cache, injecting a default), `Scope` propagates that into the parent state automatically. It is not silently overwritten by `HomeState()`.

```swift
struct FeedReducer: ReducerType {
    func initialState() -> FeedState {
        // Load cached posts so the screen isn't empty on first render
        FeedState(posts: PostCache.load(), page: PostCache.lastPage())
    }
    func reduce(action: FeedAction, state: inout FeedState) { ... }
}
```

When `HomeReducer` is initialised, `Scope(state: \.feed) { FeedReducer() }.initialState()` returns a `HomeState` whose `feed` property comes from `FeedReducer.initialState()` — not from `FeedState()`.

This is important if you override `initialState()` on a child reducer — without Scope's propagation that override would be silently ignored by the parent.

---

## `combined(with:)`

Use `combined(with:)` when you want to split one large reducer into focused pieces that still **share the same Action and State types**. Neither piece is a sub-feature — they are just organised slices of the same concern.

```swift
// Same HomeAction and HomeState — just spread across two files
struct HomeFeedHandling: ReducerType {
    func reduce(action: HomeAction, state: inout HomeState) {
        guard case .feed(let a) = action else { return }
        // handle feed cases directly on HomeState
    }
}

struct HomeAnalyticsHandling: ReducerType {
    func reduce(action: HomeAction, state: inout HomeState) {
        // log every action, update analytics counters on HomeState
    }
}

struct HomeReducer: ReducerType {
    private let impl = HomeFeedHandling().combined(with: HomeAnalyticsHandling())

    func reduce(action: HomeAction, state: inout HomeState) {
        impl.reduce(action: action, state: &state)
    }
}
```

`HomeFeedHandling` runs first, then `HomeAnalyticsHandling` sees the already-mutated state. This ordering matters — analytics can read the final state after the feed handler has already applied its changes.

Chain as many as needed:

```swift
let pipeline = A().combined(with: B()).combined(with: C())
// runs: A → B → C
```

---

## `Scope` vs `combined(with:)` — when to use which

| Question | Answer |
|---|---|
| Does the sub-feature have its own independent `Action` and `State`? | Use `Scope` |
| Is it just an organisational split of the same types? | Use `combined(with:)` |
| Can this reducer be reused on a different screen? | It should use `Scope` — child reducers are portable |
| Do you want to test it without constructing parent state? | Use `Scope` — child reducers test in isolation |
| Does one piece need to see state *after* the other ran? | Use `combined(with:)` — first runs before second |
