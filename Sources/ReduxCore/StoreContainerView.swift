//
//  StoreContainerView.swift
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

/// A SwiftUI view that owns and manages the Redux store for a feature.
///
/// Use this as the root view of a feature screen, passing the reducer,
/// any middleware, and a content closure that receives the store.
///
/// The store is held in `@State` and lives as long as this view is in the
/// hierarchy. In-flight middleware effects are cancelled automatically when
/// `@State` is released — i.e. when the view is permanently removed (popped
/// from a navigation stack, sheet dismissed, etc.) — not on transient
/// disappearances such as pushing a child screen or switching tabs.
public struct StoreContainerView<TReducer: ReducerType, Content: View>: View
where TReducer.Action: Equatable & Sendable, TReducer.State: Equatable & Sendable {

    public typealias Store = ObservableStore<TReducer>
    public typealias Middleware = AnyMiddleware<TReducer.Action, TReducer.State>

    private let content: (Store) -> Content

    // @State keeps the store alive for the entire lifetime of this view
    // and prevents re-creation on re-renders.
    @State private var observableStore: Store

    /// Primary initializer. Accepts type-erased middleware directly.
    public init(
        reducer: TReducer,
        middleware: [Middleware] = [],
        maxDispatchDepth: Int = .max,
        maxActionFrequency: Int = 20,
        cycleWindow: Duration = .seconds(1),
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        self.content = content
        self._observableStore = .init(wrappedValue: .init(
            store: .init(
                reducer: reducer,
                middleware: middleware,
                maxDispatchDepth: maxDispatchDepth,
                maxActionFrequency: maxActionFrequency,
                cycleWindow: cycleWindow
            )
        ))
    }

    public var body: some View {
        content(observableStore)
    }
}

// MARK: - Convenience Initializers

extension StoreContainerView {

    /// Convenience init that accepts a heterogeneous array of middleware.
    /// Each middleware is type-erased automatically so the call site stays clean
    /// and can mix different concrete middleware types freely.
    public init(
        reducer: TReducer,
        middleware: [any MiddlewareType<TReducer.Action, TReducer.State>],
        maxDispatchDepth: Int = .max,
        maxActionFrequency: Int = 20,
        cycleWindow: Duration = .seconds(1),
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        self.init(
            reducer: reducer,
            middleware: middleware.map { AnyMiddleware($0) },
            maxDispatchDepth: maxDispatchDepth,
            maxActionFrequency: maxActionFrequency,
            cycleWindow: cycleWindow,
            content: content
        )
    }

    /// Convenience init that accepts middleware via a `@MiddlewareBuilder` closure.
    /// Enables declarative middleware composition without array brackets or commas:
    ///
    /// ```swift
    /// StoreContainerView(reducer: HomeReducer()) {
    ///     HomeMiddleware(user: user)
    ///     LoggingMiddleware<HomeReducer>()
    /// } content: { store in
    ///     Text(store.state.counter)
    /// }
    /// ```
    public init(
        reducer: TReducer,
        maxDispatchDepth: Int = .max,
        maxActionFrequency: Int = 20,
        cycleWindow: Duration = .seconds(1),
        @MiddlewareBuilder<TReducer.Action, TReducer.State> middleware: () -> [Middleware],
        @ViewBuilder content: @escaping (Store) -> Content
    ) {
        self.init(
            reducer: reducer,
            middleware: middleware(),
            maxDispatchDepth: maxDispatchDepth,
            maxActionFrequency: maxActionFrequency,
            cycleWindow: cycleWindow,
            content: content
        )
    }
}
