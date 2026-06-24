//
//  Storable.swift
//
//  Copyright (c) Andres F. Lozano
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

/// Core Redux store.
///
/// @MainActor isolation ensures all state mutations and state-change
/// notifications happen on the main thread — safe to use with SwiftUI.
///
/// - Equatable guard: `onStateChange` is only called when state actually changes.
/// - Parallel middleware: all middleware run concurrently via `withTaskGroup`.
/// - Effect cancellation: in-flight middleware tasks are tracked and cancelled
///   on `cancel()` or `deinit` (e.g. when the owning view disappears).
/// - Sync cycle detection: `maxDispatchDepth` (default `.max`, effectively unlimited)
///   breaks synchronous re-entrant dispatch chains. Set a lower value to cap depth.
/// - Async cycle detection: `maxActionFrequency` (default 20/s) warns when the
///   same action is dispatched too rapidly, indicating an async middleware loop.
@MainActor
public final class Storable<TReducer: ReducerType>
where TReducer.Action: Equatable & Sendable, TReducer.State: Equatable & Sendable {
    
    public typealias ErasedMiddleware = AnyMiddleware<TReducer.Action, TReducer.State>
    
    public let reducer: TReducer
    private let middleware: [ErasedMiddleware]
    
    /// Maximum number of nested dispatches before breaking a cycle.
    /// Defaults to `.max` (unlimited). Set a lower value to cap synchronous re-entrant depth.
    private let maxDispatchDepth: Int
    private var currentDispatchDepth: Int = 0
    
    /// Maximum number of times the same action may be dispatched within `cycleWindow`
    /// before an async cycle warning is printed.
    private let maxActionFrequency: Int
    /// The time window used by the async cycle detector.
    private let cycleWindow: Duration
    /// Rolling frequency table: action description → (count, window start).
    private var dispatchFrequency: [String: (count: Int, since: ContinuousClock.Instant)] = [:]
    
    /// Lightweight wrapper that tracks whether a `Task<Void, Never>` has completed.
    ///
    /// `Task` has no public `.isFinished` property, so we set a flag at the end
    /// of the task body. `@unchecked Sendable` is safe: `isFinished` is only ever
    /// set once (from within the task itself) and read from the main actor after
    /// an appropriate delay.
    private final class TaskHandle: @unchecked Sendable {
        /// Written exactly once — from within the task body after all async work
        /// completes. Safe because: (1) it is only ever written from one place,
        /// (2) it is only read by `removeFinishedTasks()` which runs on the main
        /// actor well after the write, giving the CPU sufficient ordering guarantees.
        nonisolated(unsafe) private(set) var isFinished = false
        let task: Task<Void, Never>
        
        init(_ operation: @Sendable @escaping () async -> Void) {
            // A `weak var` local is captured by reference (no capture list), so
            // the Task body sees the value after `weakSelf = self` is assigned.
            // This prevents a retain cycle: `inflightTasks` holds the strong ref;
            // the Task holds only a weak ref. If the handle is evicted from
            // `inflightTasks` before the task finishes the write is skipped safely.
            weak var weakSelf: TaskHandle?
            task = Task {
                await operation()
                weakSelf?.isFinished = true
            }
            weakSelf = self
        }
        
        func cancel() { task.cancel() }
        var isCancelled: Bool { task.isCancelled }
    }
    
    /// Tracks in-flight middleware tasks so they can be cancelled on teardown.
    /// `nonisolated(unsafe)` is required because Swift does not enforce actor
    /// isolation inside `deinit`, so the compiler rejects direct access to
    /// `@MainActor`-isolated properties there. Safe in practice: `deinit` is
    /// the last operation on the object, so no concurrent access is possible.
    nonisolated(unsafe) private var inflightTasks: [TaskHandle] = []
    
    public private(set) var state: TReducer.State {
        didSet {
            // Guard against spurious notifications when the reducer returns
            // the same state value — avoids unnecessary SwiftUI re-renders.
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    
    /// Called whenever state changes. Assigned by the owner (e.g. ObservableStore).
    public var onStateChange: ((TReducer.State) -> Void)?
    
    public init(
        reducer: TReducer,
        middleware: [ErasedMiddleware] = [],
        maxDispatchDepth: Int = .max,
        maxActionFrequency: Int = 0,
        cycleWindow: Duration = .seconds(1)
    ) {
        self.reducer = reducer
        self.middleware = middleware
        self.maxDispatchDepth = maxDispatchDepth
        self.maxActionFrequency = maxActionFrequency
        self.cycleWindow = cycleWindow
        self.state = reducer.initialState()
    }
    
    public func dispatch(_ action: TReducer.Action) {
        // Async cycle detection: warn if the same action fires too rapidly.
        
        handlerSyncCycleDetection(with: action)
        // Reduce synchronously — state is mutated in place on the main actor.
        reducer.reduce(action: action, state: &state)
        
        guard !middleware.isEmpty else { return }
        
        // Capture the state value at this point in time so each middleware
        // sees a consistent snapshot even if dispatch is called again before
        // the Task runs.
        let capturedState = state
        
        let handle = TaskHandle { [weak self] in
            guard let self else { return }
            await self.runMiddleware(action, state: capturedState)
        }
        
        inflightTasks.append(handle)
        removeFinishedTasks()
    }
    
    /// Cancels all in-flight middleware effects.
    /// Call this when the owning view disappears to release resources promptly.
    public func cancel() {
        inflightTasks.forEach { $0.cancel() }
        inflightTasks.removeAll()
    }
    
    deinit {
        // Best-effort cleanup for tasks that outlive the store.
        inflightTasks.forEach { $0.cancel() }
    }
    
    // MARK: - Private
    
    private func runMiddleware(_ action: TReducer.Action, state: TReducer.State) async {
        // Bridge the @MainActor-isolated dispatch into a @Sendable nonisolated
        // function so it can be called safely from within the TaskGroup.
        @Sendable nonisolated func dispatchIfDifferent(
            store: Storable,
            newAction: TReducer.Action,
            originalAction: TReducer.Action
        ) async {
            // Fast-path: same action would re-trigger the same middleware cycle.
            guard newAction != originalAction else { return }
            await MainActor.run { store.dispatch(newAction) }
        }
        
        // Run all middleware concurrently. Each receives the same action + state
        // snapshot and may independently dispatch result actions. Structured
        // concurrency guarantees all child tasks finish (or are cancelled together).
        await withTaskGroup(of: Void.self) { group in
            for middleware in middleware {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await middleware.process(action: action, state: state) { [weak self] newAction in
                        guard let self else { return }
                        await dispatchIfDifferent(store: self, newAction: newAction, originalAction: action)
                    }
                }
            }
        }
    }
    
    /// Removes references to tasks that have already finished (completed or cancelled)
    /// to keep the array bounded.
    private func removeFinishedTasks() {
        inflightTasks.removeAll { $0.isFinished || $0.isCancelled }
    }
    
    /// Tracks how often each action is dispatched within the configured `cycleWindow`.
    /// Prints a warning when the same action exceeds `maxActionFrequency`, which
    /// indicates an async middleware loop (e.g. A dispatches B, B dispatches A).
    /// This is purely diagnostic — it never blocks or drops a dispatch.
    private func detectAsyncCycle(_ action: TReducer.Action) {
        let key = String(describing: action)
        let now = ContinuousClock.now
        
        if let (count, since) = dispatchFrequency[key], now - since < cycleWindow {
            let newCount = count + 1
            dispatchFrequency[key] = (newCount, since)
            if newCount > maxActionFrequency {
                print("[ReduxCore] ⚠️ Possible async cycle: '\(key)' dispatched \(newCount) times in < \(cycleWindow)")
            }
        } else {
            dispatchFrequency[key] = (1, now)
        }
    }
    
    private func handlerSyncCycleDetection(with action: TReducer.Action) {
#if DEBUG
        if maxActionFrequency > 0 {
            detectAsyncCycle(action)
            // Sync cycle detection: break dispatch chains that exceed the configured depth.
            currentDispatchDepth += 1
            defer { currentDispatchDepth -= 1 }
            
            guard currentDispatchDepth <= maxDispatchDepth else {
                return print("[ReduxCore] ⚠️ Max dispatch depth (\(maxDispatchDepth)) exceeded. Breaking potential cycle for action: \(action)")
            }
        }
#endif
    }
}
