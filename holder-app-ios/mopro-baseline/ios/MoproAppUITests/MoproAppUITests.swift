//
//  MoproAppUITests.swift
//  MoproAppUITests
//

import XCTest

final class MoproAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    func testCircomProveVerify() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["proveCircom"].tap()
        let proveText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "1️⃣")).firstMatch
        XCTAssertTrue(proveText.waitForExistence(timeout: 30), "Proof generation did not complete in time")

        app.buttons["verifyCircom"].tap()
        let verifyText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "2️⃣")).firstMatch
        XCTAssertTrue(verifyText.waitForExistence(timeout: 10), "Proof verification did not complete in time")
    }
}
