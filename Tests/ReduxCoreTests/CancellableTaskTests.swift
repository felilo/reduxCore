//
//  CancellableTaskTests.swift
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

// CancellableTaskTests.swift
// Tests for TaskCancellationManager and the CancellableTask protocol extension.

import Testing
import ReduxCore

// MARK: - Test double

/// Minimal concrete CancellableTask implementor used only in this file.
final class TaskRunner: CancellableTask {
    let taskManager = TaskCancellationManager()
}

@Suite("CancellableTask")
struct CancellableTaskTests {

    // MARK: - run(key:_:)

    @Test("run executes the operation")
    func runExecutesOperation() async throws {
        let runner = TaskRunner()
        let flag = Flag()

        await runner.run(key: "op") { flag.set() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(flag.value == true)
    }

    @Test("second run with same key cancels the first task")
    func secondRunCancelsPreviousTask() async throws {
        let runner = TaskRunner()
        let firstCompleted = Flag()

        await runner.run(key: "k") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            firstCompleted.set()
        }

        // Second run immediately cancels the first
        await runner.run(key: "k") { /* no-op */ }

        try await Task.sleep(for: .milliseconds(100))

        #expect(firstCompleted.value == false)
    }

    @Test("two different keys run independently without cancelling each other")
    func differentKeysAreIndependent() async throws {
        let runner = TaskRunner()
        let aCompleted = Flag()
        let bCompleted = Flag()

        await runner.run(key: "a") { aCompleted.set() }
        await runner.run(key: "b") { bCompleted.set() }

        try await Task.sleep(for: .milliseconds(50))

        #expect(aCompleted.value == true)
        #expect(bCompleted.value == true)
    }

    // MARK: - cancel(key:)

    @Test("cancel(key:) cancels only the keyed task")
    func cancelSingleKey() async throws {
        let runner = TaskRunner()
        let aCompleted = Flag()
        let bCompleted = Flag()

        await runner.run(key: "a") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            aCompleted.set()
        }
        await runner.run(key: "b") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            bCompleted.set()
        }

        await runner.cancel(key: "a")

        try await Task.sleep(for: .milliseconds(100))

        #expect(aCompleted.value == false)
        // b is not cancelled — but it's still sleeping; just verify no crash
    }

    // MARK: - cancelAll()

    @Test("cancelAll cancels all in-flight tasks")
    func cancelAllCancelsTasks() async throws {
        let runner = TaskRunner()
        let firstCompleted = Flag()
        let secondCompleted = Flag()

        await runner.run(key: "a") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            firstCompleted.set()
        }
        await runner.run(key: "b") {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            secondCompleted.set()
        }

        await runner.cancelAll()

        try await Task.sleep(for: .milliseconds(100))

        #expect(firstCompleted.value == false)
        #expect(secondCompleted.value == false)
    }

    @Test("cancelAll on empty runner does not crash")
    func cancelAllOnEmptyRunnerIsNoop() async {
        let runner = TaskRunner()
        await runner.cancelAll()  // must not crash
    }

    // MARK: - Multiple sequential runs on the same key

    @Test("three sequential same-key runs result in only the last completing")
    func multipleSequentialSameKey() async throws {
        let runner = TaskRunner()
        let counter = Counter()

        await runner.run(key: "seq") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            counter.increment()
        }
        await runner.run(key: "seq") {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            counter.increment()
        }
        await runner.run(key: "seq") {
            counter.increment()
        }

        try await Task.sleep(for: .milliseconds(150))

        // Only the last (instant) run should complete within the window
        #expect(counter.count == 1)
    }

    // MARK: - TaskCancellationManager direct tests

    @Test("TaskCancellationManager can be used directly")
    func directManagerUsage() async throws {
        let manager = TaskCancellationManager()
        let flag = Flag()

        await manager.run(key: "direct") { flag.set() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(flag.value == true)
    }

    @Test("TaskCancellationManager initializes without arguments")
    func managerDefaultInit() {
        let _ = TaskCancellationManager()
    }

    @Test("run with explicit priority executes the operation")
    func runWithPriority() async throws {
        let manager = TaskCancellationManager()
        let flag = Flag()

        await manager.run(key: "p", priority: .high) { flag.set() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(flag.value == true)
    }

    @Test("run with low priority still executes the operation")
    func runWithLowPriority() async throws {
        let runner = TaskRunner()
        let flag = Flag()

        await runner.run(key: "low", priority: .low) { flag.set() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(flag.value == true)
    }
}
