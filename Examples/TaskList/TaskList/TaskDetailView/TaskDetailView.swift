//
//  TaskDetailView.swift
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
import ReduxCore

@StoreView(reducer: TaskDetailReducer.self)
struct TaskDetailView: View {

    let initialTask: TaskItem
    let onDismiss: () -> Void
    var onTaskChanged: ((TaskItem) -> Void)? = nil

    @Environment(\.taskAPIClient) private var api
    @Environment(\.analyticsTracker) private var tracker

    @MiddlewareResultBuilder
    var middleware: [Middleware] {
        TaskDetailMiddleware(api: api)
        TaskDetailAnalyticsMiddleware(tracker: tracker)
        LoggerMiddleware()
    }

    @ViewBuilder
    func content(store: Store) -> some View {
        let task = store.state.task ?? initialTask

        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 64))
                    .foregroundStyle(task.isDone ? .green : .secondary)
                Text(task.title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text(task.isDone ? "Completed" : "Not yet done")
                    .foregroundStyle(.secondary)
                Button(task.isDone ? "Mark as Undone" : "Mark as Done") {
                    store.dispatch(.toggleDoneTapped)
                }
                .buttonStyle(.borderedProminent)
                .tint(task.isDone ? .secondary : .accentColor)
            }
            .padding()
            .navigationTitle("Task Detail")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { store.state.errorMessage != nil }, set: { _ in }),
                presenting: store.state.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
        }
        .task { store.dispatch(.appeared(initialTask)) }
        .onChange(of: store.state.task) { oldTask, newTask in
            guard oldTask != nil, let newTask else { return }
            onTaskChanged?(newTask)
        }
    }
}
