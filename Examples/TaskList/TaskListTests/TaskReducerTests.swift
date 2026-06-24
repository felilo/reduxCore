//
//  TaskReducerTests.swift
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

// MARK: - Fixtures

private let taskA = TaskItem(id: UUID(), title: "Buy milk", isDone: false)
private let taskB = TaskItem(id: UUID(), title: "Read book", isDone: false)

// MARK: - Tests

@MainActor
@Suite("TaskReducer")
struct TaskReducerTests {

    // MARK: .appeared

    @Test func appearedSetsLoadingAndClearsError() {
        var state = TaskState(errorMessage: "previous error")
        TaskReducer().reduce(action: .appeared, state: &state)
        #expect(state.isLoading == true)
        #expect(state.errorMessage == nil)
    }

    // MARK: .searchChanged

    @Test func searchChangedUpdatesQuery() {
        var state = TaskState()
        TaskReducer().reduce(action: .searchChanged("milk"), state: &state)
        #expect(state.searchQuery == "milk")
    }

    @Test func searchChangedToEmptyStringClearsQuery() {
        var state = TaskState(searchQuery: "milk")
        TaskReducer().reduce(action: .searchChanged(""), state: &state)
        #expect(state.searchQuery == "")
    }

    // MARK: .createTapped

    @Test func createTappedSetsLoadingFlag() {
        var state = TaskState()
        TaskReducer().reduce(action: .createTapped(title: "New"), state: &state)
        #expect(state.isLoading == true)
    }

    // MARK: .deleteTapped

    @Test func deleteTappedDoesNotMutateState() {
        var state = TaskState(tasks: [taskA])
        TaskReducer().reduce(action: .deleteTapped(id: taskA.id), state: &state)
        // Optimistic delete is handled via .taskDeleted; reducer does nothing here
        #expect(state.tasks.count == 1)
    }

    // MARK: .navigate

    @Test func navigateSetsDetailNavigation() {
        var state = TaskState(tasks: [taskA])
        TaskReducer().reduce(action: .navigate(to: .detail(taskA)), state: &state)
        #expect(state.navigation == .detail(taskA))
    }

    @Test func navigateUpdatesNavigationDestination() {
        var state = TaskState(tasks: [taskA, taskB], navigation: .detail(taskA))
        TaskReducer().reduce(action: .navigate(to: .detail(taskB)), state: &state)
        #expect(state.navigation == .detail(taskB))
    }

    // MARK: .resetNavigation

    @Test func resetNavigationClearsNavigation() {
        var state = TaskState(navigation: .detail(taskA))
        TaskReducer().reduce(action: .resetNavigation, state: &state)
        #expect(state.navigation == nil)
    }

    // MARK: .tasksLoaded

    @Test func tasksLoadedReplacesListAndClearsLoading() {
        var state = TaskState(isLoading: true)
        TaskReducer().reduce(action: .tasksLoaded([taskA, taskB]), state: &state)
        #expect(state.tasks == [taskA, taskB])
        #expect(state.isLoading == false)
    }

    @Test func tasksLoadedWithEmptyArrayClearsExistingTasks() {
        var state = TaskState(tasks: [taskA, taskB])
        TaskReducer().reduce(action: .tasksLoaded([]), state: &state)
        #expect(state.tasks.isEmpty)
    }

    // MARK: .taskCreated

    @Test func taskCreatedAppendsTaskAndClearsLoading() {
        var state = TaskState(tasks: [taskA], isLoading: true)
        TaskReducer().reduce(action: .taskCreated(taskB), state: &state)
        #expect(state.tasks.count == 2)
        #expect(state.tasks.last == taskB)
        #expect(state.isLoading == false)
    }

    // MARK: .taskUpdated

    @Test func taskUpdatedReplacesMatchingTask() {
        let updated = TaskItem(id: taskA.id, title: taskA.title, isDone: true)
        var state = TaskState(tasks: [taskA, taskB])
        TaskReducer().reduce(action: .taskUpdated(updated), state: &state)
        #expect(state.tasks.first == updated)
        #expect(state.tasks.count == 2)
    }

    @Test func taskUpdatedWithUnknownIDLeavesListUnchanged() {
        let unknown = TaskItem(id: UUID(), title: "Ghost", isDone: true)
        var state = TaskState(tasks: [taskA, taskB])
        TaskReducer().reduce(action: .taskUpdated(unknown), state: &state)
        #expect(state.tasks == [taskA, taskB])
    }

    // MARK: .taskDeleted

    @Test func taskDeletedRemovesMatchingTask() {
        var state = TaskState(tasks: [taskA, taskB])
        TaskReducer().reduce(action: .taskDeleted(taskA.id), state: &state)
        #expect(state.tasks == [taskB])
    }

    @Test func taskDeletedWithUnknownIDLeavesListUnchanged() {
        var state = TaskState(tasks: [taskA])
        TaskReducer().reduce(action: .taskDeleted(UUID()), state: &state)
        #expect(state.tasks == [taskA])
    }

    // MARK: .failed

    @Test func failedStoresMessageAndClearsLoading() {
        var state = TaskState(isLoading: true)
        TaskReducer().reduce(action: .failed("Network error"), state: &state)
        #expect(state.errorMessage == "Network error")
        #expect(state.isLoading == false)
    }

    @Test func failedDoesNotClearExistingTasks() {
        var state = TaskState(tasks: [taskA], isLoading: true)
        TaskReducer().reduce(action: .failed("err"), state: &state)
        #expect(state.tasks == [taskA])
    }
}
