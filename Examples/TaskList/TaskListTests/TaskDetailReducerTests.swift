//
//  TaskDetailReducerTests.swift
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

private let stubTask = TaskItem(id: UUID(), title: "Buy milk", isDone: false)

@MainActor
@Suite("TaskDetailReducer")
struct TaskDetailReducerTests {

    // MARK: .appeared

    @Test func appearedSetsTask() {
        var state = TaskDetailState()
        TaskDetailReducer().reduce(action: .appeared(stubTask), state: &state)
        #expect(state.task == stubTask)
    }

    @Test func appearedOverwritesPreviousTask() {
        let other = TaskItem(id: UUID(), title: "Read book", isDone: true)
        var state = TaskDetailState(task: other)
        TaskDetailReducer().reduce(action: .appeared(stubTask), state: &state)
        #expect(state.task == stubTask)
    }

    // MARK: .toggleDoneTapped

    @Test func toggleDoneTappedFlipsIsDoneFromFalseToTrue() {
        var state = TaskDetailState(task: stubTask)
        TaskDetailReducer().reduce(action: .toggleDoneTapped, state: &state)
        #expect(state.task?.isDone == true)
    }

    @Test func toggleDoneTappedFlipsIsDoneFromTrueToFalse() {
        let doneTask = TaskItem(id: stubTask.id, title: stubTask.title, isDone: true)
        var state = TaskDetailState(task: doneTask)
        TaskDetailReducer().reduce(action: .toggleDoneTapped, state: &state)
        #expect(state.task?.isDone == false)
    }

    @Test func toggleDoneTappedWithNoTaskDoesNotCrash() {
        var state = TaskDetailState()
        TaskDetailReducer().reduce(action: .toggleDoneTapped, state: &state)
        #expect(state.task == nil)
    }

    // MARK: .failed

    @Test func failedSetsErrorMessage() {
        var state = TaskDetailState()
        TaskDetailReducer().reduce(action: .failed("Toggle failed"), state: &state)
        #expect(state.errorMessage == "Toggle failed")
    }
}
