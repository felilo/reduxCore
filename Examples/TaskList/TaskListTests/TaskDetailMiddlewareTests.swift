//
//  TaskDetailMiddlewareTests.swift
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

import Testing
import Foundation
@testable import TaskList

private final class MockAnalyticsTracker: AnalyticsTracker, @unchecked Sendable {
    var recorded: [(event: String, properties: [String: String])] = []

    func track(_ event: String, properties: [String: String]) {
        recorded.append((event: event, properties: properties))
    }
}

private let stubTask = TaskItem(id: UUID(), title: "Buy milk", isDone: false)

@MainActor
@Suite("TaskDetailAnalyticsMiddleware")
struct TaskDetailAnalyticsMiddlewareTests {

    @Test func appearedTracksTaskDetailViewed() async {
        let tracker = MockAnalyticsTracker()
        let middleware = TaskDetailAnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .appeared(stubTask), state: TaskDetailState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_detail_viewed")
    }

    @Test func toggleDoneTappedTracksWithIsDoneFalseToTrue() async {
        let tracker = MockAnalyticsTracker()
        let middleware = TaskDetailAnalyticsMiddleware(tracker: tracker)
        let state = TaskDetailState(task: stubTask)   // isDone = false → toggling to true

        await middleware.process(action: .toggleDoneTapped, state: state, next: { _ in })

        #expect(tracker.recorded.first?.event == "task_toggle_tapped")
        #expect(tracker.recorded.first?.properties["is_done"] == "true")
    }

    @Test func toggleDoneTappedTracksWithIsDoneTrueToFalse() async {
        let tracker = MockAnalyticsTracker()
        let middleware = TaskDetailAnalyticsMiddleware(tracker: tracker)
        let doneTask = TaskItem(id: stubTask.id, title: stubTask.title, isDone: true)
        let state = TaskDetailState(task: doneTask)   // isDone = true → toggling to false

        await middleware.process(action: .toggleDoneTapped, state: state, next: { _ in })

        #expect(tracker.recorded.first?.event == "task_toggle_tapped")
        #expect(tracker.recorded.first?.properties["is_done"] == "false")
    }

    @Test func neverCallsNext() async {
        let tracker = MockAnalyticsTracker()
        let middleware = TaskDetailAnalyticsMiddleware(tracker: tracker)

        var dispatched: [TaskDetailAction] = []
        let next: @Sendable (TaskDetailAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .appeared(stubTask), state: TaskDetailState(), next: next)

        #expect(dispatched.isEmpty)
    }
}

@MainActor
@Suite("TaskDetailMiddleware")
struct TaskDetailMiddlewareTests {

    @Test func toggleDoneTappedCallsAPIWithTaskID() async {
        let api = MockTaskAPIClient()
        let middleware = TaskDetailMiddleware(api: api)
        let state = TaskDetailState(task: stubTask)

        await middleware.process(action: .toggleDoneTapped, state: state, next: { _ in })

        #expect(api.toggleCallCount == 1)
        #expect(api.toggleReceivedIDs == [stubTask.id])
    }

    @Test func toggleDoneTappedDispatchesFailedWhenAPIThrows() async {
        let api = MockTaskAPIClient()
        api.shouldThrow = true
        let middleware = TaskDetailMiddleware(api: api)
        let state = TaskDetailState(task: stubTask)

        var dispatched: [TaskDetailAction] = []
        let next: @Sendable (TaskDetailAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .toggleDoneTapped, state: state, next: next)

        guard case .failed = dispatched.first else {
            Issue.record("Expected .failed, got \(dispatched)")
            return
        }
    }

    @Test func toggleDoneTappedWithNoTaskDoesNotCallAPI() async {
        let api = MockTaskAPIClient()
        let middleware = TaskDetailMiddleware(api: api)

        await middleware.process(action: .toggleDoneTapped, state: TaskDetailState(), next: { _ in })

        #expect(api.toggleCallCount == 0)
    }
}
