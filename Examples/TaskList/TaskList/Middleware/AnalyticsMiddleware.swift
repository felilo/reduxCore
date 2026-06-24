//
//  AnalyticsMiddleware.swift
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

/// Tracks user behaviour events. Never dispatches follow-up actions.
/// Has zero knowledge of TaskMiddleware or LoggerMiddleware.
struct AnalyticsMiddleware: MiddlewareType, Sendable {
    
    let tracker: any AnalyticsTracker

    init(tracker: any AnalyticsTracker) {
        self.tracker = tracker
    }

    func process(
        action: TaskAction,
        state: TaskState,
        next: @escaping @concurrent @Sendable (TaskAction) async -> Void
    ) async {
        switch action {
        case .appeared:
            await tracker.track("task_list_viewed")
        case .createTapped(let title):
            await tracker.track("task_create_tapped", properties: ["title_length": "\(title.count)"])
        case .taskCreated:
            await tracker.track("task_created")
        case .deleteTapped:
            await tracker.track("task_delete_tapped")
        case .failed(let message):
            await tracker.track("task_error", properties: ["message": message])
        default:
            break
        }
    }
    
}
