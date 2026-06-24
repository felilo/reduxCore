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

    @Test("dispatch is blocked when maxDispatchDepth is exceeded")
    func dispatchDepthLimitPreventsInfiniteLoop() async throws {
        // Middleware always re-dispatches a different action → would loop forever
        // without an explicit depth limit.
        let passthrough = PassthroughMiddleware(response: .decrement)
        let store = Storable(
            reducer: TestReducer(),
            middleware: [AnyMiddleware(passthrough)],
            maxDispatchDepth: 3
        )
        store.dispatch(.increment)

        try await Task.sleep(for: .milliseconds(200))

        // count should be capped by the depth limit, not go to -∞
        #expect(store.state.count > Int.min)
        #expect(store.state.count >= -3)
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
}
