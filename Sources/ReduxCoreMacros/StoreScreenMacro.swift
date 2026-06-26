//
//  StoreScreenMacro.swift
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

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin
import SwiftDiagnostics

/// Implementation of `@StoreView(reducer:)`.
///
/// Accepts either a bare type (`HomeReducer`) or a call expression (`HomeReducer()`).
/// When a bare type is provided, the macro appends `()` in the generated code.
///
/// Given:
/// ```swift
/// @StoreView(reducer: HomeReducer)
/// struct HomeScreen: View {
///     @MiddlewareBuilder<HomeAction, HomeState>
///     var middleware: [AnyMiddleware<HomeAction, HomeState>] {
///         HomeMiddleware()
///         LoggingMiddleware<HomeReducer>()
///     }
///     func content(_ store: ObservableStore<HomeReducer>) -> some View { ... }
/// }
/// ```
///
/// Synthesises:
/// ```swift
/// var body: some View {
///     StoreContainerView(reducer: HomeReducer(), middleware: middleware, content: content)
/// }
/// ```
public struct StoreViewMacro: MemberMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // --- Extract reducer argument from @StoreView(reducer:) ---
        guard
            case .argumentList(let args) = node.arguments,
            let reducerArg = args.first(where: { $0.label?.text == "reducer" })
        else {
            throw MacroError.message(
                "@StoreView requires exactly one argument: reducer:"
            )
        }

        // --- Validate that the decorated type declares `middleware` ---
        let hasMiddleware = declaration.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            return variable.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "middleware" }
        }

        if !hasMiddleware {
            context.diagnose(
                Diagnostic(
                    node: declaration,
                    message: StoreViewDiagnostic.missingMiddleware
                )
            )
        }

        // --- Validate that the decorated type declares `content` ---
        let hasContent = declaration.memberBlock.members.contains { member in
            guard let function = member.decl.as(FunctionDeclSyntax.self) else { return false }
            return function.name.text == "content"
        }

        if !hasContent {
            context.diagnose(
                Diagnostic(
                    node: declaration,
                    message: StoreViewDiagnostic.missingContent
                )
            )
        }

        // Normalise the reducer expression so the generated code always calls init():
        //   HomeReducer()              → reducerExpr = HomeReducer(),      reducerTypeName = "HomeReducer"
        //   HomeReducer.self           → reducerExpr = HomeReducer(),      reducerTypeName = "HomeReducer"
        //   MyReducer(config:.default) → reducerExpr = MyReducer(config:…), reducerTypeName = "MyReducer"
        let rawExpr = reducerArg.expression.trimmed
        let reducerExpr: ExprSyntax
        let reducerTypeName: TokenSyntax

        if let call = rawExpr.as(FunctionCallExprSyntax.self) {
            // Already a call expression — use as-is; extract the callee as the type name.
            reducerExpr = rawExpr
            // Callee may be a simple identifier (HomeReducer) or a member access (Module.Reducer).
            // For the type alias we just use the raw callee text.
            let calleeText = call.calledExpression.trimmed.description
            reducerTypeName = TokenSyntax(stringLiteral: calleeText)
        } else if let memberAccess = rawExpr.as(MemberAccessExprSyntax.self),
                  memberAccess.declName.baseName.text == "self",
                  let base = memberAccess.base {
            // `Type.self` — drop `.self` and append `()`.
            reducerExpr = "\(base.trimmed)()"
            reducerTypeName = TokenSyntax(stringLiteral: base.trimmed.description)
        } else {
            // Bare identifier or anything else — append `()`.
            reducerExpr = "\(rawExpr)()"
            reducerTypeName = TokenSyntax(stringLiteral: rawExpr.description)
        }

        // --- Synthesise `typealias Store = ObservableStore<ReducerType>` ---
        // This lets screens write `func content(_ store: Store)` instead of the verbose generic form.
        let typeAliasDecl: DeclSyntax = """
            typealias Store = ObservableStore<\(reducerTypeName)>
            """

        // --- Synthesise `typealias Middleware = AnyMiddleware<R.Action, R.State>` ---
        // This lets screens write `var middleware: [Middleware]` instead of the verbose generic form.
        let middlewareAliasDecl: DeclSyntax = """
            typealias Middleware = AnyMiddleware<\(reducerTypeName).Action, \(reducerTypeName).State>
            """

        // --- Synthesise `typealias MiddlewareResultBuilder = MiddlewareBuilder<R.Action, R.State>` ---
        // Provides a concrete alias so screens can write `@MiddlewareResultBuilder` with no
        // angle-bracket type parameters. Named differently from `MiddlewareBuilder` to avoid
        // a recursive self-reference in the alias body.
        let middlewareBuilderAliasDecl: DeclSyntax = """
            typealias MiddlewareResultBuilder = MiddlewareBuilder<\(reducerTypeName).Action, \(reducerTypeName).State>
            """

        // Detect the struct's access level so the synthesised `body` satisfies the `View`
        // protocol requirement when the struct is declared `public` (or `open`).
        let accessPrefix: String
        if let modifiers = declaration.as(StructDeclSyntax.self)?.modifiers {
            if modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }) {
                accessPrefix = "public "
            } else if modifiers.contains(where: { $0.name.tokenKind == .keyword(.open) }) {
                accessPrefix = "open "
            } else {
                accessPrefix = ""
            }
        } else {
            accessPrefix = ""
        }

        // --- Collect optional cycle-detection arguments forwarded to StoreContainerView ---
        // Only include an argument in the generated call when it was explicitly provided by
        // the user — omitting it lets StoreContainerView fall back to its own defaults.
        let optionalParamLabels = ["maxDispatchDepth", "maxActionFrequency", "cycleWindow"]
        let extraParams = optionalParamLabels.compactMap { label -> String? in
            guard let arg = args.first(where: { $0.label?.text == label }) else { return nil }
            return "        \(label): \(arg.expression.trimmed),"
        }.joined(separator: "\n")
        let extraParamsLine = extraParams.isEmpty ? "" : "\n\(extraParams)"

        // --- Synthesise `var body: some View { ... }` ---
        // `middleware` and `content` are resolved from `self` — the screen declares them.
        // The closure wrapper is required because `content(store:)` has a labelled parameter,
        // so it cannot be passed directly as an unlabelled `(Store) -> Content` closure.
        let bodyDecl: DeclSyntax = """
            \(raw: accessPrefix)var body: some View {
                StoreContainerView(
                    reducer: \(reducerExpr),
                    middleware: middleware,\(raw: extraParamsLine)
                    content: { store in content(store: store) }
                )
            }
            """

        return [typeAliasDecl, middlewareAliasDecl, middlewareBuilderAliasDecl, bodyDecl]
    }
}

// MARK: - Diagnostics

enum StoreViewDiagnostic: DiagnosticMessage {
    case missingMiddleware
    case missingContent

    var message: String {
        switch self {
        case .missingMiddleware:
            return "@StoreView requires 'var middleware: [Middleware]' to be declared on the struct"
        case .missingContent:
            return "@StoreView requires 'func content(store: Store) -> some View' to be declared on the struct"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .missingMiddleware:
            return MessageID(domain: "ReduxCoreMacros", id: "missingMiddleware")
        case .missingContent:
            return MessageID(domain: "ReduxCoreMacros", id: "missingContent")
        }
    }

    var severity: DiagnosticSeverity { .error }
}

// MARK: - Error helper

enum MacroError: Error, CustomStringConvertible {
    case message(String)
    var description: String {
        switch self { case .message(let m): return m }
    }
}

// MARK: - Plugin entry point

@main
struct ReduxCoreMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        StoreViewMacro.self
    ]
}
