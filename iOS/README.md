# Affitto stanze per iPhone

Aprire `AffittoStanze.xcodeproj` con Xcode. SwiftUI nativo, iOS 17 o successivo. Il progetto usa lo stesso server, le stesse sessioni e lo stesso database Firebase del sito `https://affitto-stanze.onrender.com`.

## Schermate senza scorrimento verticale

Le schermate principali usano contenuti compatti e pulsanti Precedente/Successiva. Gli elenchi mostrano un numero di righe calcolato in base allo spazio disponibile. La prenotazione è divisa in passaggi: stanza/data, inizio, fine, nota privata per gli amministratori e riepilogo. Il login si compatta quando compare la tastiera; sui display più piccoli può passare alla password in un secondo passaggio.

Anche descrizioni e note lunghe si leggono su pagine. Selettore data, tastiera e pannello di condivisione PDF sono controlli standard di iOS e mantengono il proprio comportamento di sistema.

## Corrispondenza con il sito

| Funzione del sito | App nativa |
| --- | --- |
| Login, sessione, logout | Login e Profilo |
| Dashboard utente e ultime prenotazioni | Home |
| Dashboard amministratore, utenti/stanze attive e prenotazioni di oggi | Home amministratore |
| Cambio della propria password | Profilo → Cambia password |
| Prenotazione a intervalli di 30 minuti, 08:00–20:30 | Prenota, orari liberi/futuri e controllo conflitti lato server |
| Elenco prenotazioni personali o amministrative | Prenotazioni, ricerca e pagine |
| Cancellazione utente oltre un’ora prima; cancellazione amministratore | Dettaglio prenotazione, stesse regole lato server |
| Prenotazioni per altri utenti, nota privata e autore amministrativo | Prenota amministratore e Dettaglio |
| Lista utenti, creazione con ruolo, attivazione/disattivazione | Gestione → Utenti |
| Reimpostazione password di un utente | Dettaglio utente → Reimposta password |
| Protezione contro disattivazione propria e dell’ultimo amministratore | Controllo lato server |
| Lista stanze, creazione e descrizione | Gestione → Stanze |
| Attivazione/disattivazione ed eliminazione senza prenotazioni collegate | Dettaglio stanza |
| Report mensile/settimanale e filtro utente, compresi gli utenti disattivati | Gestione → Report |
| Totale ore, conteggio prenotazioni ed esportazione PDF | Report → Esporta e condividi PDF |

Non sono aggiunte operazioni che il sito non offre, come modifica di prenotazioni o eliminazione di utenti. Le note private non vengono restituite dall’API agli utenti normali.

## Server e test

Node.js 22 o superiore. Le nuove rotte amministrative in `lib/mobile-admin.js` usano gli stessi helper del sito e lo stesso generatore PDF. La limitazione degli accessi condivisa in Firestore rimane attiva. Nessuna password è scritta nei nuovi log.

- `npm test`: test HTTP con database simulato per ruoli, prenotazioni, conflitti, cancellazioni, password, gestione utenti/stanze, riservatezza delle note e report/PDF.
- `python3 test/check-ios.py`: controlli isolati Swift su sessioni e date, senza rete reale.
- Xcode → Product → Test: test interfaccia su dati isolati, senza contattare Firebase o modificare prenotazioni reali.

I dati per i test visivi sono compilati solo in Debug e attivati solo passando esplicitamente `--ui-preview`; i normali avvii dell’app si collegano al gestionale. Il codice di prova non è presente nella configurazione Release.

## Distribuzione

Prima di App Store occorrono identificativo definitivo (attualmente `com.example.affittostanze`), firma Apple, icona, informazioni privacy e assistenza e configurazione App Store Connect. Il progetto contiene ora le schermate e le operazioni presenti nel sito; la parità funzionale non sostituisce le verifiche con account di prova sull’ambiente di destinazione.


## Versione 1.0.0 e distribuzione

Bundle ID definitivo `com.isaacmorganti.affittostanze`, team Apple configurato, icona opaca 1024×1024 e versione/build esplicite. Le pagine pubbliche privacy e assistenza sono in public/privacy.html e public/support.html. Contatto pubblico confermato dal titolare. Le credenziali e il telefono per App Review non sono salvati nel repository. Metadati italiani in iOS/AppStore/it-IT.
