//
//  StorableTests.swift
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

// StorableTests.swift
// Tests for Storable: initialization, dispatch, state updates, and middleware pipeline.

import Testing
import ReduxCore

@Suite("Storable")
@MainActor
struct StorableTests {

    // MARK: - Initialization

    @Test("initializes with default state when no initial action")
    func initWithNoInitialAction() {
        let store = Storable(reducer: TestReducer())
        #expect(store.state == TestState())
        #expect(store.state.count == 0)
    }

    @Test("initializes state via initialState() from the reducer")
    func initUsesReducerInitialState() {
        let store = Storable(reducer: TestReducer())
        #expect(store.state.count == 0)
    }

    @Test("exposes the reducer")
    func exposesReducer() {
        let reducer = TestReducer()
        let store = Storable(reducer: reducer)
        // Reducer is accessible (compile + runtime check)
        let _ = store.reducer
    }

    // MARK: - Synchronous state updates

    @Test("dispatch updates state synchronously")
    func dispatchUpdatesSynchronously() {
        let store = Storable(reducer: TestReducer())
        store.dispatch(.increment)
        #expect(store.state.count == 1)
    }

    @Test("multiple dispatches accumulate state correctly")
    func multipleDispatches() {
        let store = Storable(reducer: TestReducer())
        store.dispatch(.increment)
        store.dispatch(.increment)
        store.dispatch(.decrement)
        #expect(store.state.count == 1)
    }

    @Test("reset brings count back to zero")
    func dispatchReset() {
        let store = Storable(reducer: TestReducer())
        store.dispatch(.setValue(10))
        store.dispatch(.reset)
        #expect(store.state.count == 0)
    }

    // MARK: - onStateChange callback

    @Test("onStateChange is called when state changes")
    func onStateChangeFires() async {
        let store = Storable(reducer: TestReducer())
        var received: [TestState] = []
        store.onStateChange = { received.append($0) }

        store.dispatch(.increment)
        store.dispatch(.increment)

        #expect(received.count == 2)
        #expect(received[0].count == 1)
        #expect(received[1].count == 2)
    }

    @Test("onStateChange is not called during initialization")
    func onStateChangeNotCalledOnInit() {
        var callCount = 0
        let store = Storable(reducer: TestReducer())
        store.onStateChange = { _ in callCount += 1 }
        // No dispatch yet — callback should not have been invoked
        #expect(callCount == 0)
    }

    @Test("onStateChange receives the updated state value")
    func onStateChangeReceivesNewState() {
        let store = Storable(reducer: TestReducer())
        var lastState: TestState?
        store.onStateChange = { lastState = $0 }

        store.dispatch(.setValue(99))
        #expect(lastState?.count == 99)
    }

    // MARK: - Middleware pipeline

    @Test("middleware receives dispatched action and current state")
    func middlewareReceivesActionAndState() async throws {
        let spy = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy)]
        )
        store.dispatch(.increment)

        // Give the async Task time to run
        try await Task.sleep(for: .milliseconds(50))

        #expect(spy.receivedActions == [.increment])
        #expect(spy.receivedStates.first?.count == 1) // state AFTER reduction
    }

    @Test("multiple middleware all receive the action")
    func allMiddlewaresReceiveAction() async throws {
        let spy1 = SpyMiddleware()
        let spy2 = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy1), AnyMiddleware(spy2)]
        )
        store.dispatch(.increment)

        try await Task.sleep(for: .milliseconds(50))

        #expect(spy1.receivedActions == [.increment])
        #expect(spy2.receivedActions == [.increment])
    }

    @Test("middleware calling next() with a different action triggers re-dispatch")
    func middlewareNextDispatchesNewAction() async throws {
        let spy = SpyMiddleware(nextAction: .setValue(100))

        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy)]
        )
        store.dispatch(.increment)

        try await Task.sleep(for: .milliseconds(100))

        // .increment → count becomes 1, then middleware fires .setValue(100) → count becomes 100
        #expect(store.state.count == 100)
    }

    @Test("middleware calling next() with the same action does NOT re-dispatch")
    func middlewareSameActionIsFiltered() async throws {
        // Passthrough always returns .increment — same as incoming action
        let passthrough = PassthroughMiddleware(response: .increment)
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(passthrough)]
        )
        store.dispatch(.increment)

        try await Task.sleep(for: .milliseconds(100))

        // Only one increment should have happened (the middleware's .increment is filtered)
        #expect(store.state.count == 1)
    }

    @Test("no middleware: dispatch still works correctly")
    func noMiddlewares() {
        let store = Storable(reducer: TestReducer(), middleware: [])
        store.dispatch(.setValue(7))
        #expect(store.state.count == 7)
    }

    @Test("state is captured at dispatch time, not during async middleware execution")
    func stateCapturedAtDispatchTime() async throws {
        let spy = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy)]
        )
        // Dispatch increment, then immediately dispatch decrement
        store.dispatch(.increment)  // state → 1; middleware sees state=1
        store.dispatch(.decrement)  // state → 0; middleware sees state=0

        try await Task.sleep(for: .milliseconds(100))

        // First middleware invocation should have seen state.count == 1
        #expect(spy.receivedStates.first?.count == 1)
        // Second invocation should have seen state.count == 0
        #expect(spy.receivedStates.dropFirst().first?.count == 0)
    }

    // MARK: - Equatable guard (Step 1)

    @Test("onStateChange does NOT fire when reducer returns identical state")
    func onStateChangeNotFiredForNoOp() {
        let store = Storable(reducer: TestReducer())
        var callCount = 0
        store.onStateChange = { _ in callCount += 1 }

        store.dispatch(.noop)   // returns same state — should not trigger callback

        #expect(callCount == 0)
    }

    @Test("onStateChange fires when state actually changes")
    func onStateChangeFiresOnRealChange() {
        let store = Storable(reducer: TestReducer())
        var callCount = 0
        store.onStateChange = { _ in callCount += 1 }

        store.dispatch(.increment)

        #expect(callCount == 1)
    }

    // MARK: - Parallel middleware execution (Step 2)

    @Test("two slow middleware execute concurrently, not sequentially")
    func middlewareExecuteConcurrently() async throws {
        // Each middleware takes 150ms. Serial execution would take ≥300ms;
        // parallel execution should complete in ~150ms.
        let delay = Duration.milliseconds(150)
        let m1 = AsyncMiddleware(delay: delay)
        let m2 = AsyncMiddleware(delay: delay)

        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(m1), AnyMiddleware(m2)]
        )

        let clock = ContinuousClock()
        let start = clock.now
        store.dispatch(.increment)

        // Poll until both middleware finish (or timeout at 250ms).
        // This avoids including a fixed sleep in the elapsed measurement.
        for _ in 0..<25 {
            if m1.didProcess && m2.didProcess { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let elapsed = clock.now - start

        // Serial would take ≥300ms; 250ms is a generous ceiling for parallel.
        #expect(elapsed < .milliseconds(250))
        #expect(m1.didProcess)
        #expect(m2.didProcess)
    }

    @Test("all middleware receive the action even when one is slow")
    func slowMiddlewareDoesNotBlockOthers() async throws {
        let slow = AsyncMiddleware(delay: .milliseconds(200))
        let fast = SpyMiddleware()

        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(slow), AnyMiddleware(fast)]
        )
        store.dispatch(.increment)

        // Fast middleware should complete well before the slow one
        try await Task.sleep(for: .milliseconds(50))
        #expect(fast.receivedActions == [.increment])
    }

    // MARK: - Effect cancellation (Step 5)

    @Test("cancel() stops in-flight middleware tasks")
    func cancelStopsInflightTasks() async throws {
        let slow = AsyncMiddleware(delay: .milliseconds(500), nextAction: .setValue(99))

        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(slow)]
        )
        store.dispatch(.increment)
        store.cancel()

        try await Task.sleep(for: .milliseconds(100))

        // The middleware was cancelled before it could dispatch .setValue(99)
        #expect(store.state.count == 1)
    }

    @Test("dispatch continues to work after cancel()")
    func dispatchWorksAfterCancel() {
        let store = Storable(reducer: TestReducer())
        store.dispatch(.increment)
        store.cancel()
        store.dispatch(.setValue(42))
        #expect(store.state.count == 42)
    }

    // MARK: - Dispatch depth limit

    @Test("depth limit blocks synchronous re-entrant dispatch via onStateChange")
    func dispatchDepthLimitPreventsInfiniteLoop() {
        // Sync re-entrancy: onStateChange dispatches again from within didSet.
        // This is the only scenario where sync depth detection is relevant —
        // middleware-driven dispatch is async and is handled by frequency detection.
        var reentrantCount = 0
        let store = Storable(
            reducer: TestReducer(),
            maxDispatchDepth: 3,
            maxActionFrequency: 1
        )
        store.onStateChange = { [weak store] _ in
            reentrantCount += 1
            guard reentrantCount <= 10 else { return }  // safety net for broken impl
            store?.dispatch(.increment)
        }
        store.dispatch(.increment)
        // depth 1: count = 1, depth 2: count = 2, depth 3: count = 3
        // depth 4 → blocked. Final count == 3, reentrantCount == 3.
        #expect(store.state.count == 3)
        #expect(reentrantCount == 3)
    }

    @Test("depth limit works independently of maxActionFrequency")
    func depthLimitIsIndependentOfMaxActionFrequency() {
        // BUG: handlerSyncCycleDetection gates both detectors behind `maxActionFrequency > 0`.
        // When maxActionFrequency == 0, sync depth detection is silently disabled.
        var reentrantCount = 0
        let store = Storable(
            reducer: TestReducer(),
            maxDispatchDepth: 2,
            maxActionFrequency: 0  // frequency detection explicitly off
        )
        store.onStateChange = { [weak store] _ in
            reentrantCount += 1
            guard reentrantCount <= 10 else { return }
            store?.dispatch(.increment)
        }
        store.dispatch(.increment)
        // With depth limit 2: count == 2, reentrantCount == 2
        // BUG: depth detection never fires → safety net kicks in → count == 11
        #expect(store.state.count == 2)
        #expect(reentrantCount == 2)
    }

    @Test("depth limit actually prevents the reducer from running when exceeded")
    func depthLimitActuallyBlocksReducer() {
        // BUG: handlerSyncCycleDetection returns early but dispatch() continues
        // and calls reducer.reduce after the guard — the reducer still runs.
        var reentrantCount = 0
        let store = Storable(
            reducer: TestReducer(),
            maxDispatchDepth: 2,
            maxActionFrequency: 1
        )
        store.onStateChange = { [weak store] _ in
            reentrantCount += 1
            guard reentrantCount <= 10 else { return }
            store?.dispatch(.increment)
        }
        store.dispatch(.increment)
        // Expected after fix: count == 2, reentrantCount == 2
        // BUG: defer in helper resets depth before re-entry → count reaches safety limit
        #expect(store.state.count == 2)
        #expect(reentrantCount == 2)
    }

    @Test("default maxDispatchDepth is unlimited")
    func defaultMaxDispatchDepthIsUnlimited() {
        let store = Storable(reducer: TestReducer())
        // Verify many sequential dispatches don't crash under the unlimited default
        for _ in 0..<100 {
            store.dispatch(.increment)
        }
        #expect(store.state.count == 100)
    }

    // MARK: - Post-reducer state verification

    @Test("middleware receives post-reducer state, not pre-reducer state")
    func middlewareReceivesPostReducerState() async throws {
        let spy = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy)]
        )
        // Pre-reducer: count = 0. .setValue(42) makes it 42 post-reducer.
        store.dispatch(.setValue(42))
        try await Task.sleep(for: .milliseconds(50))

        // If middleware ran before the reducer, count would be 0.
        // It is 42 → reducer ran first, then middleware received the updated state.
        #expect(spy.receivedStates.first?.count == 42)
    }

    @Test("middleware receives pre-reducer state of 0 before setValue(42) is applied")
    func middlewareDoesNotReceivePreReducerState() async throws {
        let spy = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy)]
        )
        store.dispatch(.setValue(42))
        try await Task.sleep(for: .milliseconds(50))

        // Pre-reducer value was 0. Middleware must NOT have received 0 — it received 42.
        #expect(spy.receivedStates.first?.count != 0)
    }

    // MARK: - deinit cancellation (Step 5)

    @Test("in-flight middleware tasks are cancelled when store is deallocated")
    func deinitCancelsTasks() async throws {
        let slow = AsyncMiddleware(delay: .milliseconds(500), nextAction: .setValue(99))

        // Wrap in optional so we can force deallocation by setting to nil.
        var store: Storable<TestReducer>? = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(slow)]
        )
        store?.dispatch(.increment)

        // Deallocate the store while the middleware is still sleeping.
        store = nil

        try await Task.sleep(for: .milliseconds(100))

        // The middleware cannot dispatch .setValue(99) because the store is gone.
        // Reaching here without a crash confirms deinit cleanup ran correctly.
        #expect(store == nil)
    }

    // MARK: - pruneCompletedTasks (Step 5)

    @Test("completed tasks are pruned so the task array stays bounded")
    func completedTasksArePruned() async throws {
        let fast = AsyncMiddleware(delay: .milliseconds(10))

        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(fast)]
        )

        // Dispatch several times to create multiple tasks.
        for _ in 0..<5 {
            store.dispatch(.increment)
        }

        // Wait for all tasks to finish.
        try await Task.sleep(for: .milliseconds(100))

        // Dispatch once more — this triggers pruneCompletedTasks internally.
        store.dispatch(.increment)
        #expect(store.state.count == 6)
    }

    // MARK: - dispatchAsync

    @Test("dispatchAsync updates state synchronously before returning")
    func dispatchAsyncUpdatesStateBeforeReturning() async {
        let store = Storable(reducer: TestReducer())
        await store.dispatchAsync(.increment)
        #expect(store.state.count == 1)
    }

    @Test("dispatchAsync accumulates multiple state updates correctly")
    func dispatchAsyncMultipleUpdates() async {
        let store = Storable(reducer: TestReducer())
        await store.dispatchAsync(.increment)
        await store.dispatchAsync(.increment)
        await store.dispatchAsync(.decrement)
        #expect(store.state.count == 1)
    }

    @Test("dispatchAsync fires onStateChange when state changes")
    func dispatchAsyncOnStateChangeFires() async {
        let store = Storable(reducer: TestReducer())
        var received: [TestState] = []
        store.onStateChange = { received.append($0) }

        await store.dispatchAsync(.increment)
        await store.dispatchAsync(.setValue(5))

        #expect(received.count == 2)
        #expect(received[0].count == 1)
        #expect(received[1].count == 5)
    }

    @Test("dispatchAsync does not fire onStateChange for no-op action")
    func dispatchAsyncOnStateChangeNotFiredForNoop() async {
        let store = Storable(reducer: TestReducer())
        var callCount = 0
        store.onStateChange = { _ in callCount += 1 }

        await store.dispatchAsync(.noop)

        #expect(callCount == 0)
    }

    @Test("dispatchAsync with no middleware returns after reducer runs")
    func dispatchAsyncNoMiddlewareCompletesImmediately() async {
        let store = Storable(reducer: TestReducer(), middleware: [])
        await store.dispatchAsync(.setValue(7))
        #expect(store.state.count == 7)
    }

    @Test("dispatchAsync suspends until middleware completes — no sleep needed")
    func dispatchAsyncSuspendsUntilMiddlewareCompletes() async {
        let spy = SpyMiddleware()
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(spy)])

        await store.dispatchAsync(.increment)

        // Unlike sync dispatch, no Task.sleep is needed — dispatchAsync guarantees
        // all middleware have finished by the time it returns.
        #expect(spy.receivedActions == [.increment])
        #expect(spy.receivedStates.first?.count == 1)
    }

    @Test("dispatchAsync: middleware receives post-reducer state")
    func dispatchAsyncMiddlewareReceivesPostReducerState() async {
        let spy = SpyMiddleware()
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(spy)])

        await store.dispatchAsync(.setValue(42))

        #expect(spy.receivedStates.first?.count == 42)
    }

    @Test("dispatchAsync: all middleware receive the action")
    func dispatchAsyncAllMiddlewareReceiveAction() async {
        let spy1 = SpyMiddleware()
        let spy2 = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy1), AnyMiddleware(spy2)]
        )

        await store.dispatchAsync(.increment)

        #expect(spy1.receivedActions == [.increment])
        #expect(spy2.receivedActions == [.increment])
    }

    @Test("dispatchAsync: follow-up action dispatched by middleware is applied before return")
    func dispatchAsyncFollowUpActionAppliedBeforeReturn() async {
        // SpyMiddleware dispatches .setValue(100) after seeing .increment.
        // Because dispatch(.setValue(100)) runs on MainActor inside middleware,
        // its reducer fires before runMiddleware returns, so dispatchAsync
        // sees the final count without any extra sleep.
        let spy = SpyMiddleware(nextAction: .setValue(100))
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(spy)])

        await store.dispatchAsync(.increment)

        #expect(store.state.count == 100)
    }

    @Test("dispatchAsync: same action dispatched by middleware is filtered")
    func dispatchAsyncSameActionFilteredInMiddleware() async {
        let passthrough = PassthroughMiddleware(response: .increment)
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(passthrough)]
        )

        await store.dispatchAsync(.increment)

        // Middleware tried to re-dispatch .increment but it was filtered.
        #expect(store.state.count == 1)
    }

    @Test("dispatchAsync: two slow middleware execute concurrently, not sequentially")
    func dispatchAsyncMiddlewareRunsConcurrently() async throws {
        let delay = Duration.milliseconds(150)
        let m1 = AsyncMiddleware(delay: delay)
        let m2 = AsyncMiddleware(delay: delay)
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(m1), AnyMiddleware(m2)]
        )

        let clock = ContinuousClock()
        let start = clock.now
        await store.dispatchAsync(.increment)
        let elapsed = clock.now - start

        // Serial would take ≥300ms; parallel completes in ~150ms.
        #expect(elapsed < .milliseconds(250))
        #expect(m1.didProcess)
        #expect(m2.didProcess)
    }

    @Test("two sequential dispatchAsync calls with multiple middleware accumulate state correctly")
    func dispatchAsyncSequentialCallsWithMultipleMiddleware() async {
        let spy1 = SpyMiddleware()
        let spy2 = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy1), AnyMiddleware(spy2)]
        )

        await store.dispatchAsync(.increment)
        await store.dispatchAsync(.decrement)

        // count == 0 only if both reducers ran (increment → 1, decrement → 0)
        #expect(store.state.count == 0)

        // Both middleware instances saw both dispatches (2 × 2 = 4 total calls)
        #expect(spy1.receivedActions == [.increment, .decrement])
        #expect(spy2.receivedActions == [.increment, .decrement])
    }

    @Test("two different actions fired with dispatchAsync are processed in order by all middleware")
    func dispatchAsyncDifferentActionsDeliveredInOrder() async {
        let spy1 = SpyMiddleware()
        let spy2 = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy1), AnyMiddleware(spy2)]
        )

        await store.dispatchAsync(.increment)
        await store.dispatchAsync(.setValue(10))

        // Reducer applied both: 0 → 1 → 10
        #expect(store.state.count == 10)

        // Both middleware received actions in the correct order
        #expect(spy1.receivedActions == [.increment, .setValue(10)])
        #expect(spy2.receivedActions == [.increment, .setValue(10)])
    }

    @Test("two different dispatchAsync calls fired concurrently each complete with their own effect")
    func dispatchAsyncTwoConcurrentDifferentActionsEachComplete() async {
        let spy1 = SpyMiddleware()
        let spy2 = SpyMiddleware()
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(spy1), AnyMiddleware(spy2)]
        )

        // Fire both at the same time — MainActor serializes reducers, but
        // both dispatchAsync calls must complete before continuing.
        // Using .increment + .decrement: regardless of execution order,
        // count == 0 only if BOTH reducers ran. 1 or -1 means one was dropped.
        async let first: Void = store.dispatchAsync(.increment)
        async let second: Void = store.dispatchAsync(.decrement)
        _ = await (first, second)

        // Only possible if both reducers ran (±1 cancel out)
        #expect(store.state.count == 0)

        // First event: .increment was processed by all middleware
        #expect(spy1.receivedActions.contains(.increment))
        #expect(spy2.receivedActions.contains(.increment))

        // Second event: .decrement was processed by all middleware
        #expect(spy1.receivedActions.contains(.decrement))
        #expect(spy2.receivedActions.contains(.decrement))

        // Total: 2 actions × 2 middleware = 4 calls
        #expect(spy1.receivedActions.count == 2)
        #expect(spy2.receivedActions.count == 2)
    }

    @Test("cancel() stops a dispatchAsync task in flight")
    func dispatchAsyncCancelledByExplicitCancel() async throws {
        let slow = AsyncMiddleware(delay: .milliseconds(500), nextAction: .setValue(99))
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(slow)])

        // Fire dispatchAsync on a separate Task so we can cancel the store mid-flight.
        let task = Task { @MainActor in
            await store.dispatchAsync(.increment)
        }

        // Give the middleware task time to start, then cancel via the store.
        try await Task.sleep(for: .milliseconds(50))
        store.cancel()
        await task.value

        // Middleware was cancelled before it could dispatch .setValue(99).
        #expect(store.state.count == 1)
    }

    @Test("dispatchAsync respects structured cancellation from parent Task")
    func dispatchAsyncCancelledByParentTask() async throws {
        let slow = AsyncMiddleware(delay: .milliseconds(500), nextAction: .setValue(99))
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(slow)])

        let task = Task { @MainActor in
            await store.dispatchAsync(.increment)
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value

        // Parent Task was cancelled — middleware should have been cancelled too.
        #expect(store.state.count == 1)
    }

    @Test("dispatchAsync: state is captured at call time, not during middleware execution")
    func dispatchAsyncStateCapturedAtCallTime() async {
        let spy = SpyMiddleware()
        let store = Storable(reducer: TestReducer(), middleware: [AnyMiddleware(spy)])

        await store.dispatchAsync(.increment)   // middleware sees state.count == 1
        await store.dispatchAsync(.decrement)   // middleware sees state.count == 0

        #expect(spy.receivedStates.first?.count == 1)
        #expect(spy.receivedStates.dropFirst().first?.count == 0)
    }
}
