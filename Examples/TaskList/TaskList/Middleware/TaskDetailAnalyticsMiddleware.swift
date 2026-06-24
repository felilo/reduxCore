//
//  TaskDetailAnalyticsMiddleware.swift
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

import ReduxCore

/// Tracks user behaviour events for the task detail screen. Never dispatches follow-up actions.
struct TaskDetailAnalyticsMiddleware: MiddlewareType, Sendable {

    let tracker: any AnalyticsTracker

    init(tracker: any AnalyticsTracker) {
        self.tracker = tracker
    }

    func process(
        action: TaskDetailAction,
        state: TaskDetailState,
        next: @escaping @concurrent @Sendable (TaskDetailAction) async -> Void
    ) async {
        switch action {
        case .appeared:
            await tracker.track("task_detail_viewed")
        case .toggleDoneTapped:
            let newValue = !(state.task?.isDone ?? false)
            await tracker.track("task_toggle_tapped", properties: ["is_done": "\(newValue)"])
        case .failed:
            break
        }
    }
}
