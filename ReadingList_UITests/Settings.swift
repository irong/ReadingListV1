import XCTest

class Settings: XCTestCase {

    private let defaultLaunchArguments = ["--reset", "--UITests", "--UITests_PopulateData"]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testExportBook() {
        let app = ReadingListApp()
        app.launchArguments = defaultLaunchArguments
        app.launch()

        app.clickTab(.settings)
        app.tables.staticTexts["Import / Export"].tap()
        app.tables.staticTexts["Export"].tap()

        let cancel = app.buttons["Cancel"]
        if UIDevice.current.userInterfaceIdiom != .pad {
            XCTAssert(cancel.waitForExistence(timeout: 5))
            cancel.tap()
        }
    }

    func testSortOrders() {
        let app = ReadingListApp()
        app.launchArguments = defaultLaunchArguments
        app.launch()

        func testAllSorts() {
            let sortButton = app.tables.otherElements.firstMatch.children(matching: .button).element
            var buttonIndex = 0
            while true {
                sortButton.tap()
                let chooseOrderSheet = app.sheets["Choose Order"]
                let sortSheetButton = chooseOrderSheet.buttons.element(boundBy: buttonIndex)
                if !sortSheetButton.exists {
                    chooseOrderSheet.buttons.element(boundBy: buttonIndex - 1).tap()
                    break
                }
                sortSheetButton.tap()
                buttonIndex += 1
            }
        }

        app.clickTab(.toRead)
        testAllSorts()

        app.clickTab(.finished)
        testAllSorts()
    }
}
