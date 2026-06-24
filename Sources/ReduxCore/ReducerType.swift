//
//  ReducerType.swift
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

/// The core reducer contract.
///
/// A reducer is a pure function: given an action and the current state (mutated in place),
/// it applies the action's changes directly to `state`.
///
/// - `initialState()` has a default implementation (`State()`) for reducers whose
///   `State` conforms to `Statable`. Override it when the starting state requires
///   custom logic (e.g. loading from disk, injecting dependencies).
/// - `reduce(action:state:)` is called on every subsequent dispatch; `state` is `inout`
///   so mutations are direct and no intermediate copy needs to be returned.
public protocol ReducerType<Action, State> {
    associatedtype Action
    associatedtype State: Statable

    /// Returns the initial state for this reducer. Defaults to `State()`.
    func initialState() -> State

    /// Applies `action` to `state` in place.
    func reduce(action: Action, state: inout State)
}

public extension ReducerType {
    func initialState() -> State { State() }

    /// Composes this reducer with another, running both sequentially on the same
    /// action and state. The first reducer runs before the second.
    ///
    /// ```swift
    /// let composed = ReducerA().combined(with: ReducerB())
    /// ```
    func combined<Other: ReducerType>(
        with other: Other
    ) -> CombinedReducer<Self, Other>
    where Other.Action == Action, Other.State == State {
        CombinedReducer(first: self, second: other)
    }
}

/// A reducer that runs two reducers sequentially on the same action and state.
/// Created via `ReducerType.combined(with:)`.
public struct CombinedReducer<First: ReducerType, Second: ReducerType>: ReducerType
where First.Action == Second.Action, First.State == Second.State {

    public typealias Action = First.Action
    public typealias State  = First.State

    let first: First
    let second: Second

    public func reduce(action: Action, state: inout State) {
        first.reduce(action: action, state: &state)
        second.reduce(action: action, state: &state)
    }
}
