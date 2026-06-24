//
//  MiddlewareBuilder.swift
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

/// A result builder that composes heterogeneous middleware into a typed array.
///
/// Each middleware is automatically type-erased via AnyMiddleware, so you can
/// mix different concrete middleware types in the same builder block:
///
///     StoreContainerView(HomeReducer()) {
///         LoggingMiddleware<HomeReducer>()
///         HomeMiddleware()
///     } content: { store in ... }
@resultBuilder
public struct MiddlewareBuilder<Action, State> {

    public typealias Erased = AnyMiddleware<Action, State>

    public static func buildExpression<M: MiddlewareType>(
        _ middleware: M
    ) -> [Erased] where M.Action == Action, M.State == State {
        [AnyMiddleware(middleware)]
    }

    public static func buildBlock(_ components: [Erased]...) -> [Erased] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [Erased]?) -> [Erased] {
        component ?? []
    }

    public static func buildEither(first component: [Erased]) -> [Erased] {
        component
    }

    public static func buildEither(second component: [Erased]) -> [Erased] {
        component
    }

    public static func buildArray(_ components: [[Erased]]) -> [Erased] {
        components.flatMap { $0 }
    }

    /// Enables `#available` guards inside builder blocks:
    ///
    /// ```swift
    /// @MiddlewareResultBuilder
    /// var middleware: [Middleware] {
    ///     if #available(iOS 18, *) {
    ///         NewPlatformMiddleware()
    ///     }
    ///     LoggingMiddleware<MyReducer>()
    /// }
    /// ```
    public static func buildLimitedAvailability(_ component: [Erased]) -> [Erased] {
        component
    }
}
