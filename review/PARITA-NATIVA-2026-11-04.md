# Aggiornamento interfaccia nativa e parità funzionale

Schermate compatte senza ScrollView, Form o List; elenchi a pagine, selezione degli orari a griglia paginata e prenotazione guidata. Il calendario, la tastiera e la condivisione sono controlli di sistema iOS.

Aggiunte gestione utenti (creazione, ruolo, stato, reset password), gestione stanze (creazione, descrizione, stato, eliminazione protetta), note private e autore delle prenotazioni, dashboard amministratore e utente, report mensili/settimanali con filtro per utente ed esportazione PDF autenticata. I campi amministrativi delle prenotazioni sono esclusi dalle risposte agli utenti normali. Il generatore PDF è condiviso con il sito.

Verifiche: test HTTP su database in memoria per le nuove operazioni e relativi divieti; compilazione iOS; controlli Swift sulle sessioni; test UI con rete simulata su iPhone SE 3 e iPhone 17 Pro Max. Durante il controllo visivo è stata corretta l’assenza della configurazione di avvio moderno, che faceva usare dimensioni di compatibilità errate. Il login e i moduli sono verificati anche con tastiera aperta.

Nessuna prenotazione reale viene usata per i test automatici. Non sono disponibili credenziali di un account di prova per una verifica autenticata completa contro Firebase di produzione; dopo il deploy si controllano pubblicamente versione, pagina di accesso e protezioni delle nuove API.

Esito finale: 5 test UI superati su iPhone SE 3, 4 su iPhone 17 Pro Max, nessun errore o avviso runtime riportato dai risultati. Compilazione Debug per simulatore e Release per iPhone superate. Tre test HTTP di integrazione superati; controlli Swift di sessione/data superati; audit dipendenze a zero segnalazioni.
