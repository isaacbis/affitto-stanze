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
    func testTrackingDenialKeepsBookingsUsable() {
        // Real system ATT prompt; the booking API and notifications remain isolated.
        // Reset the system choice so this test is repeatable on the same simulator.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview","--ui-user","--ui-ad-consent"]
        app.resetAuthorizationStatus(for:.userTracking)
        app.launch()
        let alert = XCUIApplication(bundleIdentifier:"com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout:15), "Use a fresh simulator for the ATT prompt")
        capture("Richiesta ATT prima della pubblicità",XCUIApplication(bundleIdentifier:"com.apple.springboard"))
        let deny = alert.buttons.matching(NSPredicate(format:"label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Ask App Not to Track", "non tracciare", "Non tracciarmi")).firstMatch
        XCTAssertTrue(deny.exists)
        deny.tap()
        XCTAssertTrue(app.tabBars.buttons["Prenota"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["advertising.preview"].exists)
        app.tabBars.buttons["Prenota"].tap()
        app.buttons["booking.room"].tap();app.buttons["Sala 1"].tap()
        app.buttons["Continua"].tap();app.buttons["Continua"].tap();app.buttons["Continua"].tap()
        XCTAssertTrue(app.buttons["Conferma prenotazione"].isHittable)
        app.buttons["Conferma prenotazione"].tap()
        XCTAssertTrue(app.alerts["Prenotazione inserita"].waitForExistence(timeout:5))
        capture("Prenotazione dopo rifiuto ATT",app)
    }
    func testNotificationOpensAuthorizedBookingAndHandlesCancellation() {
        for type in ["created","deleted","other-user"] {
            let app=XCUIApplication();app.launchArguments=["--ui-preview","--ui-notification=\(type)"];app.launch()
            if type=="created" {
                XCTAssertTrue(app.navigationBars["Dettaglio"].waitForExistence(timeout:10))
                XCTAssertTrue(app.buttons["Fine"].isHittable)
            } else if type=="deleted" {
                XCTAssertTrue(app.alerts["Prenotazione cancellata"].waitForExistence(timeout:10))
                app.alerts.buttons["OK"].tap()
                XCTAssertTrue(app.buttons["Tutte"].isHittable)
            } else {
                XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:10))
                XCTAssertFalse(app.navigationBars["Dettaglio"].exists)
                XCTAssertFalse(app.alerts["Prenotazione cancellata"].exists)
            }
            capture("Apertura notifica - \(type)",app);app.terminate()
        }
    }
    func testNotificationSettingsFitOnProfile() {
        let app=preview("profile")
        XCTAssertTrue(app.buttons["notifications.toggle"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["notifications.toggle"].isHittable)
        XCTAssertTrue(app.buttons["Esci dall’account"].isHittable)
        XCTAssertEqual(app.scrollViews.count,0)
        capture("Profilo con notifiche",app)
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
            if route == "bookings" {
                app.buttons["Tutte"].tap()
                XCTAssertTrue(app.scrollViews["bookings.list"].waitForExistence(timeout:5))
            }
            XCTAssertEqual(app.scrollViews.count,route == "bookings" ? 1 : 0,"Unexpected scrolling in \(route)")
            if ["users","rooms"].contains(route) {
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

    func testBookingsScrollFiveRowsWithFixedHeaders() {
        for route in ["home", "bookings"] {
            let app=preview()
            XCTAssertTrue(app.tabBars.buttons["Prenotazioni"].waitForExistence(timeout:10))
            if route == "bookings" {
                app.tabBars.buttons["Prenotazioni"].tap()
                XCTAssertTrue(app.buttons["Tutte"].waitForExistence(timeout:5));app.buttons["Tutte"].tap()
            }
            let list=app.scrollViews["bookings.list"]
            XCTAssertTrue(list.waitForExistence(timeout:10))
            XCTAssertEqual(app.scrollViews.count,1)
            XCTAssertFalse(app.buttons["Pagina successiva"].exists)
            let header = route == "home" ? app.staticTexts.matching(identifier:"dashboard.metrics").firstMatch : app.buttons["Tutte"]
            XCTAssertTrue(header.exists)
            let headerFrame=header.frame
            let tabsFrame=app.tabBars.firstMatch.frame
            let rows=app.descendants(matching:.any).matching(NSPredicate(format:"identifier BEGINSWITH %@", "booking.row."))
            let fullyVisible=rows.allElementsBoundByIndex.filter {
                let frame=$0.frame, viewport=list.frame
                return frame.height >= 44 && frame.minY >= viewport.minY-1 && frame.maxY <= viewport.maxY+1
            }
            XCTAssertEqual(fullyVisible.count,5,"Five complete rows must fit in \(route)")
            let firstID=fullyVisible.first!.identifier
            capture("Cinque prenotazioni - \(route)",app)
            list.swipeUp()
            XCTAssertEqual(header.frame,headerFrame,"The header must stay fixed")
            XCTAssertEqual(app.tabBars.firstMatch.frame,tabsFrame)
            XCTAssertFalse(app.descendants(matching:.any)[firstID].isHittable)
            capture("Elenco dopo scorrimento - \(route)",app)
            // Reach the end of all 18 fixture bookings, without changing pages.
            for _ in 0..<5 {list.swipeUp()}
            XCTAssertEqual(header.frame,headerFrame)
            let visibleAtEnd=rows.allElementsBoundByIndex.filter {$0.isHittable && $0.frame.intersects(list.frame)}
            XCTAssertFalse(visibleAtEnd.isEmpty)
            XCTAssertTrue(app.descendants(matching:.any)["booking.row.booking-9"].isHittable,"The eighteenth booking must be reachable")
            capture("Fine elenco - \(route)",app)
            if route == "bookings" {
                app.buttons["Prossime"].tap();app.buttons["Tutte"].tap()
                XCTAssertTrue(app.descendants(matching:.any)[firstID].waitForExistence(timeout:3))
                XCTAssertTrue(app.descendants(matching:.any)[firstID].isHittable,"A changed filter resets to the first result")
                app.descendants(matching:.any)[firstID].tap()
            } else {visibleAtEnd.last!.tap()}
            XCTAssertTrue(app.navigationBars["Dettaglio"].waitForExistence(timeout:3))
            app.terminate()
        }
    }

}
