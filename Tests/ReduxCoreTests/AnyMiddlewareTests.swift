//
//  AnyMiddlewareTests.swift
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

// AnyMiddlewareTests.swift
// Tests for AnyMiddleware type erasure and MiddlewareBuilder result builder.

import Testing
import ReduxCore

// MARK: - AnyMiddleware

@Suite("AnyMiddleware")
@MainActor
struct AnyMiddlewareTests {

    @Test("wraps a concrete middleware and delegates process()")
    func delegatesProcess() async {
        let spy = SpyMiddleware()
        let erased = AnyMiddleware(spy)

        await erased.process(action: .increment, state: TestState()) { _ in }

        #expect(spy.receivedActions == [.increment])
    }

    @Test("next closure is forwarded to the underlying middleware")
    func nextClosureIsForwarded() async {
        let spy = SpyMiddleware(nextAction: .setValue(5))
        let received = Collector<TestAction>()

        let erased = AnyMiddleware(spy)
        await erased.process(action: .increment, state: TestState()) { received.append($0) }

        #expect(received.values == [.setValue(5)])
    }

    @Test("wraps two different concrete types without type mismatch")
    func heterogeneousWrapping() async {
        let spy = SpyMiddleware()
        let passthrough = PassthroughMiddleware(response: .decrement)
        let received = Collector<TestAction>()

        let middleware: [AnyMiddleware<TestAction, TestState>] = [
            AnyMiddleware(spy),
            AnyMiddleware(passthrough)
        ]

        for m in middleware {
            await m.process(action: .increment, state: TestState()) { received.append($0) }
        }

        // passthrough always calls next with .decrement; spy has no nextAction
        #expect(received.values == [.decrement])
        #expect(spy.receivedActions == [.increment])
    }

    @Test("state is passed through correctly to the underlying middleware")
    func stateIsPassedThrough() async {
        let spy = SpyMiddleware()
        let erased = AnyMiddleware(spy)
        let state = TestState(count: 77, label: "hi")

        await erased.process(action: .noop, state: state) { _ in }

        #expect(spy.receivedStates.first == state)
    }

    @Test("process can be called multiple times on the same AnyMiddleware")
    func multipleProcessCalls() async {
        let spy = SpyMiddleware()
        let erased = AnyMiddleware(spy)

        await erased.process(action: .increment, state: TestState()) { _ in }
        await erased.process(action: .decrement, state: TestState()) { _ in }

        #expect(spy.receivedActions == [.increment, .decrement])
    }
}

// MARK: - MiddlewareBuilder

@Suite("MiddlewareBuilder")
struct MiddlewareBuilderTests {

    // MARK: buildExpression + buildBlock

    @Test("single middleware in builder produces one-element array")
    func singleMiddleware() {
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            SpyMiddleware()
        }
        #expect(result.count == 1)
    }

    @Test("two middleware in builder produces two-element array")
    func twoMiddlewares() {
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            SpyMiddleware()
            PassthroughMiddleware(response: .reset)
        }
        #expect(result.count == 2)
    }

    @Test("three heterogeneous middleware produce three-element array")
    func threeHeterogeneousMiddlewares() {
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            SpyMiddleware()
            PassthroughMiddleware(response: .reset)
            AsyncMiddleware()
        }
        #expect(result.count == 3)
    }

    // MARK: buildOptional (if without else)

    @Test("buildOptional includes middleware when condition is true")
    func buildOptionalTrue() {
        let include = true
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            if include { SpyMiddleware() }
        }
        #expect(result.count == 1)
    }

    @Test("buildOptional excludes middleware when condition is false")
    func buildOptionalFalse() {
        let include = false
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            if include { SpyMiddleware() }
        }
        #expect(result.count == 0)
    }

    // MARK: buildEither (if / else)

    @Test("buildEither selects first branch")
    func buildEitherFirst() {
        let flag = true
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            if flag {
                SpyMiddleware()
            } else {
                PassthroughMiddleware(response: .noop)
            }
        }
        #expect(result.count == 1)
    }

    @Test("buildEither selects second branch")
    func buildEitherSecond() {
        let flag = false
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            if flag {
                SpyMiddleware()
            } else {
                PassthroughMiddleware(response: .noop)
            }
        }
        #expect(result.count == 1)
    }

    // MARK: buildArray (for loops)

    @Test("buildArray from for loop produces N elements")
    func buildArray() {
        let count = 4
        let result: [AnyMiddleware<TestAction, TestState>] = build {
            for _ in 0..<count {
                PassthroughMiddleware(response: .noop)
            }
        }
        #expect(result.count == count)
    }

    // MARK: Empty builder

    @Test("empty builder produces empty array")
    func emptyBuilder() {
        let result: [AnyMiddleware<TestAction, TestState>] = build { }
        #expect(result.isEmpty)
    }
}

// MARK: - Helper

/// Thin wrapper that invokes MiddlewareBuilder and returns the typed array.
private func build<Action, State>(
    @MiddlewareBuilder<Action, State> _ builder: () -> [AnyMiddleware<Action, State>]
) -> [AnyMiddleware<Action, State>] {
    builder()
}
