//
//  TaskDetailMiddleware.swift
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

struct TaskDetailMiddleware: MiddlewareType, Sendable {

    private let api: any TaskAPIClient
    
    init(api: any TaskAPIClient) {
        self.api = api
    }

    func process(
        action: TaskDetailAction,
        state: TaskDetailState,
        next: @escaping @concurrent @Sendable (TaskDetailAction) async -> Void
    ) async {
        switch action {
        case .appeared:
            break
        case .toggleDoneTapped:
            guard let id = state.task?.id else { return }
            do {
                try await api.toggleTask(id: id)
            } catch {
                await next(.failed(error.localizedDescription))
            }
        case .failed:
            break
        }
    }
}
