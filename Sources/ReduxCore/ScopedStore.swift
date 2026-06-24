//
//  ScopedStore.swift
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

/// A store scoped to a specific slice of a parent store's state.
///
/// `ScopedStore` lets child views subscribe only to the state they care about.
/// It re-renders only when the derived `ChildState` changes — not every time the
/// parent state changes — preventing unnecessary view updates across unrelated slices.
///
/// Create one via `ObservableStore.scope(state:action:)`:
///
///     let headerStore = store.scope(
///         state: \.headerState,
///         action: { .header(action: $0) }
///     )
///
/// Pass it to a child view and use it like any `ObservableStore`:
///
///     HeaderView(store: headerStore)
///
/// Inside `HeaderView`:
///
///     store.state       // HeaderHomeState
///     store.dispatch(.fetchItems)   // maps to HomeAction.header(action: .fetchItems)
@MainActor
@Observable
public final class ScopedStore<ParentReducer: ReducerType, ChildState: Equatable, ChildAction>
where ParentReducer.Action: Equatable & Sendable, ParentReducer.State: Equatable & Sendable {

    /// The current derived child state.
    public private(set) var state: ChildState

    private let parentStore: ObservableStore<ParentReducer>
    private let stateMapper: (ParentReducer.State) -> ChildState
    private let actionMapper: (ChildAction) -> ParentReducer.Action

    /// Token used to deregister this store's observer from the parent on deinit.
    /// `@ObservationIgnored` prevents the macro from transforming this into a computed
    /// property so that `nonisolated(unsafe)` applies to the actual backing store,
    /// allowing `deinit` (which runs outside actor isolation) to read it safely.
    @ObservationIgnored nonisolated(unsafe) private var observerID: UUID

    init(
        parent: ObservableStore<ParentReducer>,
        state stateMapper: @escaping (ParentReducer.State) -> ChildState,
        action actionMapper: @escaping (ChildAction) -> ParentReducer.Action
    ) {
        self.parentStore = parent
        self.stateMapper = stateMapper
        self.actionMapper = actionMapper
        self.state = stateMapper(parent.state)

        // Placeholder so all stored properties are initialized before `self` is
        // used in the closure below. Overwritten immediately with the real token.
        self.observerID = UUID()

        // Subscribe to parent state changes; only propagate when the derived
        // child state actually changes to avoid spurious re-renders.
        // The returned UUID lets deinit remove the closure, preventing a leak.
        self.observerID = parent.addScopedObserver { [weak self] parentState in
            guard let self else { return }
            let newChild = stateMapper(parentState)
            guard newChild != self.state else { return }
            self.state = newChild
        }
    }

    deinit {
        // Remove the observer from the parent so the closure is released
        // and the scopedObservers dictionary doesn't accumulate stale entries.
        parentStore.removeScopedObserver(observerID)
    }

    /// Dispatches a child action, mapping it to a parent action before forwarding.
    public func dispatch(_ action: ChildAction) {
        parentStore.dispatch(actionMapper(action))
    }
}
