# Risposta ad App Review — 7 novembre 2026

Submission ID: `968bcd0e-4af1-40da-a82c-60fdf4bd2839`.
Versione contestata: **1.0.0 (7)**, iPhone 17 Pro Max.

Il testo commerciale seguente è basato sui sorgenti Swift/Node, sui pacchetti inclusi nell’archivio 7 e sulla conferma del titolare del 7 novembre: nessun pagamento, account amministrativi gratuiti, monetizzazione solo tramite banner Google. Non afferma che l’app non raccolga dati.

## Testo utilizzabile subito per i sei quesiti 2.1(b)

Hello App Review Team,

Thank you for reviewing Affitto Stanze. Regarding submission 968bcd0e-4af1-40da-a82c-60fdf4bd2839 and Guideline 2.1(b), we would like to clarify the business model and account access in version 1.0.0.

Affitto Stanze is a reservation management application for physical rooms. Authorized users check availability, reserve time slots, view their own bookings and cancel them within the applicable booking rules. Administrators manage rooms, accounts and bookings and generate usage reports and PDF exports. The application displays a Google AdMob banner at the top of the screen. Banner advertising is its only monetization; users do not purchase access to the app’s functions or to room reservations.

1. **Who are the users that will use the paid content, subscriptions, features, and services in the app?**

   There are no paid digital content items, subscriptions, premium features or paid services. The users are people authorized by the room administrator to make reservations, and administrators responsible for managing those reservations. The difference between the user and administrator interfaces is based on account permissions, not a purchase or subscription tier. Neither group pays to use the application.

2. **Where can users purchase the content, subscriptions, features, and services that can be accessed in the app?**

   There is no purchase flow in the iOS app or its companion website, and no external purchase is required to use them. There are no checkout pages, payment links, activation purchases or paid plans. Room reservations are also free of charge. The advertising banner is supplied by Google AdMob; interacting with an advertisement is not required to access any application function.

3. **What specific types of previously purchased content, subscriptions, features, and services can a user access in the app?**

   None. The app does not restore purchases, check a paid subscription, validate a purchase receipt for feature access, or grant access to content purchased on another platform. Existing room bookings are reservation records, not purchased digital content.

4. **What paid content, subscriptions, or features are unlocked within the app that do not use In-App Purchase?**

   None. There are no paid unlocks, license codes or external payment entitlements. Booking functions are available to authorized user accounts; room management, account management and reports are available to authorized administrators. Administrator permissions are assigned by an administrator and are not sold. The application has no paid ad-removal option or rewarded-ad feature.

5. **Are the enterprise services in your app sold to single users, consumers, or for family use?**

   We do not sell an enterprise subscription or enterprise service through this application, nor do we sell individual, consumer or family plans outside it. This is an administrator-managed room reservation service. Access is granted to authorized users without a charge. We are not relying on the enterprise-services exception to unlock paid software functionality.

6. **How do users obtain an account? Do users have to pay a fee to create an account?**

   Accounts are created by an authorized administrator in the account management interface, using a username, an initial password and a role. The administrator provides the credentials directly to the user. The user signs in with those credentials and can change their password. There is no public self-registration, account creation fee, subscription requirement or payment to activate an account.

For completeness, the app’s backend uses Firebase Firestore to store account and room reservation records. The iOS app also supports optional Apple push notifications about bookings. Advertising and these operational data flows are separate: our application code does not pass usernames, passwords, booking details or administrators’ private notes to the advertising SDK.

We are also addressing the separate Guideline 5.1.2(i) issue in a new binary. The GDPR advertising choices do not replace Apple’s App Tracking Transparency authorization. We will provide the corrected build and its exact permission flow with the resubmission.

Best regards,
Affitto Stanze Development Team

## Paragrafo privacy da usare con la build 8

**Sostituire l’ultimo paragrafo sul lavoro in corso con questo solo dopo caricamento e selezione della build 8 e aggiornamento effettivo di App Privacy, pagina privacy e verifica del messaggio AdMob. L’IPA locale non è stata inviata ad Apple.**

Regarding Guideline 5.1.2(i), we identified that the previous iOS advertising integration displayed Google UMP consent choices without requesting Apple’s ATT authorization. We have corrected this in version 1.0.0, build 8.

On launch, while the application is active, the app requests tracking permission using Apple’s native App Tracking Transparency dialog if the permission has not previously been determined. This happens before our code requests UMP consent information, initializes Google Mobile Ads or loads any banner. The purpose text explains Google AdMob’s advertising measurement and possible use of the advertising identifier across other companies’ apps and websites. No custom prompt substitutes for the system dialog.

If ATT is denied, restricted or undetermined, the app does not initialize Google Mobile Ads or load advertising banners. Login, room availability, reservations, cancellation, administrator tools and reports remain available. We do not use a GDPR consent grant or a non-personalized ad request to override an ATT refusal.

After ATT authorization, the app separately updates UMP consent information and presents any required regional forms. Advertising starts only after this process succeeds and UMP permits advertising requests. If the consent update or form fails, the app continues without advertising. We continue to request non-personalized ads, disable publisher first-party ID and disable SDK collection through the device’s location permissions. These settings are additional restrictions and are not presented as proof that advertising involves no tracking.

When the application leaves the active state, the current banner is removed. ATT and advertising eligibility are checked again on return. Where UMP requires it, users can reopen “Scelte privacy pubblicitarie” using the hand icon next to the banner area. Booking notifications request their own system permission separately from the advertising consent flow.

The ATT gate applies in every region. UMP’s additional forms depend on the user’s region and the published AdMob privacy message. For review, on a device whose tracking permission for this app is not yet determined and where “Allow Apps to Request to Track” is enabled, launch the app to see the ATT dialog. Choose “Ask App Not to Track” / “Non tracciarmi” to verify that booking remains usable without banners. To inspect the regional advertising forms, authorize ATT on a suitable test device and review the applicable UMP form. If iOS already has a decision or restricts tracking requests, the system may not display another dialog; the app respects that status.

Our App Privacy disclosures and public privacy policy have been updated to reflect the application’s account/reservation data, optional notification identifiers and Google advertising SDK data, including the advertising identifiers used for tracking when authorized. We are not claiming “Data Not Collected.”
