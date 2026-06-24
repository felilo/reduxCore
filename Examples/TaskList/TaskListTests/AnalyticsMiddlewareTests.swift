//
//  AnalyticsMiddlewareTests.swift
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

// MARK: - Mock

private final class MockAnalyticsTracker: AnalyticsTracker, @unchecked Sendable {
    var recorded: [(event: String, properties: [String: String])] = []

    func track(_ event: String, properties: [String: String]) {
        recorded.append((event: event, properties: properties))
    }
}

// MARK: - Tests

@MainActor
@Suite("AnalyticsMiddleware")
struct AnalyticsMiddlewareTests {

    @Test func appearedTracksTaskListViewed() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .appeared, state: TaskState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_list_viewed")
    }

    @Test func createTappedTracksWithTitleLength() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .createTapped(title: "Buy milk"), state: TaskState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_create_tapped")
        #expect(tracker.recorded.first?.properties["title_length"] == "8")
    }

    @Test func taskCreatedTracksEvent() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)
        let task = TaskItem(id: UUID(), title: "x", isDone: false)

        await middleware.process(action: .taskCreated(task), state: TaskState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_created")
    }

    @Test func deleteTappedTracksEvent() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .deleteTapped(id: UUID()), state: TaskState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_delete_tapped")
    }

    @Test func failedTracksErrorWithMessage() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .failed("Network error"), state: TaskState(), next: { _ in })

        #expect(tracker.recorded.first?.event == "task_error")
        #expect(tracker.recorded.first?.properties["message"] == "Network error")
    }

    @Test func unhandledActionDoesNotTrack() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        await middleware.process(action: .resetNavigation, state: TaskState(), next: { _ in })

        #expect(tracker.recorded.isEmpty)
    }

    @Test func neverCallsNext() async {
        let tracker = MockAnalyticsTracker()
        let middleware = AnalyticsMiddleware(tracker: tracker)

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), next: next)

        #expect(dispatched.isEmpty)
    }
}
