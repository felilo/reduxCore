//
//  MiddlewareType.swift
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

// MARK: - MiddlewareType

/// A side-effect processor in the Redux pipeline.
///
/// Middlewares receive every dispatched action and the current state.
/// To produce a result (e.g. after a network call), dispatch a new action
/// via the `next` closure. The original action has already been reduced
/// before `process` is called.
public protocol MiddlewareType<Action, State>: Sendable {
    associatedtype Action
    associatedtype State

    func process(
        action: Action,
        state: State,
        next: @escaping @Sendable (Action) async -> Void
    ) async
}

// MARK: - TaskCancellationManager

/// Actor-isolated storage for cancellable tasks.
///
/// Thread-safe without requiring `@MainActor` on the conforming class,
/// so it can be used freely from any isolation context including
/// network or background middlewares.
public actor TaskCancellationManager {

    private var tasks: [String: Task<Void, Never>] = [:]

    public init() {}

    /// Runs `operation` under `key`, cancelling any previously registered
    /// in-flight task with that key before starting.
    /// Cancellation is checked before the operation body runs.
    public func run(
        key: String,
        priority: TaskPriority? = nil,
        _ operation: @Sendable @escaping () async -> Void
    ) {
        tasks[key]?.cancel()
        let task = Task(priority: priority) {
            guard !Task.isCancelled else { return }
            await operation()
        }
        tasks[key] = task
    }

    /// Cancels a single task registered under `key`.
    public func cancel(key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    /// Cancels all in-flight tasks.
    public func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

// MARK: - CancellableTask

/// Provides automatic task cancellation keyed by a string identifier.
///
/// When `run(key:_:)` is called with the same key as a previous in-flight
/// task, the previous task is cancelled before the new one starts.
/// Useful for search-as-you-type, debounced fetches, etc.
///
/// Conforming types must provide a `TaskCancellationManager` instance.
/// The manager is actor-isolated, so conforming classes do NOT need
/// to be `@MainActor`-isolated — any isolation context is supported.
public protocol CancellableTask: AnyObject {
    var taskManager: TaskCancellationManager { get }
}

extension CancellableTask {

    /// Runs `operation`, cancelling any previously running task registered under `key`.
    public func run(
        key: String,
        priority: TaskPriority? = nil,
        _ operation: @Sendable @escaping () async -> Void
    ) async {
        await taskManager.run(key: key, priority: priority, operation)
    }

    /// Cancels a single task registered under `key`.
    public func cancel(key: String) async {
        await taskManager.cancel(key: key)
    }

    /// Cancels all in-flight tasks managed by this instance.
    public func cancelAll() async {
        await taskManager.cancelAll()
    }
}

// MARK: - AnyMiddleware (Type Erasure)

/// Type-erased wrapper that allows storing heterogeneous MiddlewareType
/// values in a homogeneous array.
public final class AnyMiddleware<Action, State>: @unchecked Sendable {
    private let _handler: @Sendable (Action, State, @escaping @Sendable (Action) async -> Void) async -> Void

    public init<M: MiddlewareType>(_ middleware: M) where M.Action == Action, M.State == State {
        self._handler = { action, state, next in
            await middleware.process(action: action, state: state, next: next)
        }
    }

    public func process(
        action: Action,
        state: State,
        next: @escaping @Sendable (Action) async -> Void
    ) async {
        await _handler(action, state, next)
    }
}
