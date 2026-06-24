//
//  TaskListUITests.swift
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

import XCTest

/**final class TaskListUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Launch

    @MainActor
    func testAppLaunchesAndShowsNavigationTitle() throws {
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    // MARK: - List

    @MainActor
    func testTaskListAppearsAfterLoading() throws {
        // Dismiss progress view by waiting for at least one cell
        let firstCell = app.cells.firstMatch
        XCTAssertTrue(firstCell.waitForExistence(timeout: 5))
    }

    // MARK: - Add task

    @MainActor
    func testAddButtonIsVisible() throws {
        XCTAssertTrue(app.buttons["Add Task"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTappingAddButtonCreatesNewTask() throws {
        let countBefore = app.cells.count
        app.buttons["Add Task"].tap()
        // Wait for the new cell to appear (middleware round-trip + animation)
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", countBefore),
            object: app.cells
        )
        wait(for: [expectation], timeout: 5)
    }

    // MARK: - Search

    @MainActor
    func testSearchBarFiltersResults() throws {
        // Wait for tasks to load
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("zzz_no_match")

        // ContentUnavailableView should appear
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 3))
    }

    // MARK: - Delete task

    @MainActor
    func testSwipeToDeleteRemovesTask() throws {
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))

        let countBefore = app.cells.count
        guard countBefore > 0 else { return }

        app.cells.firstMatch.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d", countBefore),
            object: app.cells
        )
        wait(for: [expectation], timeout: 5)
    }
}
*/
