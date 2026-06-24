//
//  TaskMiddlewareTests.swift
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
import Testing
@testable import TaskList

@MainActor
@Suite("TaskMiddleware")
struct TaskMiddlewareTests {

    private let stubTask = TaskItem(id: UUID(), title: "Buy milk", isDone: false)

    // MARK: .appeared

    @Test func appearedFetchesAndDispatchesTasksLoaded() async {
        let api = MockTaskAPIClient()
        api.stubbedTasks = [stubTask]
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), next: next)

        #expect(api.fetchCallCount == 1)
        guard case .tasksLoaded(let tasks) = dispatched.first else {
            Issue.record("Expected .tasksLoaded, got \(dispatched)")
            return
        }
        #expect(tasks == [stubTask])
    }

    @Test func appearedDispatchesFailedWhenAPIThrows() async {
        let api = MockTaskAPIClient()
        api.shouldThrow = true
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), next: next)

        guard case .failed = dispatched.first else {
            Issue.record("Expected .failed, got \(dispatched)")
            return
        }
    }

    // MARK: .createTapped

    @Test func createTappedDispatchesTaskCreated() async {
        let api = MockTaskAPIClient()
        api.stubbedCreatedTask = stubTask
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(
            action: .createTapped(title: "Buy milk"),
            state: TaskState(),
            next: next
        )

        #expect(api.createCallCount == 1)
        #expect(api.createReceivedTitles == ["Buy milk"])
        guard case .taskCreated(let task) = dispatched.first else {
            Issue.record("Expected .taskCreated, got \(dispatched)")
            return
        }
        #expect(task == stubTask)
    }

    @Test func createTappedDispatchesFailedWhenAPIThrows() async {
        let api = MockTaskAPIClient()
        api.shouldThrow = true
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(
            action: .createTapped(title: "Fail"),
            state: TaskState(),
            next: next
        )

        guard case .failed = dispatched.first else {
            Issue.record("Expected .failed, got \(dispatched)")
            return
        }
    }

    // MARK: .deleteTapped

    @Test func deleteTappedDispatchesTaskDeleted() async {
        let id = UUID()
        let api = MockTaskAPIClient()
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .deleteTapped(id: id), state: TaskState(), next: next)

        #expect(api.deleteCallCount == 1)
        #expect(api.deleteReceivedIDs == [id])
        guard case .taskDeleted(let deletedID) = dispatched.first else {
            Issue.record("Expected .taskDeleted, got \(dispatched)")
            return
        }
        #expect(deletedID == id)
    }

    @Test func deleteTappedDispatchesFailedWhenAPIThrows() async {
        let api = MockTaskAPIClient()
        api.shouldThrow = true
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .deleteTapped(id: UUID()), state: TaskState(), next: next)

        guard case .failed = dispatched.first else {
            Issue.record("Expected .failed, got \(dispatched)")
            return
        }
    }

    // MARK: .searchChanged

    @Test func searchChangedFetchesTasksAfterDebounce() async throws {
        let api = MockTaskAPIClient()
        api.stubbedTasks = [stubTask]
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .searchChanged("milk"), state: TaskState(), next: next)
        try await Task.sleep(for: .milliseconds(400))

        #expect(api.fetchCallCount == 1)
        guard case .tasksLoaded(let tasks) = dispatched.first else {
            Issue.record("Expected .tasksLoaded, got \(dispatched)")
            return
        }
        #expect(tasks == [stubTask])
    }

    @Test func searchChangedCancelsPreviousDebounceOnRapidInput() async throws {
        let api = MockTaskAPIClient()
        api.stubbedTasks = []
        let middleware = TaskMiddleware(api: api)

        let next: @Sendable (TaskAction) async -> Void = { _ in }

        await middleware.process(action: .searchChanged("m"), state: TaskState(), next: next)
        await middleware.process(action: .searchChanged("mi"), state: TaskState(), next: next)
        try await Task.sleep(for: .milliseconds(400))

        #expect(api.fetchCallCount == 1)
    }

    @Test func searchChangedDispatchesFailedWhenAPIThrows() async throws {
        let api = MockTaskAPIClient()
        api.shouldThrow = true
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .searchChanged("milk"), state: TaskState(), next: next)
        try await Task.sleep(for: .milliseconds(400))

        guard case .failed = dispatched.first else {
            Issue.record("Expected .failed, got \(dispatched)")
            return
        }
    }

    // MARK: .resetNavigation

    @Test func resetNavigationDoesNotDispatch() async {
        let api = MockTaskAPIClient()
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .resetNavigation, state: TaskState(), next: next)

        #expect(dispatched.isEmpty)
        #expect(api.fetchCallCount == 0)
    }

    // MARK: Unhandled actions

    @Test func unhandledActionsDoNotDispatch() async {
        let api = MockTaskAPIClient()
        let middleware = TaskMiddleware(api: api)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        let unhandled: [TaskAction] = [
            .tasksLoaded([]),
            .taskCreated(TaskItem(id: UUID(), title: "x", isDone: false)),
            .taskUpdated(TaskItem(id: UUID(), title: "x", isDone: true)),
            .taskDeleted(UUID()),
            .navigate(to: .detail(TaskItem(id: UUID(), title: "x", isDone: false))),
            .resetNavigation,
            .failed("err"),
        ]

        for action in unhandled {
            await middleware.process(action: action, state: TaskState(), next: next)
        }

        #expect(dispatched.isEmpty)
        #expect(api.fetchCallCount == 0)
    }
}
