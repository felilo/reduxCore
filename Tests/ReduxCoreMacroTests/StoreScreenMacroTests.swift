//
//  StoreScreenMacroTests.swift
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

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(ReduxCoreMacros)
@testable import ReduxCoreMacros
//TaskCancellationManager

// Map macro name to its implementation for assertMacroExpansion
private let testMacros: [String: Macro.Type] = [
    "StoreView": StoreViewMacro.self
]

final class StoreViewMacroTests: XCTestCase {

    // MARK: - Valid expansion

    func testValidExpansion_generatesBodyWithReducerExpression() {
        assertMacroExpansion(
            """
            @StoreView(reducer: HomeReducer())
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    Text("Hello")
                }

                typealias Store = ObservableStore<HomeReducer>

                typealias Middleware = AnyMiddleware<HomeReducer.Action, HomeReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<HomeReducer.Action, HomeReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: HomeReducer(),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    func testValidExpansion_preservesComplexReducerExpression() {
        assertMacroExpansion(
            """
            @StoreView(reducer: MyReducer(config: .default))
            struct MyScreen: View {
                var middleware: [any MiddlewareType<MyAction, MyState>] { [] }
                func content(_ store: ObservableStore<MyReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            expandedSource: """
            struct MyScreen: View {
                var middleware: [any MiddlewareType<MyAction, MyState>] { [] }
                func content(_ store: ObservableStore<MyReducer>) -> some View {
                    EmptyView()
                }

                typealias Store = ObservableStore<MyReducer>

                typealias Middleware = AnyMiddleware<MyReducer.Action, MyReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<MyReducer.Action, MyReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: MyReducer(config: .default),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    func testValidExpansion_metatypeAppendsCallParens() {
        assertMacroExpansion(
            """
            @StoreView(reducer: HomeReducer.self)
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    Text("Hello")
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    Text("Hello")
                }

                typealias Store = ObservableStore<HomeReducer>

                typealias Middleware = AnyMiddleware<HomeReducer.Action, HomeReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<HomeReducer.Action, HomeReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: HomeReducer(),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - Error: missing reducer: label

    func testError_missingReducerLabel_producesError() {
        assertMacroExpansion(
            """
            @StoreView(HomeReducer())
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires exactly one argument: reducer:",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testError_wrongLabel_producesError() {
        assertMacroExpansion(
            """
            @StoreView(myReducer: HomeReducer())
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires exactly one argument: reducer:",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    func testError_noArguments_producesError() {
        assertMacroExpansion(
            """
            @StoreView()
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires exactly one argument: reducer:",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Error: missing middleware

    func testError_missingMiddlewares_producesDiagnostic() {
        assertMacroExpansion(
            """
            @StoreView(reducer: HomeReducer())
            struct HomeScreen: View {
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                func content(_ store: ObservableStore<HomeReducer>) -> some View {
                    EmptyView()
                }

                typealias Store = ObservableStore<HomeReducer>

                typealias Middleware = AnyMiddleware<HomeReducer.Action, HomeReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<HomeReducer.Action, HomeReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: HomeReducer(),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires 'var middleware: [Middleware]' to be declared on the struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Error: missing content

    func testError_missingContent_producesDiagnostic() {
        assertMacroExpansion(
            """
            @StoreView(reducer: HomeReducer())
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }
            }
            """,
            expandedSource: """
            struct HomeScreen: View {
                var middleware: [any MiddlewareType<HomeAction, HomeState>] { [] }

                typealias Store = ObservableStore<HomeReducer>

                typealias Middleware = AnyMiddleware<HomeReducer.Action, HomeReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<HomeReducer.Action, HomeReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: HomeReducer(),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires 'func content(store: Store) -> some View' to be declared on the struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - Error: missing both middleware and content

    func testError_missingBoth_producesBothDiagnostics() {
        assertMacroExpansion(
            """
            @StoreView(reducer: HomeReducer())
            struct HomeScreen: View {
            }
            """,
            expandedSource: """
            struct HomeScreen: View {

                typealias Store = ObservableStore<HomeReducer>

                typealias Middleware = AnyMiddleware<HomeReducer.Action, HomeReducer.State>

                typealias MiddlewareResultBuilder = MiddlewareBuilder<HomeReducer.Action, HomeReducer.State>

                var body: some View {
                    StoreContainerView(
                        reducer: HomeReducer(),
                        middleware: middleware,
                        content: { store in
                            content(store: store)
                        }
                    )
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@StoreView requires 'var middleware: [Middleware]' to be declared on the struct",
                    line: 1,
                    column: 1
                ),
                DiagnosticSpec(
                    message: "@StoreView requires 'func content(store: Store) -> some View' to be declared on the struct",
                    line: 1,
                    column: 1
                )
            ],
            macros: testMacros
        )
    }
}
#endif
