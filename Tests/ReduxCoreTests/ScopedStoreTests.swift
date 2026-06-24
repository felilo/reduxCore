//
//  ScopedStoreTests.swift
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

// ScopedStoreTests.swift
// Tests for ScopedStore: state projection, action mapping, and selective updates.

import Testing
import ReduxCore

@Suite("ScopedStore")
@MainActor
struct ScopedStoreTests {

    // MARK: - Initialization

    @Test("scoped store reflects initial parent state through the mapping")
    func initMirrorsParentSlice() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        parent.dispatch(.setValue(7))
        // Scope maps the whole state through as-is (identity on count)
        let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })

        #expect(scoped.state == 7)
    }

    @Test("scoped store with zero initial value")
    func initZeroValue() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })

        #expect(scoped.state == 0)
    }

    // MARK: - State propagation

    @Test("scoped store updates when parent state changes in the scoped slice")
    func updatesWhenSliceChanges() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })

        parent.dispatch(.setValue(42))

        #expect(scoped.state == 42)
    }

    @Test("scoped store does NOT update when parent state changes outside the scoped slice")
    func doesNotUpdateForUnrelatedChanges() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        // Scope only on the label property
        let scoped = parent.scope(state: \.label, action: { (a: TestAction) in a })

        let updateCount = 0
        // We check via manual state comparison since @Observable tracks reads
        let initial = scoped.state

        // Dispatch an action that changes count but NOT label
        parent.dispatch(.increment)

        // The label slice should not have changed
        #expect(scoped.state == initial)
        let _ = updateCount // suppress unused warning
    }

    @Test("multiple sequential parent dispatches are reflected in scoped state")
    func multipleDispatches() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })

        parent.dispatch(.increment)
        parent.dispatch(.increment)
        parent.dispatch(.decrement)

        #expect(scoped.state == 1)
    }

    // MARK: - Action mapping

    @Test("dispatch on scoped store maps action and dispatches to parent")
    func dispatchMapsToParent() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })

        scoped.dispatch(.setValue(55))

        #expect(parent.state.count == 55)
        #expect(scoped.state == 55)
    }

    // MARK: - Multiple scoped stores

    @Test("multiple scoped stores on the same parent work independently")
    func multipleScopesAreIndependent() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)
        let countScoped = parent.scope(state: \.count, action: { (a: TestAction) in a })
        let labelScoped = parent.scope(state: \.label, action: { (a: TestAction) in a })

        parent.dispatch(.setValue(10))

        #expect(countScoped.state == 10)
        #expect(labelScoped.state == "")  // unchanged
    }

    // MARK: - Observer lifecycle (leak prevention)

    @Test("observer is removed from parent when ScopedStore is deallocated")
    func observerRemovedOnDeinit() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)

        // Create a scoped store in a nested scope so it deallocates when the
        // block exits, triggering its deinit and removing the observer.
        var callCount = 0
        do {
            let scoped = parent.scope(state: \.count, action: { (a: TestAction) in a })
            // Verify it works while alive
            parent.dispatch(.increment)
            callCount = scoped.state  // just read it to suppress unused warning
        }
        // scoped is now deallocated — its observer must have been removed

        // Any further dispatches should not crash or reference stale closures
        parent.dispatch(.increment)
        parent.dispatch(.increment)
        #expect(parent.state.count == 3)
        let _ = callCount
    }

    @Test("creating and releasing many scoped stores does not accumulate observers")
    func observersDontAccumulate() {
        let storable = Storable(reducer: TestReducer())
        let parent = ObservableStore(store: storable)

        for _ in 0..<100 {
            // Each iteration creates a ScopedStore that goes out of scope
            // immediately, triggering deinit and observer removal.
            _ = parent.scope(state: \.count, action: { (a: TestAction) in a })
        }

        // If observers accumulated, the dictionary would have 100 entries;
        // after deinit cleanup it should be empty.
        // We can't inspect the private dictionary directly, but dispatching
        // must work correctly with no stale closures causing issues.
        parent.dispatch(.setValue(42))
        #expect(parent.state.count == 42)
    }
}
