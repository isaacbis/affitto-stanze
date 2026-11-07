# Verifiche della correzione — 1.0.0 (8)

Data: 7 novembre 2026. Xcode 27.2 (27B52).

- **Backend: 10/10 test superati** (`npm test`), con Firestore/APNs simulati. Coprono accesso, ruoli, conflitti e cancellazioni, note private, utenti/stanze, report e notifiche. Nessuna prenotazione reale creata o cancellata.
- **Sessioni e date Swift: superati** (`python3 test/check-ios.py`). Sessione scaduta, cambio account con refresh fallito, logout e date di Roma.
- **Coordinatore pubblicitario di produzione: superato** (`python3 test/check-advertising.py`). Compilato in isolamento con servizi simulati: ATT denied/restricted/notDetermined, ordine ATT → UMP → SDK, errori aggiornamento/modulo e retry, UMP senza permesso annunci, app inattiva, revoca durante le operazioni asincrone, riapertura privacy e avvio unico.
- **Compilazione Debug per simulatore: riuscita**.
- **UI su iPhone 17 Pro Max, iOS Simulator 26.5: tre scenari superati**: prenotazione amministratore con nota privata; controlli notifiche nel profilo; richiesta ATT reale e prenotazione utente dopo “Non tracciarmi”. API prenotazioni simulate, notifiche isolate. Il primo tentativo del terzo test è fallito sul selettore del pulsante italiano; corretto includendo “Non tracciarmi”, poi superato. Il testo e il prompt dell’app non erano difettosi. Screenshot del tentativo riuscito nella cartella di distribuzione.
- **Archivio Release build 8: riuscito**, poi ricreato dopo aggiunta del manifest privacy. Verificati plist, risorsa privacy e metadati SDK. Ripetuti anche i tre test UI con il manifest finale: 3/3 superati. Il test ATT reimposta la scelta con XCTest per essere ripetibile sullo stesso simulatore.
- **Esportazione App Store Connect: riuscita**, destinazione `export`, nessun upload. IPA finale verificata dopo estrazione: `codesign --verify --deep --strict` passato; bundle `com.isaacmorganti.affittostanze`, 1.0.0 (8), manifest app e manifest dei due SDK presenti, descrizione ATT presente, APNs `production`, `get-task-allow=false`.
- SHA-256 IPA: `50519803a9f01fccad38cd2f45b0f2c2dd688d8d8041f9a6b57ace4f482e03ff`.
- **HTTP pubblici**: health/privacy/support/app-ads.txt restituiscono 200. Privacy online ancora precedente al nuovo flusso; nessun deploy eseguito.

Il File Provider di macOS aggiunge metadati Finder ai bundle nella cartella Documents: una verifica strict direttamente sull’archivio locale può segnalarli. L’archivio Xcode può inoltre avere firma di sviluppo prima dell’esportazione. La verifica conclusiva sopra riguarda il payload estratto dall’IPA App Store effettivamente esportata, con firma di distribuzione e senza quei metadati.

Non verificati in questa sessione: invio o approvazione Apple, stato effettivo di App Privacy in console, impostazioni remote AdMob, cattura completa del traffico pubblicitario, modulo UMP reale dopo accettazione ATT in più regioni, consegna push su dispositivo fisico. I test simulati dimostrano il controllo applicativo; non certificano il trattamento interno dei fornitori.

Artefatti: `distribuzione/ipa-build8/AffittoStanze.ipa`, `distribuzione/AffittoStanze-1.0.0-build8.xcarchive`, `distribuzione/revisione-2026-11-07/` (log, schermate, verifica JSON, risposta e rapporto privacy).
