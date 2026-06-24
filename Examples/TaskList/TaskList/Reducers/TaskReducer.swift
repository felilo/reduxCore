//
//  TaskReducer.swift
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
import Foundation

struct TaskReducer: ReducerType {
    func reduce(action: TaskAction, state: inout TaskState) {
        switch action {

        case .appeared:
            state.isLoading    = true
            state.errorMessage = nil

        case .searchChanged(let query):
            state.searchQuery = query

        case .createTapped:
            state.isLoading = true

        case .deleteTapped:
            break   // optimistic delete: middleware dispatches .taskDeleted after API confirms

        case .navigate(to: let destination):
            state.navigation = destination

        case .resetNavigation:
            state.navigation = nil

        case .tasksLoaded(let tasks):
            state.tasks     = tasks
            state.isLoading = false
            state.errorMessage = nil

        case .taskCreated(let task):
            state.tasks.append(task)
            state.isLoading = false

        case .taskUpdated(let updated):
            state.tasks = state.tasks.map { $0.id == updated.id ? updated : $0 }

        case .taskDeleted(let id):
            state.tasks.removeAll { $0.id == id }

        case .failed(let message):
            state.errorMessage = message
            state.isLoading    = false
        }
    }
}
