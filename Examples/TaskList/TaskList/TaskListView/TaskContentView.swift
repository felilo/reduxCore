//
//  TaskContentView.swift
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

import SwiftUI

struct TaskContentView: View {
    let filteredTasks: [TaskItem]
    let searchQuery: String
    let onTaskTapped: (TaskItem) -> Void
    let onTaskDeleted: (TaskItem) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            ForEach(filteredTasks) { task in
                TaskRowView(
                    task: task,
                    onTap: { onTaskTapped(task) },
                    onDelete: { onTaskDeleted(task) }
                )
            }
        }
        .refreshable { await onRefresh() }
        .overlay {
            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? "No Tasks" : "No Results",
                    systemImage: searchQuery.isEmpty ? "checklist" : "magnifyingglass",
                    description: Text(
                        searchQuery.isEmpty
                            ? "Tap + to add your first task."
                            : "No tasks match \"\(searchQuery)\"."
                    )
                )
            }
        }
    }
}
