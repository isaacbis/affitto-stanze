# Revisione del 4 novembre 2026

Ambito: server.js, dipendenze npm, app SwiftUI del repository e confronto con il progetto aperto sul Desktop. Il codice Swift delle due copie coincide. Revisione senza modificare il funzionamento o pubblicare aggiornamenti.

## Problemi da correggere

1. **P1 — Dati del precedente account conservati dopo la scadenza della sessione.** In AffittoStanzeApp.swift:36 viene azzerato solo `user`, mentre prenotazioni e utenti restano in memoria. Un nuovo login rende visibile MainView prima del completamento di refresh. Se refresh fallisce, rimangono i dati del precedente accesso. Riprodotto in un harness macOS eseguendo il codice Store originale con URLProtocol e risposte HTTP simulate: account admin -> 401 -> nuovo login utente -> errore caricamento stanze -> prenotazione admin ancora presente. Azzerare tutti i dati al termine della sessione e prima del cambio account; rifiutare risposte appartenenti a una sessione precedente.

2. **P1 — Dipendenze con vulnerabilità note.** `npm audit --omit=dev` sul lockfile restituisce 30 pacchetti segnalati: 3 critical, 9 high, 17 moderate e 1 low. Rapporto completo in npm-audit-2026-11-04.json. Le tre voci critical sono protobufjs, proxy-addr e websocket-driver. Il conteggio non dimostra che tutte le vulnerabilità siano sfruttabili tramite il gestionale. Aggiornare le dipendenze in una copia di lavoro e verificare autenticazione, Firestore e PDF prima della distribuzione.

3. **P1 — Password iniziale scritta nei log.** server.js:517 registra in chiaro la password dell'admin durante la creazione iniziale, anche in produzione. Rimuovere la password dal log; se quella fase è già avvenuta, cambiare la relativa password. La revisione non ha letto i log storici e non conferma un'esposizione avvenuta.

4. **P2 — Data visualizzata e data inviata possono differire fuori dal fuso italiano.** DatePicker usa il fuso del dispositivo (Swift:170), mentre dateString usa Europe/Rome (164). Riprodotto con Foundation: 5 novembre 2026 alle 01:00 in Asia/Tokyo viene formattato come 2026-11-04 per l'API. Impostare esplicitamente Europe/Rome e calendario gregoriano nel selettore e nel calcolo del limite minimo, indicando il fuso agli utenti.

5. **P2 — Disponibilità obsoleta o apparentemente vuota durante caricamento/errore.** Swift:180-182 non azzera slots al cambio selezione, non distingue caricamento da nessuna prenotazione e conserva il risultato precedente se la rete fallisce. La cancellazione del task è trattata come errore da mostrare. Usare stato di caricamento/errore esplicito e applicare solo la risposta corrispondente a stanza e data ancora selezionate. Il server continua a controllare le sovrapposizioni all'inserimento, quindi il problema qui è l'informazione mostrata nell'app.

6. **P2 — Accessi senza limitazione dei tentativi.** Le rotte POST /login (server:737) e POST /api/v1/login (644) non hanno middleware di throttling. L'header X-Affitto-Client è riproducibile e non sostituisce la protezione dei tentativi. Aggiungere una limitazione condivisa per IP e account, senza blocchi permanenti, verificando la configurazione del proxy. Nessuna prova di forza bruta è stata eseguita sul servizio pubblico.

## Miglioramenti utili

- Paginazione e query per utente/data: /api/v1/bookings legge prima tutte le prenotazioni, quindi filtra in memoria; questo aumenta letture e latenza con la crescita dei dati.
- Gestione utenti, stanze, report e note amministrative: non ancora disponibili nell'interfaccia nativa con la stessa copertura del sito.
- Prenotazione: selezionare solo fasce libere e future, distinguere elenco prossimo/storico, aggiornare al ritorno dell'app in primo piano.
- Rete: mostrare errori e tentativo di riprova anche durante il ripristino sessione; `try?` in restore attualmente nasconde tutti i problemi come se non ci fosse una sessione.
- Accessibilità: colori della schermata login adattati alla modalità scura e dimensioni del testo dinamiche, con prove visive su schermi piccoli.
- Manutenzione: separare modelli, client API e schermate Swift; estrarre le rotte API dal server monolitico; versionare iOS, attualmente non tracciata da Git.
- Distribuzione: bundle ID ancora com.example.affittostanze, firma/team da configurare, icona e versioni app da completare. Informativa privacy e riferimenti di assistenza devono essere definiti e aggiunti.

## Verifiche effettuate e limiti

- node --check server.js: superato.
- Compilazione iOS per dispositivo generico, firma disabilitata: superata. Rimane avviso di configurazione ALWAYS_SEARCH_USER_PATHS.
- Harness Swift locale con URLProtocol: riprodotta conservazione dei dati dopo 401 e successivo cambio account con errore di refresh.
- Foundation: riprodotta differenza di giorno tra dispositivo in Asia/Tokyo e serializzazione Europe/Rome.
- npm audit --omit=dev: eseguito, rapporto allegato.
- Non sono state create, cancellate o modificate prenotazioni reali. Mancano prove end-to-end con account di test e verifiche di concorrenza contro un ambiente Firebase di test; la compilazione non copre questi casi.


## Esito delle correzioni

Applicate le sei correzioni principali: isolamento delle sessioni, aggiornamento delle dipendenze con audit a zero segnalazioni, rimozione del log della password iniziale, calendario Europe/Rome, disponibilità esplicita e protetta dalle risposte obsolete, limitazione condivisa degli accessi tramite Firestore. Aggiunti test HTTP con database simulato e controllo Swift locale, selezione di fasce libere/future e filtro prossime/storico. Le password eventualmente presenti nei log storici non sono state modificate per evitare di bloccare gli account esistenti. Gestione amministrativa completa e preparazione finale App Store restano fuori da questo aggiornamento correttivo.
