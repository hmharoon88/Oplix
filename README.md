# Oplix - Cloud-Based Management App

A complete SwiftUI iOS app for managing locations, employees, tasks, shifts, and lottery forms with Firebase backend.

## Features

- **Dual Role System**: Manager and Employee roles with different access levels
- **Firebase Integration**: Authentication and Firestore for cloud-based data storage
- **Real-time Updates**: Live syncing of tasks, shifts, and lottery forms
- **Modern UI**: Cloud-themed design with gradients and adaptive layouts
- **iPad Support**: Full iPad optimization with NavigationSplitView

## Setup Instructions

> **⚠️ IMPORTANT: If you see "No such module 'FirebaseAuth'" error, see [FIREBASE_SETUP.md](FIREBASE_SETUP.md) for step-by-step instructions to add Firebase to your Xcode project.**

### 1. Add Firebase SDK (Required First Step)

**You must add Firebase before building the project:**

1. Open `Oplix.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter: `https://github.com/firebase/firebase-ios-sdk`
4. Select products: **FirebaseAuth**, **FirebaseFirestore**, **FirebaseCore**
5. Add to target: **Oplix**

See [FIREBASE_SETUP.md](FIREBASE_SETUP.md) for detailed instructions.

### 2. Firebase Configuration

1. Create a new Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add an iOS app to your Firebase project
3. Download `GoogleService-Info.plist` and add it to your Xcode project
4. Enable Authentication:
   - Go to Authentication > Sign-in method
   - Enable Email/Password authentication
5. Create Firestore Database:
   - Go to Firestore Database
   - Create database in production mode
   - Copy the contents of `firestore.rules` to your Firestore Rules

### 2. Xcode Dependencies

Add the following Swift Package Manager dependencies:

1. Open your project in Xcode
2. Go to File > Add Package Dependencies
3. Add:
   - `https://github.com/firebase/firebase-ios-sdk`
   - Select these products:
     - FirebaseAuth
     - FirebaseFirestore
     - FirebaseCore

### 3. Project Structure

```
Oplix/
├── Models/
│   ├── User.swift
│   ├── Location.swift
│   ├── Employee.swift
│   ├── Task.swift
│   ├── Shift.swift
│   └── LotteryForm.swift
├── Services/
│   └── FirebaseService.swift
├── ViewModels/
│   ├── AuthViewModel.swift
│   ├── ManagerDashboardViewModel.swift
│   ├── LocationDetailViewModel.swift
│   └── EmployeeHomeViewModel.swift
├── Views/
│   ├── Theme.swift
│   ├── Auth/
│   │   ├── RoleSelectionView.swift
│   │   ├── ManagerLoginView.swift
│   │   └── EmployeeLoginView.swift
│   ├── Manager/
│   │   ├── ManagerDashboardView.swift
│   │   ├── AddLocationView.swift
│   │   ├── LocationDetailView.swift
│   │   ├── AddEmployeeView.swift
│   │   └── AddTaskView.swift
│   └── Employee/
│       ├── EmployeeHomeView.swift
│       └── LotteryFormView.swift
└── OplixApp.swift
```

### 4. Firestore Security Rules

Deploy the security rules from `firestore.rules` to your Firestore database:

1. Go to Firestore Database > Rules
2. Paste the contents of `firestore.rules`
3. Publish the rules

### 5. Create First Manager Account

Since managers need to be created manually, you can:

1. Use Firebase Console to create a user with email/password
2. Manually create a User document in Firestore:
   ```json
   {
     "id": "<firebase-auth-uid>",
     "username": "admin",
     "role": "manager",
     "locationId": null,
     "createdAt": "<timestamp>"
   }
   ```

## Usage

### Manager Flow

1. Select "Manager" on the role selection screen
2. Sign in with email and password
3. View all locations in the dashboard
4. Create new locations
5. For each location:
   - Add employees (auto-generates username/password)
   - Create and assign tasks
   - View employee shifts and hours
   - View lottery forms

### Employee Flow

1. Select "Employee" on the role selection screen
2. Sign in with username (format: `username@oplix.app`) and password
3. Clock in/out for shifts
4. View and complete assigned tasks
5. Submit lottery forms for active shifts

## Architecture

- **MVVM Pattern**: Separation of concerns with ViewModels
- **Swift Concurrency**: Async/await throughout
- **Firebase Services**: Centralized Firebase operations
- **Real-time Listeners**: Live updates for tasks, shifts, and forms

## Requirements

- iOS 16.0+
- Xcode 14.0+
- Swift 5.7+
- Firebase iOS SDK

## Color Theme

- **Cloud Blue**: Primary action color
- **Sunshine Yellow**: Secondary action color
- **Soft Gray**: Background accents
- **Cloud White**: Card backgrounds
- **Sky Blue**: Gradient accents

## Notes

- All employees are created with email format: `{username}@oplix.app`
- Managers can view and manage all locations remotely
- Real-time syncing ensures data consistency across devices
- Logout functionality returns users to the role selection screen

