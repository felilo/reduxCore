//
//  MockTaskAPIClient.swift
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
@testable import TaskList

// MARK: - MockTaskAPIClient

final class MockTaskAPIClient: TaskAPIClient, @unchecked Sendable {

    // MARK: Stubbed responses

    var stubbedTasks: [TaskItem] = []
    var stubbedCreatedTask: TaskItem?
    var shouldThrow = false

    // MARK: Recorded calls

    var fetchCallCount = 0
    var createCallCount = 0
    var createReceivedTitles: [String] = []
    var deleteCallCount = 0
    var deleteReceivedIDs: [UUID] = []
    var toggleCallCount = 0
    var toggleReceivedIDs: [UUID] = []

    // MARK: TaskAPIClient

    func fetchTasks() async throws -> [TaskItem] {
        fetchCallCount += 1
        if shouldThrow { throw MockError.intentional }
        return stubbedTasks
    }

    func createTask(title: String) async throws -> TaskItem {
        createCallCount += 1
        createReceivedTitles.append(title)
        if shouldThrow { throw MockError.intentional }
        guard let task = stubbedCreatedTask else {
            return TaskItem(id: UUID(), title: title, isDone: false)
        }
        return task
    }

    func deleteTask(id: UUID) async throws {
        deleteCallCount += 1
        deleteReceivedIDs.append(id)
        if shouldThrow { throw MockError.intentional }
    }

    func toggleTask(id: UUID) async throws {
        toggleCallCount += 1
        toggleReceivedIDs.append(id)
        if shouldThrow { throw MockError.intentional }
    }
}

// MARK: -

enum MockError: Error, LocalizedError {
    case intentional

    var errorDescription: String? { "Mock error" }
}
