//
//  ScopeTests.swift
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

// ScopeTests.swift
// Tests for Scope and CombinedReducer.

import Testing
import ReduxCore

// MARK: - Fixtures

/// A minimal child action/state/reducer used only in these tests.
private enum ChildAction: Actionable {
    case increment
    case reset
}

private struct ChildState: Statable {
    var count: Int = 0
}

private struct ChildReducer: ReducerType {
    func reduce(action: ChildAction, state: inout ChildState) {
        switch action {
        case .increment: state.count += 1
        case .reset:     state.count = 0
        }
    }
}

/// A parent action that wraps both TestAction (own) and ChildAction (child).
private enum ParentAction: Actionable {
    case own(TestAction)
    case child(ChildAction)
}

private struct ParentState: Statable {
    var ownCount: Int  = 0
    var childState: ChildState = .init()
}

// MARK: - Scope tests

@Suite("Scope")
struct ScopeTests {

    // MARK: Routing

    @Test("child action is routed to child reducer via Scope")
    func childActionRoutedToChild() {
        var state = ParentState()

        Scope(state: \ParentState.childState,
              action: { (a: ParentAction) -> ChildAction? in
                  guard case .child(let c) = a else { return nil }; return c
              }) {
            ChildReducer()
        }
        .reduce(action: .child(.increment), state: &state)

        #expect(state.childState.count == 1)
        #expect(state.ownCount == 0)   // parent untouched
    }

    @Test("non-child action is ignored by Scope")
    func nonChildActionIgnored() {
        var state = ParentState()
        state.childState.count = 5

        Scope(state: \ParentState.childState,
              action: { (a: ParentAction) -> ChildAction? in
                  guard case .child(let c) = a else { return nil }; return c
              }) {
            ChildReducer()
        }
        .reduce(action: .own(.increment), state: &state)

        // Scope returns early because actionMap returns nil for .own
        #expect(state.childState.count == 5)
    }

    @Test("multiple dispatches accumulate in child slice")
    func multipleDispatchesAccumulate() {
        var state = ParentState()
        let scope = Scope(
            state: \ParentState.childState,
            action: { (a: ParentAction) -> ChildAction? in
                guard case .child(let c) = a else { return nil }; return c
            }
        ) { ChildReducer() }

        scope.reduce(action: .child(.increment), state: &state)
        scope.reduce(action: .child(.increment), state: &state)
        scope.reduce(action: .child(.increment), state: &state)
        #expect(state.childState.count == 3)

        scope.reduce(action: .child(.reset), state: &state)
        #expect(state.childState.count == 0)
    }

    @Test("Scope does not mutate other state slices")
    func scopeIsolatesSlice() {
        var state = ParentState()
        state.ownCount = 99

        Scope(state: \ParentState.childState,
              action: { (a: ParentAction) -> ChildAction? in
                  guard case .child(let c) = a else { return nil }; return c
              }) {
            ChildReducer()
        }
        .reduce(action: .child(.increment), state: &state)

        #expect(state.ownCount == 99)  // untouched
    }

    @Test("Scope initialState returns default ParentState when child has no custom initialState")
    func scopeInitialState() {
        let scope = Scope(
            state: \ParentState.childState,
            action: { (_: ParentAction) -> ChildAction? in nil }
        ) { ChildReducer() }

        let initial: ParentState = scope.initialState()
        #expect(initial == ParentState())
    }

    @Test("Scope initialState uses child reducer's custom initialState")
    func scopeInitialStateRespectsChildOverride() {
        // A child reducer with a non-default initial count.
        struct SeededChildReducer: ReducerType {
            func initialState() -> ChildState { ChildState(count: 42) }
            func reduce(action: ChildAction, state: inout ChildState) {}
        }

        let scope = Scope(
            state: \ParentState.childState,
            action: { (_: ParentAction) -> ChildAction? in nil }
        ) { SeededChildReducer() }

        let initial: ParentState = scope.initialState()
        #expect(initial.childState.count == 42)
        #expect(initial.ownCount == 0)  // parent-owned fields are still default
    }
}

// MARK: - CombinedReducer tests

/// Two simple reducers that each mutate different fields of TestState
/// so we can verify both ran in order.
private struct LabelReducer: ReducerType {
    let label: String
    func reduce(action: TestAction, state: inout TestState) {
        if action == .increment {
            state.label = label
        }
    }
}

@Suite("CombinedReducer")
struct CombinedReducerTests {

    @Test("both reducers run on the same action")
    func bothReducersRun() {
        var state = TestState()
        let combined = TestReducer().combined(with: LabelReducer(label: "hit"))

        combined.reduce(action: .increment, state: &state)

        #expect(state.count == 1)      // TestReducer ran
        #expect(state.label == "hit")  // LabelReducer ran
    }

    @Test("first reducer runs before second")
    func orderIsFirstThenSecond() {
        // The second reducer reads count after the first has incremented it.
        // We capture the count the second reducer sees via a closure reducer.
        var seenCount = -1

        struct ObserverReducer: ReducerType {
            let observe: (Int) -> Void
            func reduce(action: TestAction, state: inout TestState) {
                observe(state.count)
            }
        }

        var state = TestState()
        let combined = TestReducer()
            .combined(with: ObserverReducer { seenCount = $0 })

        combined.reduce(action: .increment, state: &state)

        // TestReducer incremented count to 1 first,
        // so ObserverReducer saw count == 1, not 0.
        #expect(seenCount == 1)
    }

    @Test("non-matching action leaves both sides unchanged")
    func noopAction() {
        var state = TestState(count: 7, label: "x")
        let before = state
        let combined = TestReducer().combined(with: LabelReducer(label: "y"))

        combined.reduce(action: .noop, state: &state)

        #expect(state == before)
    }

    @Test("combined chains are composable (three reducers)")
    func tripleComposition() {
        var state = TestState()

        // count +1, then +1 again, label set
        let triple = TestReducer()
            .combined(with: TestReducer())
            .combined(with: LabelReducer(label: "done"))

        triple.reduce(action: .increment, state: &state)

        #expect(state.count == 2)
        #expect(state.label == "done")
    }
}
