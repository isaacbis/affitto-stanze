import XCTest

final class CompactScreensTests:XCTestCase {
    func preview(_ route:String?=nil,login:Bool=false)->XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["--ui-preview"]+(route.map{["--ui-route=\($0)"]} ?? [])+(login ? ["--ui-login"] : [])
        app.launch();return app
    }
    func capture(_ name:String,_ app:XCUIApplication) {
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    func testLoginFitsWithKeyboard() {
        let app=preview(login:true)
        let username=app.textFields["login.username"]
        XCTAssertTrue(username.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["advertising.preview"].exists);capture("Login",app)
        username.tap();username.typeText("preview")
        XCTAssertFalse(app.staticTexts["advertising.preview"].exists)
        // Compact phones use a second step when the keyboard reduces the space.
        if app.buttons["Continua"].exists {app.buttons["Continua"].tap()}
        let password=app.secureTextFields["login.password"]
        XCTAssertTrue(password.waitForExistence(timeout:3));XCTAssertTrue(password.isHittable)
        capture("Login con tastiera",app)
        XCTAssertTrue(app.buttons["Accedi"].isHittable)
    }
    func testEveryMainScreenUsesPages() {
        for route in ["users","rooms","reports","bookings","booking","profile","password"] {
            let app=preview(route)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout:10))
            // Wait for the mocked initial data, not for a live network.
            if route == "users" {XCTAssertTrue(app.staticTexts["Utente 1"].waitForExistence(timeout:5))}
            if route == "rooms" {XCTAssertTrue(app.staticTexts["Sala 1"].waitForExistence(timeout:5))}
            XCTAssertEqual(app.scrollViews.count,0,"Unexpected scrolling in \(route)")
            if route == "bookings" {app.buttons["Tutte"].tap()}
            if ["users","rooms","bookings"].contains(route) {
                let next=app.buttons["Pagina successiva"]
                XCTAssertTrue(next.waitForExistence(timeout:5));XCTAssertTrue(next.isHittable);next.tap()
                XCTAssertTrue(app.buttons["Pagina precedente"].isEnabled)
            }
            capture(route,app);app.terminate()
        }
    }
    func testCreateRoomAndUserKeyboardFit() {
        for route in ["new-room","new-user"] {
            let app=preview(route)
            let field=app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText("Test")
            capture(route+" con tastiera",app)
            XCTAssertTrue(app.buttons[route == "new-room" ? "Crea stanza" : "Continua"].isHittable)
            app.terminate()
        }
    }
    func testFullBookingWizardWithPrivateNote() {
        let app=preview("booking")
        let room=app.buttons["booking.room"]
        XCTAssertTrue(room.waitForExistence(timeout:10));room.tap()
        app.buttons["Sala 1"].tap()
        app.buttons["booking.user"].tap()
        app.buttons["Utente 1"].tap()
        XCTAssertTrue(app.buttons["Continua"].isEnabled);app.buttons["Continua"].tap()
        XCTAssertTrue(app.staticTexts["Ora d’inizio"].exists);capture("Scelta inizio",app)
        app.buttons["Continua"].tap();XCTAssertTrue(app.staticTexts["Ora di fine"].exists)
        app.buttons["Continua"].tap()
        let note=app.textFields["Nota privata (facoltativa)"]
        XCTAssertTrue(note.exists);note.tap();note.typeText("Nota riservata di prova")
        XCTAssertTrue(app.buttons["Continua"].isHittable);app.buttons["Continua"].tap()
        capture("Riepilogo prenotazione",app)
        XCTAssertTrue(app.buttons["Conferma prenotazione"].isHittable)
        app.buttons["Conferma prenotazione"].tap()
        XCTAssertTrue(app.alerts["Prenotazione inserita"].waitForExistence(timeout:5))
    }

    func testRealTabsAndUserPermissions() {
        let app=preview()
        let manage=app.tabBars.buttons["Gestione"]
        XCTAssertTrue(manage.waitForExistence(timeout:10));capture("Home amministratore",app)
        manage.tap();app.buttons["Report e PDF"].tap()
        let export=app.buttons["Esporta e condividi PDF"]
        XCTAssertTrue(export.waitForExistence(timeout:5));XCTAssertTrue(export.isHittable);capture("Report con barra schede",app)
        app.terminate()
        let userApp=XCUIApplication();userApp.launchArguments=["--ui-preview","--ui-user"];userApp.launch()
        XCTAssertTrue(userApp.tabBars.buttons["Profilo"].waitForExistence(timeout:10))
        XCTAssertFalse(userApp.tabBars.buttons["Gestione"].exists)
        userApp.tabBars.buttons["Prenota"].tap()
        XCTAssertFalse(userApp.buttons["booking.user"].exists)
        XCTAssertTrue(userApp.buttons["booking.room"].isHittable);capture("Prenota utente",userApp)
    }

    func testBookingsUseEightRowsPerPage() {
        for route in ["home", "bookings"] {
            let app=preview(route == "home" ? nil : route)
            if route == "bookings" {
                XCTAssertTrue(app.buttons["Tutte"].waitForExistence(timeout:10));app.buttons["Tutte"].tap()
            }
            let rows=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "booking.row."))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:10))
            XCTAssertEqual(rows.count,8,"Eight bookings must be visible in \(route)")
            XCTAssertEqual(app.scrollViews.count,0)
            for index in 0..<rows.count {
                XCTAssertTrue(rows.element(boundBy:index).isHittable)
                XCTAssertGreaterThanOrEqual(rows.element(boundBy:index).frame.height,44)
            }
            capture("Otto prenotazioni - \(route)",app)
            app.buttons["Pagina successiva"].tap();XCTAssertEqual(rows.count,8)
            app.buttons["Pagina successiva"].tap();XCTAssertEqual(rows.count,2)
            app.buttons["Pagina precedente"].tap();XCTAssertEqual(rows.count,8)
            rows.firstMatch.tap();XCTAssertTrue(app.navigationBars["Dettaglio"].waitForExistence(timeout:3))
            app.terminate()
        }
    }

}
