//
//  TaskStateTests.swift
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
@Suite("TaskState computed properties")
struct TaskStateTests {

    private let milk  = TaskItem(id: UUID(), title: "Buy Milk",  isDone: false)
    private let book  = TaskItem(id: UUID(), title: "Read book", isDone: true)
    private let bread = TaskItem(id: UUID(), title: "Buy bread", isDone: false)

    // MARK: filteredTasks

    @Test func filteredTasksReturnsAllWhenQueryIsEmpty() {
        var state = TaskState(tasks: [milk, book])
        state.searchQuery = ""
        #expect(state.filteredTasks.count == 2)
    }

    @Test func filteredTasksMatchesBySubstring() {
        var state = TaskState(tasks: [milk, book, bread])
        state.searchQuery = "buy"
        #expect(state.filteredTasks.count == 2)
        #expect(state.filteredTasks.allSatisfy { $0.title.lowercased().contains("buy") })
    }

    @Test func filteredTasksIsCaseInsensitive() {
        var state = TaskState(tasks: [milk])
        state.searchQuery = "MILK"
        #expect(state.filteredTasks.count == 1)
    }

    @Test func filteredTasksReturnsEmptyForNoMatch() {
        var state = TaskState(tasks: [milk, book])
        state.searchQuery = "zzz"
        #expect(state.filteredTasks.isEmpty)
    }

    @Test func filteredTasksReflectsCurrentTasksAndQuery() {
        var state = TaskState(tasks: [milk, book])
        state.searchQuery = "book"
        #expect(state.filteredTasks == [book])

        // Update tasks — derived value reflects new source of truth
        state.tasks = [bread]
        #expect(state.filteredTasks.isEmpty)
    }

    // MARK: Default values

    @Test func defaultStateHasExpectedValues() {
        let state = TaskState()
        #expect(state.tasks.isEmpty)
        #expect(state.searchQuery == "")
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
    }
}
