//
//  LocalTaskAPIClient.swift
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

/// In-memory implementation that simulates network latency.
/// Used as the real client in the running app.
actor LocalTaskAPIClient: TaskAPIClient {

    private var tasks: [TaskItem] = [
        TaskItem(id: UUID(), title: "Buy groceries", isDone: false),
        TaskItem(id: UUID(), title: "Read a book",   isDone: true),
        TaskItem(id: UUID(), title: "Go for a run",  isDone: false),
        TaskItem(id: UUID(), title: "Call mom",       isDone: false),
    ]

    func fetchTasks() async throws -> [TaskItem] {
        try await Task.sleep(for: .milliseconds(800))
        return tasks
    }

    func createTask(title: String) async throws -> TaskItem {
        try await Task.sleep(for: .milliseconds(300))
        let task = TaskItem(id: UUID(), title: title, isDone: false)
        tasks.append(task)
        return task
    }

    func deleteTask(id: UUID) async throws {
        try await Task.sleep(for: .milliseconds(200))
        tasks.removeAll { $0.id == id }
    }

    func toggleTask(id: UUID) async throws {
        try await Task.sleep(for: .milliseconds(200))
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].isDone.toggle()
        }
    }
}
