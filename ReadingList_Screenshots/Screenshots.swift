import XCTest

class Screenshots: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false

        let app = ReadingListApp()
        setupSnapshot(app)
        app.launchArguments = ["--reset", "--UITests", "--UITests_PopulateData", "--UITests_Screenshots", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXL"]
        app.launch()
        sleep(5)
    }

    func testSnapshot() {
        // Screenshot is designed for iOS 12 only
        guard #available(iOS 12.0, *) else { return }

        let app = ReadingListApp()
        app.clickTab(.toRead)

        let isIpad = app.navigationBars.count == 2
        if isIpad {
            app.tables.cells.element(boundBy: 2).tap()
        }

        snapshot("0_ToReadList")
        app.clickTab(.finished)
        app.swipeUp()
        app.tables.staticTexts["The Color Purple"].tap()
        snapshot("1_BookDetails")

        if !isIpad {
            // go back
            app.navigationBars["The Color Purple"].buttons["Finished"].tap()
        }
        if isIpad {
            app.tables.staticTexts["The Great Gatsby"].tap()
            app.swipeDown()
        }
        app.navigationBars["Finished"].buttons["Add"].tap()
        app.sheets["Add New Book"].buttons["Scan Barcode"].tap()
        snapshot("2_ScanBarcode")

        app.navigationBars["Scan Barcode"].buttons["Cancel"].tap()

        app.tabBars.buttons["Finished"].tap()
        app.tables.element(boundBy: 0).swipeDown()

        let yourLibrarySearchField = app.searchFields["Your Library"]
        yourLibrarySearchField.tap()
        yourLibrarySearchField.typeText("Orwell")
        app.buttons["Done"].tap()

        if isIpad {
            app.tables.staticTexts["1984"].tap()
        }

        snapshot("3_SearchFinished")
        app.buttons["Cancel"].tap()

        if isIpad {
            app.tables.cells.element(boundBy: 3).tap()
        }
        app.navigationBars["Finished"].buttons["Edit"].tap()
        app.tables.cells.element(boundBy: 3).tap()
        app.tables.cells.element(boundBy: 6).tap()
        app.tables.cells.element(boundBy: 7).tap()
        snapshot("4_BulkEdit")

        app.tabBars.buttons.element(boundBy: 2).tap()
        app.tables.cells.element(boundBy: 0).tap()
        if isIpad {
            app.tables.cells.element(boundBy: 6).tap()
        } else {
            app.swipeUp()
        }
        snapshot("5_Organise")

        app.tabBars.buttons["Settings"].tap()
        app.tables.staticTexts["General"].tap()
        app.tables.staticTexts["Black"].tap()
        app.tabBars.buttons["To Read"].tap()
        snapshot("6_DarkMode")
    }
}
