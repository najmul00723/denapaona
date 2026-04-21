# দেনা পাওনা

Flutter Android-first offline ledger app for personal debt, receivable, shop
dues, and amanot tracking.

## Firebase Security

Firestore data is stored under authenticated user paths:

```text
users/{uid}/entities/{entityId}
users/{uid}/transactions/{transactionId}
users/{uid}/snapshots/latest
```

Production rules live in `firestore.rules` and enforce:

- Firebase Auth is required for every cloud read/write.
- A user can access only `users/{request.auth.uid}`.
- Unknown top-level paths and unknown subcollections are denied.
- Entity, transaction, and snapshot writes must match the app schema.
- Snapshot writes are limited to `snapshots/latest`.

Deploy rules after selecting the Firebase project:

```powershell
firebase use <project-id>
firebase deploy --only firestore:rules
```

## Development

```powershell
flutter pub get
flutter analyze
flutter test
```
