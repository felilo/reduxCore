//
//  Scope.swift
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

/// Connects a child reducer to a slice of parent state and a subset of parent actions.
///
/// Use `Scope` inside a parent reducer's `reduce(action:state:)` to delegate
/// responsibility for a sub-feature without writing imperative `case` blocks.
/// The parent action enum still needs a wrapping case, but the routing logic
/// is declarative and co-located with the composition rather than spread across
/// a large switch statement.
///
/// **Usage**
/// ```swift
/// func reduce(action: HomeAction, state: inout HomeState) {
///     // Parent-owned logic
///     switch action { ... }
///
///     // Sub-feature delegation
///     Scope(state: \.headerState, action: { guard case .header(let a) = $0 else { return nil }; return a }) {
///         HeaderHomeReducer()
///     }
///     .reduce(action: action, state: &state)
/// }
/// ```
///
/// **Adding a new sub-feature** only requires one new `Scope` block here.
/// The child reducer itself never needs to import or reference the parent.
public struct Scope<ParentAction, ParentState: Statable, Child: ReducerType>: ReducerType {

    public typealias Action = ParentAction
    public typealias State  = ParentState

    private let stateKey: WritableKeyPath<ParentState, Child.State>
    private let actionMap: (ParentAction) -> Child.Action?
    private let childReducer: Child

    /// Creates a scoped reducer.
    ///
    /// - Parameters:
    ///   - stateKey:  Key path from parent state to the child state slice.
    ///   - actionMap: Closure that extracts a child action from a parent action,
    ///                returning `nil` when the action is not relevant to this child.
    ///   - reducer:   Builder closure that produces the child reducer instance.
    public init(
        state stateKey: WritableKeyPath<ParentState, Child.State>,
        action actionMap: @escaping (ParentAction) -> Child.Action?,
        @ScopeReducerBuilder<Child> reducer: () -> Child
    ) {
        self.stateKey = stateKey
        self.actionMap = actionMap
        self.childReducer = reducer()
    }

    /// Returns a `ParentState` whose child slice is initialised from the child
    /// reducer's `initialState()` rather than from `ParentState()` alone.
    /// This ensures a child reducer that overrides `initialState()` with custom
    /// logic is respected when the parent boots, instead of being silently discarded.
    public func initialState() -> ParentState {
        var parent = ParentState()
        parent[keyPath: stateKey] = childReducer.initialState()
        return parent
    }

    public func reduce(action: ParentAction, state: inout ParentState) {
        guard let childAction = actionMap(action) else { return }
        childReducer.reduce(action: childAction, state: &state[keyPath: stateKey])
    }
}

/// Trivial single-expression builder so the `Scope` initialiser accepts a
/// trailing closure that returns any `ReducerType` directly.
@resultBuilder
public enum ScopeReducerBuilder<R: ReducerType> {
    public static func buildBlock(_ reducer: R) -> R { reducer }
}
