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

        // F1.3: verify+prove above persisted a measurement record locally
        // (MeasurementStore.persist); this confirms it also syncs to the
        // collector. The first local-network request on a fresh install
        // triggers iOS's one-time "Local Network" permission alert, which
        // would otherwise swallow the tap silently - auto-accept it.
        let interruption = addUIInterruptionMonitor(withDescription: "Local Network permission") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }

        app.buttons["syncRecords"].tap()
        // XCUITest only evaluates interruption monitors on the next
        // interaction; tap the inert log view (not a button) so this can't
        // accidentally trigger another prove/verify action.
        app.staticTexts["proof_log"].tap()
        let syncText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "synced")).firstMatch
        XCTAssertTrue(syncText.waitForExistence(timeout: 15), "Measurement sync did not complete in time")
    }
}
