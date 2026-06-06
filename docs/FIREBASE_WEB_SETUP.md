# Connect the website to your existing Firebase app

The website uses the **same Firebase project** as the Oplix iOS app:

| | Value |
|---|--------|
| Project | `oplix-3183d` |
| iOS config | `Oplix/GoogleService-Info.plist` |
| Web config | `docs/js/firebase-config.js` (auto-synced from plist) |
| Auth users | Same Email/Password accounts |
| User profiles | Firestore `users/{uid}` (same as app) |

## One-time: add a Web app in Firebase

The iOS app and website share one Firebase **project**, but Firebase still needs a **Web** app registered for the browser SDK.

1. Open [Firebase Console → oplix-3183d](https://console.firebase.google.com/project/oplix-3183d/settings/general)
2. **Project settings** → **Your apps** → **Add app** → **Web** (`</>`)
3. App nickname: e.g. `Oplix Web`
4. Copy the **appId** (looks like `1:102947106270:web:…`)

Then either:

**Option A — text file (recommended)**

```bash
# Paste only the appId on one line:
echo "1:102947106270:web:YOUR_ID_HERE" > docs/firebase-web-app-id.txt
./scripts/sync-firebase-web-config.sh
```

**Option B — override file**

```bash
cp docs/js/firebase-config.override.js.example docs/js/firebase-config.override.js
# Edit appId inside firebase-config.override.js
```

## Authorized domains

**Authentication** → **Settings** → **Authorized domains** → add:

- `localhost`
- `hmharoon88.github.io` (GitHub Pages)
- Your Oplix custom domain when ready (not algls.com — that is a separate company site)

## Sync config after plist changes

If you replace `GoogleService-Info.plist` from Firebase:

```bash
./scripts/sync-firebase-web-config.sh
```

## Test locally

```bash
cd docs && python3 -m http.server 8080
```

1. http://localhost:8080/login.html  
2. Sign in with a **manager** account (verified email)  
3. http://localhost:8080/app/index.html — your facilities from Firestore  

## What matches the iOS app

- Same `oplix-3183d` project and API key  
- Same Auth email/password  
- Email must be verified (managers)  
- Firestore `users` doc must have `role: "manager"`  
- Data path: `users/{yourUid}/locations/…`

Supervisor and employee accounts are rejected on the web (manager-only for now).
