# Security rules — what they do & how to publish

These rules are written so **normal app usage is not interrupted**, while blocking the main external attack paths.

## What is blocked

| Attacker | Before | After |
|----------|--------|-------|
| Not logged in | ❌ (was already blocked) | ❌ |
| Random sign-up, tries to read your data | ✅ could read everything | ❌ only sees their own empty `users/{uid}` tree |
| Employee login, tries another org's data | ✅ could read everything | ❌ only their manager's tree |
| Staff changing own role to `manager` | ✅ possible | ❌ role / managerUserId locked on self-update |

## What still works (unchanged for users)

- **Managers (web + iOS):** full access to `users/{yourUid}/…` — facilities, books, employees, payroll, etc.
- **Employees / supervisors (iOS):** access `users/{managerUserId}/…` using the `managerUserId` on their profile — shifts, tasks, lottery, register, etc.
- **Cloud Functions:** unchanged (Admin SDK bypasses rules).
- **Manager sign-up on web:** can still create `users/{uid}` with `role: manager`.
- **Creating staff:** manager can still create `users/{staffUid}` and all employee/location records.

## What we intentionally kept simple

- Staff can write anywhere under their manager's tree (same practical access as today, but **not** other managers' data).
- Manager-to-manager isolation is **not** the focus — each manager is scoped to their own `uid` path anyway.

## Publish to Firebase

```bash
# From project root, with Firebase CLI logged in:
firebase deploy --only firestore:rules,storage
```

Or manually:

1. [Firebase Console](https://console.firebase.google.com/project/oplix-3183d/firestore/rules) → Firestore → Rules → paste `firestore.rules` → **Publish**
2. Storage → Rules → paste `storage.rules` → **Publish**

Rules take effect immediately. No app update required.

## After publishing — quick smoke test

1. **Manager web** — log in, open Facilities, Daily books, Employees, add a payable.
2. **Manager iOS** — same account, confirm locations and tasks load.
3. **Employee iOS** — clock in, complete a task, submit lottery if applicable.
4. **New sign-up** — create a fresh manager account; confirm it sees **no** existing org data.

If anything permission-denied appears in normal flows, note the screen and we can adjust that path only.
