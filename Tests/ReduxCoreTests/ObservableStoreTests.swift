//
//  ObservableStoreTests.swift
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

// ObservableStoreTests.swift
// Tests for ObservableStore: initialization, state sync, dispatch delegation.

import Testing
import ReduxCore

@Suite("ObservableStore")
@MainActor
struct ObservableStoreTests {

    // MARK: - Initialization

    @Test("initializes with the current state of the underlying Storable")
    func initMirrorsStorableState() {
        let storable = Storable(reducer: TestReducer())
        storable.dispatch(.setValue(7))
        let store = ObservableStore(store: storable)
        #expect(store.state.count == 7)
    }

    @Test("initializes with default state when Storable has no initial action")
    func initDefaultState() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)
        #expect(store.state == TestState())
    }

    // MARK: - State synchronisation via onStateChange

    @Test("state updates when the underlying Storable dispatches an action")
    func stateSyncsOnDispatch() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        storable.dispatch(.setValue(42))

        #expect(store.state.count == 42)
    }

    @Test("state reflects multiple sequential dispatches")
    func stateReflectsSequentialDispatches() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        storable.dispatch(.increment)
        storable.dispatch(.increment)
        storable.dispatch(.decrement)

        #expect(store.state.count == 1)
    }

    // MARK: - dispatch delegation

    @Test("dispatch forwards action to the underlying Storable")
    func dispatchForwardsAction() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        store.dispatch(.setValue(99))

        #expect(storable.state.count == 99)
    }

    @Test("dispatch updates observable state")
    func dispatchUpdatesObservableState() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        store.dispatch(.increment)

        #expect(store.state.count == 1)
    }

    @Test("multiple dispatches via ObservableStore accumulate correctly")
    func multipleDispatchesAccumulate() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        store.dispatch(.increment)
        store.dispatch(.increment)
        store.dispatch(.increment)
        store.dispatch(.decrement)

        #expect(store.state.count == 2)
    }

    // MARK: - Ownership

    @Test("ObservableStore state stays consistent with underlying Storable state")
    func storeAndStorableStateAreInSync() {
        let storable = Storable(reducer: TestReducer())
        let store = ObservableStore(store: storable)

        store.dispatch(.setValue(55))

        #expect(store.state == storable.state)
    }
}
