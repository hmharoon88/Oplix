/* global firebase, OPLIX_FIREBASE_CONFIG, OPLIX_FIREBASE_CONFIG_OVERRIDE */
(function () {
    if (typeof firebase === "undefined") {
        console.error("Firebase SDK not loaded");
        return;
    }

    const config = Object.assign(
        {},
        OPLIX_FIREBASE_CONFIG,
        typeof OPLIX_FIREBASE_CONFIG_OVERRIDE !== "undefined"
            ? OPLIX_FIREBASE_CONFIG_OVERRIDE
            : {}
    );

    if (!config.appId || config.appId === "REPLACE_WITH_WEB_APP_ID") {
        console.warn(
            "Oplix web: add a Firebase Web app in Console (project oplix-3183d) and set docs/firebase-web-app-id.txt, then run scripts/sync-firebase-web-config.sh"
        );
    }

    if (!firebase.apps.length) {
        window.oplixApp = firebase.initializeApp(config);
    } else {
        window.oplixApp = firebase.app();
    }

    window.oplixAuth = firebase.auth();
    window.oplixDb = firebase.firestore();
    if (typeof firebase.storage === "function") {
        window.oplixStorage = firebase.storage();
    }

    window.oplixAuth.setPersistence(firebase.auth.Auth.Persistence.LOCAL).catch(function (err) {
        console.warn("Auth persistence:", err);
    });
})();
