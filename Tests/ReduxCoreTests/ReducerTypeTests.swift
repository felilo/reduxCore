//
//  ReducerTypeTests.swift
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

// ReducerTypeTests.swift
// Tests for ReducerType protocol, ActionType, and StateType.

import Testing
import ReduxCore

// MARK: - ReducerType

@Suite("ReducerType")
struct ReducerTypeTests {

    // MARK: Initial state

    @Test("initialState() returns default zero state")
    func initialStateIsDefault() {
        let state = TestReducer().initialState()
        #expect(state == TestState())
        #expect(state.count == 0)
    }

    // MARK: Action handling

    @Test("increment action increases count by 1")
    func increment() {
        var state = TestState(count: 5)
        TestReducer().reduce(action: .increment, state: &state)
        #expect(state.count == 6)
    }

    @Test("decrement action decreases count by 1")
    func decrement() {
        var state = TestState(count: 5)
        TestReducer().reduce(action: .decrement, state: &state)
        #expect(state.count == 4)
    }

    @Test("reset action sets count to zero")
    func reset() {
        var state = TestState(count: 99)
        TestReducer().reduce(action: .reset, state: &state)
        #expect(state.count == 0)
    }

    @Test("setValue action sets exact value")
    func setValue() {
        var state = TestState()
        TestReducer().reduce(action: .setValue(77), state: &state)
        #expect(state.count == 77)
    }

    @Test("noop action leaves state unchanged")
    func noop() {
        var state = TestState(count: 10, label: "same")
        let before = state
        TestReducer().reduce(action: .noop, state: &state)
        #expect(state == before)
    }

    // MARK: Sequential reductions

    @Test("sequential reductions accumulate correctly")
    func sequentialReductions() {
        var state = TestReducer().initialState()
        let reducer = TestReducer()
        reducer.reduce(action: .increment, state: &state)
        reducer.reduce(action: .increment, state: &state)
        reducer.reduce(action: .decrement, state: &state)
        #expect(state.count == 1)
    }
}

// MARK: - ActionType / Actionable

@Suite("ActionType")
struct ActionTypeTests {

    @Test("same cases are equal")
    func sameCasesEqual() {
        #expect(TestAction.increment == TestAction.increment)
        #expect(TestAction.reset == TestAction.reset)
    }

    @Test("different cases are not equal")
    func differentCasesNotEqual() {
        #expect(TestAction.increment != TestAction.decrement)
        #expect(TestAction.increment != TestAction.reset)
    }

    @Test("associated value cases compare values")
    func associatedValueEquality() {
        #expect(TestAction.setValue(5) == TestAction.setValue(5))
        #expect(TestAction.setValue(5) != TestAction.setValue(6))
    }

    @Test("Actionable typealias resolves to ActionType")
    func typealiasResolution() {
        // Compile-time check: if this builds, the typealias works
        func acceptsActionable<A: Actionable>(_ a: A) -> Bool { true }
        #expect(acceptsActionable(TestAction.increment))
    }
}

// MARK: - StateType / Statable

@Suite("StateType")
struct StateTypeTests {

    @Test("identical states are equal")
    func identicalStatesEqual() {
        let s1 = TestState(count: 7, label: "x")
        let s2 = TestState(count: 7, label: "x")
        #expect(s1 == s2)
    }

    @Test("states differing in count are not equal")
    func differentCountNotEqual() {
        #expect(TestState(count: 1) != TestState(count: 2))
    }

    @Test("states differing in label are not equal")
    func differentLabelNotEqual() {
        #expect(TestState(count: 0, label: "a") != TestState(count: 0, label: "b"))
    }

    @Test("Statable typealias resolves to StateType")
    func typealiasResolution() {
        func acceptsStatable<S: Statable>(_ s: S) -> Bool { true }
        #expect(acceptsStatable(TestState()))
    }
}
