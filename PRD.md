PRD: দেনা পাওনা (Flutter App)
1. 📌 Product Overview

App Name: দেনা পাওনা
Platform: Flutter (Android-first, Offline-first)
Purpose:
ব্যক্তিগত লেনদেন (দেনা, পাওনা, দোকান হিসাব, আমানত) সহজভাবে ট্র্যাক ও ম্যানেজ করা।

Core Goal:
✔ Offline-first financial tracking
✔ Simple UI (Bangla-based)
✔ Firebase sync + local storage

2. 🎯 Target Users
দোকানদার
ব্যক্তিগত হিসাব রাখেন এমন মানুষ
ছোট ব্যবসায়ী
গ্রাম/মফস্বল ব্যবহারকারী (Low internet users)
3. ⚙️ Core Features (From HTML App)
🔐 3.1 Authentication
Email + Password Login/Signup
Firebase Auth
Local persistence (auto login)
🏠 3.2 Dashboard

Shows:

মোট দোকানের দেনা
মোট সাধারণ দেনা
সর্বমোট দেনা
মোট পাওনা
মোট আমানত

👉 Real-time auto update (Firestore listener)

📂 3.3 Modules (Main Sections)
1. Shops (দোকান)
দোকান add/edit/delete
দোকানের দেনা ট্র্যাক
2. General Debt (সাধারণ দেনা)
ব্যক্তিগত দেনা
3. Receivables (পাওনা)
কে তোমাকে টাকা দিবে
4. Amanot (আমানত)
জমা/ডিপোজিট হিসাব
🧾 3.4 Transaction Management

Each entity supports:

➤ Add Debt/Item
Description
Amount
Date
➤ Add Payment
Payment method
Amount
Date
➤ Detailed Entry (Advanced Feature)
Multiple items inside one transaction
Auto total calculation
📊 3.5 Details Screen
Item list (দেনা/পাওনা)
Payment list
Total due auto calculate
Edit/Delete supported
🔍 3.6 Search System
Real-time search filter
🔄 3.7 Pull to Refresh
Manual refresh gesture
📤 3.8 Data Management
Export JSON
Import JSON
🔙 3.9 Back Button Handling
Modal close priority
Dashboard → Exit confirmation
🔔 3.10 Toast & Alert System
Success/Error message
Custom confirm modal
4. 🧠 Technical Architecture (Flutter)
🏗️ Architecture Pattern
Clean Architecture + MVVM (Recommended)
Provider / Riverpod
📦 Core Packages
firebase_core
firebase_auth
cloud_firestore
hive / sembast (offline DB)
provider / riverpod
intl
💾 Offline Strategy (IMPORTANT)

From HTML:

Firestore Offline Enabled

Flutter Implementation:

✔ Local DB (Hive)
✔ First load → Firebase sync
✔ Offline mode → full functionality
✔ Online → auto sync

5. 🗂️ Data Model
Entity (Shop/User)
{
  id,
  name,
  phone,
  totalDue,
  createdAt,
  updatedAt
}
Transaction Item
{
  id,
  description,
  amount,
  date,
  type: "debt" | "payment"
}
Detailed Item
{
  mainDescription,
  subItems: [
    { name, amount }
  ],
  total
}
6. 🎨 UI/UX Requirements
Theme:
Primary: Deep Purple (#4A4063)
Accent: Golden (#FFCA28)
Background: Light Mint (#E0F2F1)
Font:
Tiro Bangla
Design Style:
Minimal
Card-based
Touch-friendly
7. 📱 Navigation (Flutter)

Bottom Navigation OR TabBar:

Dashboard
Shops
General Debt
Receivables
Amanot
Data
8. 🔄 State Management Flow
UI → Provider → Service → Firebase/Hive
9. 🔐 Security
Firebase Auth required
User-based data isolation:
users/{userId}/collection
10. 🚀 Future Enhancements (Recommended)

🔥 (তোমার app upgrade করার জন্য এগুলো খুব গুরুত্বপূর্ণ)

📊 Graph / রিপোর্ট
📅 Reminder system (due date alert)
📲 SMS reminder
🧮 Auto calculator (তুমি আগে যে medicine calculator চেয়েছিলে)
☁️ Google Drive backup
🌙 Dark mode
11. 📌 Special Notes (Very Important)

এই HTML app-এর বিশেষ বৈশিষ্ট্য:

✔ Offline-first design
✔ Modal-heavy UI
✔ Dynamic page rendering
✔ Firebase realtime listener
✔ Cordova back button handling

👉 Flutter version এ এগুলো clean ভাবে implement করতে হবে

12. 🧾 Developer Instruction Summary

👉 Developer / AI Agent কে বলবে:

Existing HTML app logic preserve করতে হবে
UI redesign Flutter style but same structure
Offline-first system must work 100%
Firebase + Local DB sync
All CRUD features identical রাখতে হবে
Bangla UI ঠিক রাখতে হবে
✅ Final Summary

এই PRD অনুযায়ী Flutter app করলে তুমি পাবে:

✔ Professional level app
✔ Offline + Online hybrid system
✔ Real business use
✔ Scalable architecture