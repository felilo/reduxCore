//
//  StoreScreen.swift
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

/// Attached member macro that synthesises a `body` property for a SwiftUI view
/// that owns a Redux store.
///
/// Apply it to any `struct` that conforms to `View` and declares:
/// - `var middleware: [AnyMiddleware<Action, State>]` — the middleware stack (use `@MiddlewareBuilder` for declarative composition)
/// - `func content(_ store: ObservableStore<R>) -> some View` — the screen UI
///
/// The macro generates:
///
/// ```swift
/// var body: some View {
///     StoreContainerView(reducer: <reducer>, middleware: middleware, content: content)
/// }
/// ```
///
/// Because `middleware` is a property on `self`, it can reference other
/// init parameters (e.g. an injected user or API client).
///
/// **Usage**
///
/// Pass the reducer type (preferred — macro calls `init()` for you):
/// ```swift
/// @StoreView(reducer: HomeReducer)
/// struct HomeScreen: View {
///     let user: User
///
///     @MiddlewareBuilder<HomeAction, HomeState>
///     var middleware: [AnyMiddleware<HomeAction, HomeState>] {
///         HomeMiddleware(user: user)
///         LoggingMiddleware<HomeReducer>()
///     }
///
///     func content(_ store: ObservableStore<HomeReducer>) -> some View {
///         Text("\(store.state.counter)")
///     }
/// }
/// ```
///
/// Or pass an explicit instance when the reducer needs arguments:
/// ```swift
/// @StoreView(reducer: MyReducer(config: .default))
/// ```
///
/// - Parameter reducer: The reducer type or an instance of a `ReducerType`.
/// - Parameter maxDispatchDepth: Maximum synchronous re-entrant dispatch depth before the cycle guard breaks the chain. Default: `.max` (unlimited). Active only in `DEBUG` builds.
/// - Parameter maxActionFrequency: Maximum times the same action may be dispatched within `cycleWindow` before a warning is logged. Pass `0` to disable. Default: `20`. Active only in `DEBUG` builds.
/// - Parameter cycleWindow: Time window used by `maxActionFrequency`. Default: `.seconds(1)`. Active only in `DEBUG` builds.
@attached(member, names: named(body), named(Store), named(Middleware), named(MiddlewareResultBuilder))
public macro StoreView<R: ReducerType>(
    reducer: R,
    maxDispatchDepth: Int = .max,
    maxActionFrequency: Int = 20,
    cycleWindow: Duration = .seconds(1)
) = #externalMacro(module: "ReduxCoreMacros", type: "StoreViewMacro")

/// Overload that accepts a metatype — `@StoreView(reducer: HomeReducer.self)`.
/// The macro calls `init()` on the type when generating the `body`.
@attached(member, names: named(body), named(Store), named(Middleware), named(MiddlewareResultBuilder))
public macro StoreView<R: ReducerType>(
    reducer: R.Type,
    maxDispatchDepth: Int = .max,
    maxActionFrequency: Int = 20,
    cycleWindow: Duration = .seconds(1)
) = #externalMacro(module: "ReduxCoreMacros", type: "StoreViewMacro")
