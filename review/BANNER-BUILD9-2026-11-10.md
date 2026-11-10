# Affitto Stanze 1.0.1 (9) — banner dopo rifiuto ATT

## Modifica
Il coordinatore attende ATT se non determinato. Gli stati denied e restricted non bloccano più da soli UMP e banner; resta obbligatorio un aggiornamento UMP/modulo riuscito e canRequestAds=true. Nessuna stringa TCF o scelta utente viene forzata. Il Google SDK omette IDFA senza autorizzazione ATT secondo la documentazione ufficiale. Invariati npa=1, personalizzazione disabilitata, publisher first-party ID disabilitato e posizione da permessi disabilitata. I manifest privacy app e SDK sono conservati. Log banner limitati a dominio/codice errore.

## Verifiche completate il 10 novembre 2026
- Coordinatore Swift: rifiuto e restrizione ATT, attesa stato irrisolto, ordine ATT/UMP/SDK, errori UMP con consenso memorizzato, retry, revoca UMP, background, avvio unico e configurazione disabilitata: superati.
- Sessioni/date Swift: superati.
- Test UI su simulatore Affitto Stanze Large QA iOS 26.5: rifiutata la finestra ATT reale; UMP SDK reale con geografia non SEE solo Debug; ricevuto callback del banner ufficiale Google di prova; screenshot verificato; prenotazione su API simulate completata. Un test, zero errori.
- Archivio Release: compilato e firma verificata, bundle/versione 1.0.1 (9), App ID AdMob corretto, manifest app e due SDK inclusi. Assenti nel binario Release geografia Debug e identificatore test di caricamento.

## Limiti
L’annuncio di prova non dimostra il riempimento commerciale. Non effettuato audit completo del traffico cifrato Google né verifica su dispositivo fisico di tutti i percorsi UMP regionali. Gli SDK continuano a trattare i dati dichiarati nei propri manifest; npa=1 non è prova di assenza di raccolta. La disponibilità degli annunci dipende dai consensi e da AdMob. Nessun dato di prenotazione reale è stato creato nei test.

## Fonti
- https://developers.google.com/admob/ios/privacy/idfa — richieste consentite dopo rifiuto ATT, senza IDFA.
- https://developers.google.com/admob/ios/privacy — aggiornamento, moduli e canRequestAds.
- https://support.google.com/admob/answer/10105530 — annunci limitati secondo scelte TCF e disponibilità.

Privacy pubblica aggiornata in commit remoto 9675a3ec3c300d7f570911749de7c4deb4a4eefc; lo stato deploy e invio Apple è registrato separatamente a conclusione.
