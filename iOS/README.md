# Affitto stanze per iPhone

Aprire `AffittoStanze.xcodeproj` con Xcode. Il progetto richiede iOS 17 o successivo. Per installarlo su un iPhone selezionare il proprio team Apple in Signing & Capabilities e sostituire il bundle identifier provvisorio `com.example.affittostanze` con uno univoco.

L'app usa `https://affitto-stanze.onrender.com/api/v1/`. Le rotte sono state aggiunte a `../server.js` e usano la stessa sessione, Firebase e transazione del sito. L’API è stata pubblicata su Render il 4 novembre 2026 (commit 3301910); verificati risposta login e blocco delle richieste non autenticate. Prima del rilascio è necessario verificare login, sessione, disponibilità, conflitti e cancellazione con utenti di test e dati di prova, e verificare la configurazione Firebase e di sessione nell'ambiente di destinazione.

Questa prima versione copre accesso, elenco, inserimento e cancellazione prenotazioni; l'amministratore può prenotare per un utente attivo. Include anche il cambio della propria password. Non include ancora gestione utenti e stanze, report o tutte le schermate del gestionale. Il progetto non è pronto per App Store: occorrono funzionalità mancanti, icona, identificativo definitivo, firma, test su dispositivo e simulatori, informazioni privacy e configurazione App Store Connect.


## Correzioni del 4 novembre 2026

Sessioni isolate per account, rifiuto delle risposte di rete di sessioni precedenti, cancellazione dei dati alla scadenza e al logout. Disponibilità con caricamento ed errore espliciti, selezione di fasce libere e future, date e orari sempre nel fuso Europe/Rome. Elenco diviso in prossime prenotazioni e storico. Aggiornamento al ritorno in primo piano.

Il server usa Node.js 22 o superiore e le API modulari di Firebase Admin. I tentativi di accesso sono limitati in modo condiviso fra sito e app tramite Firestore (15 tentativi per account e 60 per IP ogni 15 minuti). Non vengono più scritte password nei log. Le password eventualmente registrate in passato richiedono un cambio manuale tramite l’account amministrativo.

Verifiche server: `npm test`; dipendenze: `npm audit --omit=dev`. I test usano dati in memoria e non contattano il database di produzione. Per il controllo Swift locale, il runner `test/check-ios.py` estrae dal sorgente i modelli/client e compila il test con Swift sul Mac.
