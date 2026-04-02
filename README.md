# esec_bus

A new Flutter project.

# 🚍 BusBuddy – ESEC Bus Tracking System

## 📌 Overview

BusBuddy is a real-time bus tracking application developed for Erode Sengunthar Engineering College (ESEC).
It enables students and staff to monitor live bus locations, view routes, and estimate arrival times using a mobile/web interface built with Flutter.

---

## 🎯 Problem Statement

Students often face uncertainty in bus timings, leading to:

* Long waiting times
* Missed buses
* Inefficient commute planning

BusBuddy addresses this by providing **real-time tracking and updates**.

---

## ⚙️ Features

* 📍 Live bus location tracking
* 🗺️ Route visualization
* ⏱️ Estimated arrival time (ETA)
* 🔐 User authentication (Student/Driver)
* 🔔 Notifications for bus updates (optional)
* 📱 Cross-platform support (Android / Web)

---

## 🛠️ Tech Stack

### Frontend

* Flutter (Dart)
* Google Maps / Map APIs

### Backend (Integrated)

* Node.js
* Firebase

---

## 📂 Project Structure

```
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
d-----         3/11/2026   9:57 AM                .dart_tool
d-----          2/3/2026   9:38 AM                .github
d-----          2/2/2026   3:21 PM                .idea
d-----          2/2/2026   8:40 PM                .vscode
d-----          2/3/2026   8:39 PM                android
d-----         2/15/2026  12:41 PM                assets
d-----          2/7/2026   2:02 PM                backend
d-----         3/16/2026  11:19 AM                build
d-----          2/5/2026   2:39 PM                functions
d-----          2/3/2026   8:39 PM                ios
d-----          2/5/2026   3:22 PM                lib
d-----          2/3/2026   8:39 PM                linux
d-----          2/3/2026   8:39 PM                macos
d-----          2/3/2026   8:39 PM                test
d-----          2/3/2026   8:39 PM                web
d-----          2/3/2026   8:39 PM                windows
-a----          2/5/2026   2:39 PM             53 .firebaserc
-a----          3/9/2026  11:24 PM           9534 .flutter-plugins-dependencies
-a----          2/7/2026   2:03 PM            780 .gitignore
-a----         3/11/2026   9:55 AM            968 .metadata
-a----          3/6/2026  11:45 AM           1448 analysis_options.yaml
-a----          2/3/2026   8:38 PM            859 esec_bus.iml
-a----          2/5/2026   2:39 PM           1076 firebase.json
-a----         2/15/2026  12:40 PM          43320 logo.jpeg
-a----         2/15/2026  12:49 PM          19434 pubspec.lock
-a----         2/15/2026  12:49 PM            613 pubspec.yaml
-a----          2/3/2026   8:38 PM            567 README.md

```

---

## 🚀 Getting Started

### Prerequisites

* Flutter SDK installed
* Android Studio / VS Code
* Connected device or emulator

### Installation

```bash
git clone https://github.com/rathishr-06/esec_bus_01.git
cd esec_bus
flutter pub get
```

### Run the App

```bash
flutter run
```

---

## 🔗 Backend Integration

Ensure backend server is running:

```
http://<your-ip>:5000/api/
```

Update API base URL in Flutter:

```dart
const baseUrl = "http://<your-ip>:5000/api/";
```

---

## 🧪 Future Enhancements

* AI-based arrival prediction
* Driver dashboard
* Offline caching
* Multi-college scalability

---

## 👨‍💻 Author
CODE INHALERS - An Upgrowing tech .env

---

## 📄 License

This project is developed for academic and learning purposes.
