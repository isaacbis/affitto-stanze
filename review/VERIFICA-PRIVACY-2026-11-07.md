# Affitto Stanze — verifica App Review del 7 novembre 2026

## Evidenze e perimetro

- Letti i sette allegati originali IMG_9807–IMG_9813 dalla conversazione “Problemi revisione Apple”. La schermata iniziale identifica submission `968bcd0e-4af1-40da-a82c-60fdf4bd2839`, data 7 novembre 2026, build 1.0.0 (7), iPhone 17 Pro Max. Ricostruiti i sei quesiti esatti dai tre screenshot finali.
- Progetto attuale: `gestionale/`, commit di partenza `dcee190b778f68997fca966fad76896cfee7061e`, inizialmente senza modifiche locali. `AffittoStanze-Xcode/` è una copia più vecchia: non è stata usata come fonte della build attuale.
- Nell’archivio effettivo `distribuzione/AffittoStanze-1.0.0-build7.xcarchive`: bundle `com.isaacmorganti.affittostanze`, versione 1.0.0, build 7; Google Mobile Ads **13.12.0**, UMP **3.1.0**. Versioni coerenti con Package.resolved e dipendenze Xcode. Nessun altro framework incorporato nella cartella Frameworks.
- L’Info.plist della build 7 include GADDelayAppMeasurementInit ma non NSUserTrackingUsageDescription. Nei sorgenti della build 7 non c’è richiesta ATT. UMP precede MobileAds.start; le richieste sono npa=1, personalizzazione e publisher first-party ID disabilitati. Queste restrizioni **non dimostrano assenza di tracking**.
- Il manifest incluso in GoogleMobileAds dichiara Device ID collegato all’utente/dispositivo e utilizzabile per tracking. Non è una cattura del traffico effettivo della build 7: documenta le capacità dichiarate dall’SDK, non prova da solo quali dati siano partiti nella sessione Apple.
- Non riscontrati StoreKit, processori di pagamento, paywall, prezzi, abbonamenti, licenze o diritti digitali a pagamento nei sorgenti Swift, nelle dipendenze e nelle rotte Express esaminate. Il titolare conferma che non esistono pagamenti neppure esterni e che gli account vengono creati dall’amministratore. Il modello è gratuito con banner AdMob.

## Flussi dati verificati

| Dati | Destinazione e finalità | Note e conservazione riscontrata |
| --- | --- | --- |
| Username, ID account, ruolo, stato, data creazione | API HTTPS Node/Express su Render, Firestore `users`; autenticazione e autorizzazione | Account creati solo da amministratori. Password trasmessa per autenticazione, memorizzata con hash bcrypt; hash non restituito dall’API. Username/ID sono dati anche se non vengono chiesti nome, email o telefono. |
| Cookie di sessione, ID e dati della sessione | Firestore `sessions`, cookie `affitto_stanze.sid`; accesso | HttpOnly, SameSite=lax, secure in produzione; durata mobile di otto ore di inattività. Cleanup periodico. Nessun uso pubblicitario della sessione nel codice applicativo. |
| Stanza, utente, data, orari, durata, autore e nota amministrativa | Firestore `bookings`, `bookings_archive`; prenotazioni, report | Utente vede le proprie prenotazioni; note private e gestione utenti riservate agli amministratori. Dopo tre mesi si archivia, **non si cancella**. Non emerge un limite finale di conservazione per l’archivio. |
| IP e username per prevenzione accessi abusivi | SHA-256 nelle chiavi di `login_attempts`, contatori e scadenze Firestore | Finestre di 15 minuti; cleanup periodico. Un hash non rende automaticamente anonimo il dato. Ulteriori log IP possono esistere presso l’hosting. |
| Token APNs, ID casuale installazione, segreto/contatore installazione e collegamento account | Firestore `push_devices`, Apple APNs; notifiche opzionali | Segreto nel Portachiavi iOS e hash sul server. Token e associazione rimossi al logout con retry; dispositivi scadono dopo 90 giorni, eventi validi 24 ore e cleanup dopo sette giorni dalla scadenza. Notifiche generiche; identificativi evento/prenotazione e destinatario per recupero autenticato dei dettagli. |
| Dati annunci, interazioni, ID dispositivo, IP/posizione approssimativa e diagnostica | Google AdMob/UMP; pubblicità, misurazione, sicurezza e finalità dichiarate dai fornitori | Manifest e documentazione Google descrivono raccolte diverse per tipo. Il codice non passa username, password, prenotazioni o note al servizio pubblicitario. Il valore npa=1 non equivale a “non raccolgo dati”. |
| Report PDF | File temporaneo iOS, pannello condivisione scelto dall’amministratore | Le copie esportate dipendono dalle destinazioni scelte. Non vengono caricate dal codice su un servizio aggiuntivo. |

Firebase Admin è una dipendenza **del server**, non un SDK Firebase Analytics integrato nell’app iOS. Nelle dipendenze iOS esaminate sono presenti Google Mobile Ads e UMP; nessun adapter di mediazione aggiuntivo risulta dichiarato nel progetto. Le configurazioni del pannello AdMob e le condizioni effettive dei fornitori non sono interamente verificabili dal repository.

## Correzione implementata nella build 8

1. Descrizione ATT nell’Info.plist e richiesta nativa a stato app attivo. Il codice aspetta il risultato prima di contattare UMP, inizializzare Mobile Ads o creare banner.
2. ATT denied/restricted/notDetermined: niente inizializzazione Mobile Ads né banner. Il codice delle prenotazioni resta indipendente dai consensi.
3. ATT authorized: aggiornamento UMP, eventuale modulo, poi controllo canRequestAds. Errori dell’aggiornamento o del modulo impediscono avvio pubblicitario anche se esiste consenso precedente memorizzato.
4. Controllo ripetuto dopo le sospensioni asincrone e prima del caricamento effettivo del banner. Rimozione banner quando l’app diventa inattiva; ricontrollo al ritorno. Inizializzazione SDK una sola volta per processo.
5. Opzioni UMP riapribili dove richiesto; banner rimosso prima di cambiare scelte. Richiesta notifiche separata da ATT/UMP. La rimozione del banner interrompe il suo refresh; non è un’API per cancellare i dati già ricevuti da Google o per disinizializzare globalmente l’SDK.
6. Conservate richieste non personalizzate, blocco publisher first-party ID e raccolta da permessi di posizione disabilitata; test ads in Debug/simulatore/TestFlight. Nessun IDFA letto direttamente dal nostro codice.
7. Aggiunto manifest privacy dell’app con uso UserDefaults CA92.1 (preferenze notifiche), dati operativi e tracking pubblicitario tramite SDK. Domini AdMob principali `googleads.g.doubleclick.net` e `pubads.g.doubleclick.net`, documentati da Google. I manifest originali degli SDK restano inclusi; non sono stati alterati per nascondere raccolte.
8. Privacy pubblica e README aggiornati **localmente**. Versione commerciale 1.0.0 invariata, numero build 8.

## Esito delle verifiche locali

Build Debug, archivio Release ed esportazione App Store riusciti. Superati 10 test backend, controlli Swift di sessione/date e consensi, e tre test UI sul simulatore iPhone 17 Pro Max, inclusa la prenotazione dopo rifiuto ATT reale. Ripetuti i test UI anche con il manifest finale. Nell’IPA verificati firma, versione 1.0.0 (8), manifest, APNs production e get-task-allow false. Dettagli e limiti in `ESITO-TEST-2026-11-07.md`.

## App Privacy da aggiornare prima dell’invio

Non scegliere “Dati non raccolti”. Le informazioni devono includere anche i fornitori e i percorsi opzionali. La sola presenza del prompt ATT non aggiorna le etichette di App Store Connect e il manifest non le sostituisce.

| Tipo App Store | Finalità da dichiarare sulla base del codice/SDK | Collegamento e tracking |
| --- | --- | --- |
| Identificativi → ID utente | Funzionalità app: account e prenotazioni | Collegato all’account; non passato agli annunci dal codice. |
| Contenuti utente → Altri contenuti dell’utente | Funzionalità app: prenotazioni e note amministrative | Collegato all’account; non passato agli annunci dal codice. |
| Identificativi → ID dispositivo | Funzionalità app per APNs/installazione; pubblicità di terze parti e analisi per SDK Google | APNs collegato all’account, senza tracking; identificativi pubblicitari collegati al dispositivo, tracking previsto dal manifest SDK quando autorizzato. La categoria combinata deve riflettere entrambi gli usi. |
| Posizione approssimativa | UMP funzionalità app; Google pubblicità/analisi secondo manifest | Il blocco del permesso posizione non elimina la geolocalizzazione da IP. Manifest UMP: non collegata; Mobile Ads: collegata, tracking false per questa categoria nel manifest esaminato. |
| Dati di utilizzo → Dati pubblicitari e interazioni con il prodotto | Pubblicità di terze parti e analisi dichiarate da Google | Mobile Ads li dichiara collegati, tracking false per queste categorie nel manifest esaminato. Non estendere automaticamente a ogni dato il flag tracking degli identificativi. |
| Diagnostica → Crash, prestazioni, altri dati diagnostici | Analisi e ulteriori finalità dichiarate da Google | Consultare il report aggregato Xcode: i tre tipi hanno finalità diverse nel manifest, prevalentemente non collegati. |
| Altri dati | Funzionalità app/sicurezza: credenziali protette, sessioni, contatori tecnici | Dati operativi collegabili a utenti o dispositivi. Specificare secondo i dettagli del trattamento effettivo. |

Verificare nel riepilogo Xcode le finalità esatte: Google include anche Developer Advertising in più voci. Non dedurre né togliere finalità dal solo nome del banner. Il titolare deve confermare quali finalità opzionali Google siano attive, e completare le etichette includendo i percorsi realmente consentiti. Stato corrente delle etichette in App Store Connect **non letto né modificato** in questa sessione.

## Controlli ancora esterni al repository

- La verifica HTTP del 7 novembre ha restituito 200 per `/health`, `/privacy.html`, `/support.html` e `/app-ads.txt`. Health indica release `2026-11-04-push-1`, notifiche attive. La privacy online contiene ancora la descrizione senza ATT. La versione locale va pubblicata prima della nuova revisione; non è stato eseguito un deploy.
- Nel pannello **AdMob → Privacy e messaggi**, controllare il messaggio europeo pubblicato per l’App ID incluso nel bundle, fornitori/finalità e opzioni di rifiuto/revoca. Il testo remoto non è incluso nei sorgenti. L’eventuale spiegazione IDFA UMP non deve contraddire o duplicare in modo fuorviante il nuovo flusso. Non inserire modalità geografiche di debug nella Release.
- Provare su iPhone/TestFlight l’accettazione ATT, i moduli UMP reali UE e fuori UE, la revoca da Impostazioni e il ritorno nell’app. Confrontare il traffico pubblicitario con i domini dichiarati, soprattutto se si attivano nuovi partner; non si è effettuata un’intercettazione completa del traffico Google o un audit dei server del fornitore.
- Definire/verificare con i fornitori le basi giuridiche, regioni Firestore/Render, trasferimenti, accordi di trattamento, tempi finali di conservazione e procedura di cancellazione effettiva degli account e archivi. Il codice e una pagina privacy da soli non certificano conformità GDPR completa. Non cambiare questi dettagli con valori inventati.
- Fornire ad Apple accesso dimostrativo attivo per utente e amministratore nei campi riservati di Review; le credenziali non sono salvate in questo documento e non sono state testate sul servizio reale.

## Fonti ufficiali consultate

- [Apple: user privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/) — ATT riguarda anche SDK terzi che combinano dati per misurazione pubblicitaria; il consenso GDPR non sostituisce la richiesta di sistema.
- [Google: privacy strategies](https://developers.google.com/admob/ios/privacy/strategies) — integrazione ATT e attesa del risultato prima degli annunci.
- [Google: UMP setup](https://developers.google.com/admob/ios/privacy) — aggiornamento a ogni avvio, moduli e canRequestAds, opzioni privacy.
- [Google: data disclosure, versione 13.12.0](https://developers.google.com/admob/ios/privacy/data-disclosure) — categorie di dati raccolti da confrontare con i manifest effettivamente inclusi.
- [Apple: privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [TN3182](https://developer.apple.com/documentation/technotes/tn3182-adding-privacy-tracking-keys-to-your-privacy-manifest) — dichiarazioni di API, raccolta e domini di tracking.
- [Google: domini per ispezione annunci AdMob](https://support.google.com/admob/answer/7671795?hl=en) — host principali documentati per il traffico degli annunci.
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — quadro generale. Per i quesiti concreti è stato usato il messaggio Apple negli allegati, non una ricostruzione generica della linea guida.
