//
//  TestHelpers.swift
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

// TestHelpers.swift
// Shared fixtures used across all ReduxCore test files.

import ReduxCore
import os

// MARK: - Minimal Action

enum TestAction: Actionable {
    case increment
    case decrement
    case reset
    case setValue(Int)
    case noop
}

// MARK: - Minimal State

struct TestState: Statable {
    var count: Int = 0
    var label: String = ""
}

// MARK: - Minimal Reducer

struct TestReducer: ReducerType {
    func initialState() -> TestState { TestState() }

    func reduce(action: TestAction, state: inout TestState) {
        switch action {
        case .increment:        state.count += 1
        case .decrement:        state.count -= 1
        case .reset:            state.count = 0
        case .setValue(let v):  state.count = v
        case .noop:             break
        }
    }
}

// MARK: - Thread-safe helpers for @Sendable closure captures

/// Thread-safe flag for use inside @Sendable closures.
/// Uses `OSAllocatedUnfairLock` for correct mutual exclusion across threads.
final class Flag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var value: Bool { lock.withLock { $0 } }
    func set() { lock.withLock { $0 = true } }
}

/// Simple thread-safe counter for use inside @Sendable closures.
/// Uses `OSAllocatedUnfairLock` for correct mutual exclusion across threads.
final class Counter: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    var count: Int { lock.withLock { $0 } }
    func increment() { lock.withLock { $0 += 1 } }
}

/// Thread-safe collection box for use inside @Sendable closures.
/// Uses `OSAllocatedUnfairLock` for correct mutual exclusion across threads.
final class Collector<T: Sendable>: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [T]())
    var values: [T] { lock.withLock { $0 } }
    func append(_ value: T) { lock.withLock { $0.append(value) } }
}

// MARK: - Spy Middleware

/// Records every action it sees and optionally forwards a response action.
/// Uses `OSAllocatedUnfairLock` so it is safe to use from concurrent middleware tasks.
final class SpyMiddleware: MiddlewareType, Sendable {
    private struct _State {
        var receivedActions: [TestAction] = []
        var receivedStates: [TestState] = []
    }
    private let lock = OSAllocatedUnfairLock(initialState: _State())

    var receivedActions: [TestAction] { lock.withLock { $0.receivedActions } }
    var receivedStates: [TestState]   { lock.withLock { $0.receivedStates } }

    /// If set, calls next() with this action instead of the incoming one.
    let nextAction: TestAction?

    init(nextAction: TestAction? = nil) {
        self.nextAction = nextAction
    }

    func process(
        action: TestAction,
        state: TestState,
        next: @escaping @Sendable (TestAction) async -> Void
    ) async {
        lock.withLock {
            $0.receivedActions.append(action)
            $0.receivedStates.append(state)
        }
        if let nextAction {
            await next(nextAction)
        }
    }
}

// MARK: - Passthrough Middleware

/// Calls next() with a fixed action every time.
struct PassthroughMiddleware: MiddlewareType, Sendable {
    let response: TestAction
    func process(
        action: TestAction,
        state: TestState,
        next: @escaping @Sendable (TestAction) async -> Void
    ) async {
        await next(response)
    }
}

// MARK: - Async Middleware

/// Waits for a configurable delay then calls next(), respecting task cancellation.
/// `delay` and `nextAction` are immutable after init; `didProcess` is guarded by a lock.
final class AsyncMiddleware: MiddlewareType, Sendable {
    let delay: Duration
    let nextAction: TestAction?
    private let _didProcess = OSAllocatedUnfairLock(initialState: false)
    var didProcess: Bool { _didProcess.withLock { $0 } }

    init(delay: Duration = .milliseconds(10), nextAction: TestAction? = nil) {
        self.delay = delay
        self.nextAction = nextAction
    }

    func process(
        action: TestAction,
        state: TestState,
        next: @escaping @Sendable (TestAction) async -> Void
    ) async {
        do {
            try await Task.sleep(for: delay)
        } catch {
            // Task was cancelled during sleep — bail out without side effects.
            return
        }
        guard !Task.isCancelled else { return }
        _didProcess.withLock { $0 = true }
        if let nextAction {
            await next(nextAction)
        }
    }
}
