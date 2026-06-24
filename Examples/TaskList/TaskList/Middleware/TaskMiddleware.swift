//
//  TaskMiddleware.swift
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
import ReduxCore

struct TaskMiddleware: MiddlewareType, Sendable {

    private let taskManager = TaskCancellationManager()
    private let api: any TaskAPIClient

    init(api: any TaskAPIClient) {
        self.api = api
    }

    func process(action: TaskAction, state: TaskState, next: @escaping @concurrent @Sendable (TaskAction) async -> Void) async {
        switch action {

        case .appeared:
            await fetchTasks(next: next)
        case .searchChanged:
            await taskManager.run(key: "search") {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
                
                await self.fetchTasks(next: next)
            }

        case .createTapped(let title):
            do {
                let task = try await api.createTask(title: title)
                await next(.taskCreated(task))
            } catch {
                await next(.failed(error.localizedDescription))
            }

        case .deleteTapped(let id):
            do {
                try await api.deleteTask(id: id)
                await next(.taskDeleted(id))
            } catch {
                await next(.failed(error.localizedDescription))
            }

        default:
            break
        }
    }

    private func fetchTasks(next: @escaping @Sendable (TaskAction) async -> Void) async {
        do {
            let tasks = try await api.fetchTasks()
            await next(.tasksLoaded(tasks))
        } catch {
            guard !(error is CancellationError) else { return }
            await next(.failed(error.localizedDescription))
        }
    }
}
