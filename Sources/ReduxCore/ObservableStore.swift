//
//  ObservableStore.swift
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

import Foundation
import Observation

/// SwiftUI-observable wrapper around Storable.
///
/// Both this class and Storable are @MainActor-isolated, so state updates
/// reach the @Observable property without any extra dispatch hops.
@MainActor
@Observable
public final class ObservableStore<TReducer: ReducerType>
where TReducer.Action: Equatable & Sendable, TReducer.State: Equatable & Sendable {

    public private(set) var state: TReducer.State

    private let store: Storable<TReducer>

    /// Keyed observers registered by ScopedStore instances.
    /// Using a dictionary allows O(1) removal when a ScopedStore is deallocated,
    /// preventing unbounded growth of stale closures.
    /// `@ObservationIgnored` prevents the macro from transforming this into a computed
    /// property so that `nonisolated(unsafe)` applies to the actual backing store,
    /// allowing `removeScopedObserver` (called from `ScopedStore.deinit`, which is
    /// nonisolated) to mutate it safely. All writes otherwise happen on @MainActor.
    @ObservationIgnored nonisolated(unsafe) private var scopedObservers: [UUID: (TReducer.State) -> Void] = [:]

    public init(store: Storable<TReducer>) {
        self.state = store.state
        self.store = store

        store.onStateChange = { [weak self] newState in
            self?.state = newState
            self?.scopedObservers.values.forEach { $0(newState) }
        }
    }

    public func dispatch(_ action: TReducer.Action) {
        store.dispatch(action)
    }

    /// Cancels all in-flight middleware effects.
    /// The store also cancels automatically in `deinit` when the owning view
    /// is permanently removed from the hierarchy (e.g. popped off a navigation stack).
    /// Call this explicitly only when you need eager teardown before deallocation.
    public func cancel() {
        store.cancel()
    }

    /// Registers an observer called whenever state changes. Returns a token
    /// that must be passed to `removeScopedObserver(_:)` on deregistration.
    /// Used internally by ScopedStore.
    internal func addScopedObserver(_ observer: @escaping (TReducer.State) -> Void) -> UUID {
        let id = UUID()
        scopedObservers[id] = observer
        return id
    }

    /// Removes the observer registered under `id`, releasing the closure.
    /// Called by ScopedStore on deinit. `nonisolated` so it can be invoked
    /// from `deinit` without an actor context.
    nonisolated internal func removeScopedObserver(_ id: UUID) {
        scopedObservers.removeValue(forKey: id)
    }

    /// Creates a scoped store observing a derived slice of this store's state,
    /// mapping child actions back to parent actions.
    ///
    /// The scoped store only updates when the derived child state changes
    /// (guarded by `Equatable`), preventing unnecessary re-renders in child views.
    ///
    /// Usage:
    ///     let headerStore = store.scope(
    ///         state: \.headerState,
    ///         action: { .header(action: $0) }
    ///     )
    public func scope<ChildState: Equatable, ChildAction>(
        state toChildState: @escaping (TReducer.State) -> ChildState,
        action fromChildAction: @escaping (ChildAction) -> TReducer.Action
    ) -> ScopedStore<TReducer, ChildState, ChildAction> {
        ScopedStore(parent: self, state: toChildState, action: fromChildAction)
    }
}
