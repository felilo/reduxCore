//
//  TaskListScreen.swift
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

@StoreView(reducer: TaskReducer.self)
struct TaskListScreen: View {

    @Environment(\.taskAPIClient) private var api
    @Environment(\.analyticsTracker) private var tracker

    @MiddlewareResultBuilder
    var middleware: [Middleware] {
        TaskMiddleware(api: api)
        AnalyticsMiddleware(tracker: tracker)
        LoggerMiddleware()
    }

    // MARK: - Content (required by @StoreView)

    @ViewBuilder
    func content(store: Store) -> some View {
        let state = store.state

        taskStack(store: store, state: state)
            .overlay { loadingOverlay(isLoading: state.isLoading) }
            .task { store.dispatch(.appeared) }
    }

    // MARK: - Private Helpers

    @ViewBuilder
    private func taskStack(store: Store, state: TaskState) -> some View {
        NavigationStack {
            TaskContentView(
                filteredTasks: state.filteredTasks,
                searchQuery: state.searchQuery,
                onTaskTapped: { store.dispatch(.navigate(to: .detail($0))) },
                onTaskDeleted: { store.dispatch(.deleteTapped(id: $0.id)) },
                onRefresh: { await store.dispatchAsync(.appeared) }
            )
            .navigationTitle("Tasks")
            .searchable(
                text: Binding(
                    get: { state.searchQuery },
                    set: { store.dispatch(.searchChanged($0)) }
                ),
                prompt: "Search tasks"
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton { store.dispatch(.createTapped(title: "New Task")) }
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(get: { state.errorMessage != nil }, set: { _ in }),
                presenting: state.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .sheet(item: Binding<TaskItem?>(
                get: {
                    guard case .detail(let task) = state.navigation else { return nil }
                    return task
                },
                set: { _ in store.dispatch(.resetNavigation) }
            )) { task in
                TaskDetailView(
                    initialTask: task,
                    onDismiss: { store.dispatch(.resetNavigation) },
                    onTaskChanged: { store.dispatch(.taskUpdated($0)) }
                )
            }
        }
    }

    @ViewBuilder
    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Task")
    }

    @ViewBuilder
    private func loadingOverlay(isLoading: Bool) -> some View {
        ProgressView("Loading tasks…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
            .opacity(isLoading ? 1 : 0)
            .animation(.default, value: isLoading)
    }
}

// MARK: - Preview

#if DEBUG
private struct PreviewAPIClient: TaskAPIClient {
    let tasks: [TaskItem]
    func fetchTasks() async throws -> [TaskItem] { tasks }
    func createTask(title: String) async throws -> TaskItem {
        TaskItem(id: UUID(), title: title, isDone: false)
    }
    func deleteTask(id: UUID) async throws {}
    func toggleTask(id: UUID) async throws {}
}

#Preview("Loaded") {
    TaskListScreen()
        .environment(\.taskAPIClient, PreviewAPIClient(tasks: [
            TaskItem(id: UUID(), title: "Buy groceries", isDone: false),
            TaskItem(id: UUID(), title: "Read a book",   isDone: true),
            TaskItem(id: UUID(), title: "Go for a run",  isDone: false),
            TaskItem(id: UUID(), title: "Call mom",      isDone: false),
        ]))
}

#Preview("Empty") {
    TaskListScreen()
        .environment(\.taskAPIClient, PreviewAPIClient(tasks: []))
}

#Preview("Loading") {
    TaskListScreen()
}
#endif
