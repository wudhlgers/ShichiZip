import XCTest

final class PasswordVaultUITests: ShichiZipUITestCase {
    override var additionalLaunchEnvironment: [String: String] {
        ["SHICHIZIP_UI_TEST_IN_MEMORY_PASSWORD_VAULT": "1"]
    }

    override var additionalLaunchArguments: [String] {
        ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    func testToolsMenuOpensLibraryAndPasswordCanBeManaged() {
        openLibraryFromToolsMenu()
        let window = passwordWindow
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.staticTexts["No Passwords Yet"].waitForExistence(timeout: 5))

        addPassword(title: "UI Test Password", password: "ui-test-secret", window: window)
        XCTAssertTrue(window.staticTexts["UI Test Password"].waitForExistence(timeout: 5))

        let search = window.textFields["passwordVault.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("UI Test")
        XCTAssertTrue(window.staticTexts["UI Test Password"].waitForExistence(timeout: 5))

        let favorite = window.buttons["passwordVault.favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.click()

        let delete = window.buttons["passwordVault.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()

        let confirmDelete = app.alerts["Delete Password?"].buttons["Delete"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.click()

        let clearSearch = window.buttons["passwordVault.clearSearch"]
        if clearSearch.exists {
            clearSearch.click()
        }
        XCTAssertTrue(window.staticTexts["No Passwords Yet"].waitForExistence(timeout: 5))

        app.typeKey("w", modifierFlags: .command)
    }

    func testToolbarOpensTheSameLibraryWindow() {
        let toolbarButton = app.windows.firstMatch.toolbars.buttons["Passwords"]
        XCTAssertTrue(toolbarButton.waitForExistence(timeout: 10),
                      "The main window toolbar should expose the password library")
        toolbarButton.click()

        XCTAssertTrue(passwordWindow.waitForExistence(timeout: 10))
        XCTAssertEqual(passwordWindows.count, 1)

        openLibraryFromToolsMenu()
        XCTAssertEqual(passwordWindows.count, 1,
                       "Reopening should reuse the existing library window")
    }

    func testPickerFillsExtractDialogPassword() throws {
        let (archiveURL, _) = try makeTestArchive(named: "uitest-archive",
                                                  payloads: ["payload.txt": "picker content"],
                                                  password: "archive-side")

        // Seed a library entry titled with the archive base name so the
        // picker's "This Archive" scope matches it via the shared rules.
        openLibraryFromToolsMenu()
        let libraryWindow = passwordWindow
        XCTAssertTrue(libraryWindow.waitForExistence(timeout: 10))
        addPassword(title: "uitest-archive", password: "picker-secret", window: libraryWindow)
        XCTAssertTrue(libraryWindow.staticTexts["uitest-archive"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)

        // Open the extract dialog for that archive.
        navigateLeftPane(to: archiveURL.deletingLastPathComponent().path)
        let table = leftPaneTable
        XCTAssertTrue(table.waitForExistence(timeout: 10))
        let archiveCell = table.cells.staticTexts[archiveURL.lastPathComponent]
        XCTAssertTrue(archiveCell.waitForExistence(timeout: 5))
        archiveCell.click()
        app.menuBars.menuBarItems["File"].menus.menuItems["Extract…"].click()

        let passwordField = app.secureTextFields.matching(identifier: "extract.password").firstMatch
        XCTAssertTrue(passwordField.waitForExistence(timeout: 10))

        let choose = app.buttons.matching(identifier: "extract.openPasswordLibrary").firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.click()

        let rail = app.descendants(matching: .any).matching(identifier: "passwordVault.picker.rail").firstMatch
        XCTAssertTrue(rail.waitForExistence(timeout: 10),
                      "The picker should expose its scope rail")
        let pickerList = app.descendants(matching: .any).matching(identifier: "passwordVault.picker.list").firstMatch
        let matchedRow = pickerList.staticTexts["uitest-archive"]
        XCTAssertTrue(matchedRow.waitForExistence(timeout: 10),
                      "The archive-titled entry should appear in the default scope")
        matchedRow.click()

        let reveal = pickerList.buttons.matching(identifier: "passwordVault.picker.reveal").firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5),
                      "Picker rows should expose a reveal toggle")
        reveal.click()
        XCTAssertTrue(pickerList.staticTexts["picker-secret"].waitForExistence(timeout: 5),
                      "Revealing should show the password in the row")
        reveal.click()
        XCTAssertFalse(pickerList.staticTexts["picker-secret"].exists,
                       "Hiding should mask the password again")

        let usePassword = app.buttons.matching(identifier: "modal.button.1").firstMatch
        XCTAssertTrue(usePassword.waitForExistence(timeout: 5))
        XCTAssertTrue(usePassword.isEnabled, "Selecting a row must enable Use Password")
        usePassword.click()

        // Secure-field accessibility values are masked; verify through the
        // plain field like the archive-update tests do.
        let showPassword = app.checkBoxes.matching(identifier: "extract.showPassword").firstMatch
        XCTAssertTrue(showPassword.waitForExistence(timeout: 5))
        if showPassword.value as? String != "1" {
            showPassword.click()
        }
        let plainField = app.textFields.matching(identifier: "extract.passwordPlain").firstMatch
        XCTAssertTrue(plainField.waitForExistence(timeout: 5))
        XCTAssertEqual(plainField.value as? String, "picker-secret",
                       "The picked password must land in the extract password field")

        app.buttons.matching(identifier: "modal.button.0").firstMatch.click()
    }

    // MARK: - Helpers

    private var passwordWindow: XCUIElement {
        app.windows["Password Library"]
    }

    private var passwordWindows: [XCUIElement] {
        app.windows.allElementsBoundByIndex.filter { $0.title == "Password Library" }
    }

    private func openLibraryFromToolsMenu() {
        app.menuBars.menuBarItems["Tools"].menus.menuItems["Password Library…"].click()
    }

    private func addPassword(title: String, password: String, window: XCUIElement) {
        let add = window.buttons["passwordVault.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()

        let titleField = app.textFields["passwordVault.editor.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.click()
        titleField.typeText(title)

        let passwordField = app.secureTextFields["passwordVault.editor.password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5))
        passwordField.click()
        passwordField.typeText(password)

        let save = app.buttons["passwordVault.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.click()
    }
}
