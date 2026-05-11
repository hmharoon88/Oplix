# Deploy Cloud Functions to Delete Firebase Auth Accounts

This guide will help you deploy Cloud Functions that automatically delete Firebase Auth accounts when employees, supervisors, or locations are deleted.

## Prerequisites

1. **Firebase CLI installed**: If not installed, run:
   ```bash
   npm install -g firebase-tools
   ```

2. **Logged into Firebase**: 
   ```bash
   firebase login
   ```

3. **Node.js 18+ installed**: Check with `node --version`

## Step 1: Install Dependencies

Navigate to the functions directory and install dependencies:

```bash
cd functions
npm install
cd ..
```

## Step 2: Deploy Functions

Deploy the Cloud Functions to Firebase:

```bash
firebase deploy --only functions
```

This will deploy:
- `deleteUserOnUserDocumentDelete` - Deletes Auth account when User document is deleted
- `deleteEmployeesOnLocationDelete` - Logs location deletion (Auth deletion handled by first function)

## Step 3: Verify Deployment

After deployment, you can check the functions in:
- Firebase Console → Functions
- Or run: `firebase functions:list`

## How It Works

1. **When an employee/supervisor is deleted:**
   - The app deletes the User document from Firestore (`users/{employeeId}`)
   - The Cloud Function `deleteUserOnUserDocumentDelete` is triggered
   - The function deletes the corresponding Firebase Auth account

2. **When a location is deleted:**
   - The app deletes all employee User documents
   - The Cloud Function is triggered for each deleted User document
   - All corresponding Auth accounts are deleted

## Testing

To test locally (optional):

```bash
cd functions
npm run serve
```

Then use the Firebase Emulator Suite to test the functions.

## Important Notes

- **First-time deployment may take 5-10 minutes**
- **Functions are billed based on usage** (Firebase free tier includes generous limits)
- **Functions run automatically** - no code changes needed in your app
- **Auth accounts are deleted within seconds** of User document deletion

## Troubleshooting

If deployment fails:
1. Check you're logged in: `firebase login`
2. Check you're in the correct project: `firebase projects:list`
3. Set the project: `firebase use <project-id>`
4. Check Node.js version: `node --version` (should be 18+)

## View Logs

To view function logs:
```bash
firebase functions:log
```

Or in Firebase Console → Functions → Logs

