//
//  LoggerMiddlewareTests.swift
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

@MainActor
@Suite("LoggerMiddleware")
struct LoggerMiddlewareTests {

    @Test func processDoesNotDispatchActions() async {
        let middleware = LoggerMiddleware<TaskAction, TaskState>()

        var dispatched: [TaskAction] = []
        let next: @Sendable (TaskAction) async -> Void = { @MainActor in dispatched.append($0) }

        await middleware.process(action: .appeared, state: TaskState(), next: next)

        #expect(dispatched.isEmpty)
    }

    @Test func processDoesNotCrashForAnyAction() async {
        let middleware = LoggerMiddleware<TaskAction, TaskState>()
        let actions: [TaskAction] = [
            .appeared,
            .searchChanged("query"),
            .createTapped(title: "task"),
            .deleteTapped(id: UUID()),
            .navigate(to: .detail(TaskItem(id: UUID(), title: "x", isDone: false))),
            .resetNavigation,
            .tasksLoaded([]),
            .taskCreated(TaskItem(id: UUID(), title: "x", isDone: false)),
            .taskDeleted(UUID()),
            .failed("err"),
        ]

        for action in actions {
            await middleware.process(action: action, state: TaskState(), next: { _ in })
        }
    }
}
