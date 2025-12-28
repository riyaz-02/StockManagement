# Android Emulator Setup Guide

## 📱 Setting Up Android Emulator for Flutter App

Since no Android emulators are currently available, follow these steps to set up Android development:

---

## Option 1: Quick Setup with Android Studio (Recommended)

### Step 1: Install Android Studio

1. **Download Android Studio**:
   - Visit: https://developer.android.com/studio
   - Download the latest version for Windows
   - Run the installer

2. **During Installation**:
   - ✅ Check "Android SDK"
   - ✅ Check "Android SDK Platform"
   - ✅ Check "Android Virtual Device"

### Step 2: Install SDK Components

1. Open Android Studio
2. Go to **Tools → SDK Manager**
3. In **SDK Platforms** tab, install:
   - ✅ Android 13.0 (Tiramisu) - API Level 33
   - ✅ Android 12.0 (S) - API Level 31
   
4. In **SDK Tools** tab, install:
   - ✅ Android SDK Build-Tools
   - ✅ Android SDK Command-line Tools
   - ✅ Android Emulator
   - ✅ Android SDK Platform-Tools
   - ✅ Intel x86 Emulator Accelerator (HAXM)

### Step 3: Create Virtual Device

1. In Android Studio, go to **Tools → Device Manager**
2. Click **Create Device**
3. Choose a device definition:
   - **Recommended**: Pixel 5 or Pixel 6
4. Select a system image:
   - **Recommended**: Android 13.0 (API 33) with Google APIs
   - Download if not already downloaded
5. Click **Finish**

### Step 4: Configure Flutter

```bash
# Accept Android licenses
flutter doctor --android-licenses

# Verify setup
flutter doctor
```

### Step 5: Launch Emulator and Run App

```bash
# List available emulators
flutter emulators

# Launch emulator
flutter emulators --launch <emulator-id>

# OR launch from Android Studio Device Manager

# Run Flutter app
cd f:\StockManagement\flutter_app
flutter run
```

---

## Option 2: Use Physical Android Device (Faster Alternative)

### Step 1: Enable Developer Options on Phone

1. Go to **Settings → About Phone**
2. Tap **Build Number** 7 times
3. Developer Options will be enabled

### Step 2: Enable USB Debugging

1. Go to **Settings → Developer Options**
2. Enable **USB Debugging**
3. Enable **Install via USB**

### Step 3: Connect and Run

1. Connect phone to computer via USB
2. On phone, allow USB debugging when prompted
3. Run:

```bash
# Check if device is detected
flutter devices

# Run app on connected device
cd f:\StockManagement\flutter_app
flutter run
```

---

## Option 3: Run on Web (Immediate Testing)

The easiest way to test the app right now without any setup:

```bash
cd f:\StockManagement\flutter_app
flutter run -d chrome
```

This will open the app in Chrome browser immediately!

---

## 🔧 Troubleshooting

### "Unable to find any emulators"
- Install Android Studio and create an AVD (see Option 1)
- Or use a physical device (see Option 2)
- Or run on web (see Option 3)

### "Android SDK not found"
```bash
# Set Android SDK path
$env:ANDROID_HOME = "C:\Users\<YourUsername>\AppData\Local\Android\Sdk"
flutter doctor --android-licenses
```

### Emulator is slow
- Enable Hardware Acceleration (HAXM)
- Allocate more RAM to emulator (2GB minimum)
- Use a physical device instead

### Flutter doctor shows issues
```bash
# Fix Android licenses
flutter doctor --android-licenses

# Update Flutter
flutter upgrade

# Clean and rebuild
flutter clean
flutter pub get
```

---

## 🚀 Quick Start (After Setup)

Once you have an emulator or device ready:

```bash
cd f:\StockManagement\flutter_app

# Check available devices
flutter devices

# Run on first available device
flutter run

# OR specify device
flutter run -d <device-id>

# Run in release mode (faster)
flutter run --release
```

---

## 📱 Expected App Flow

1. **Splash Screen** → Language selection (English/Bengali)
2. **Login Screen** → Enter credentials
   - Admin: 9999999999 / admin123
   - Staff: 8888888888 / staff123
3. **Home Dashboard** → Navigation cards for all features
4. **Scan Item** → Use camera or manual entry
5. **Add Item** → Auto-assigned to container
6. **Tally** → Start session, scan items, lock
7. **Settings** → Change language

---

## 🎯 Recommended Approach

**For immediate testing**: Use **Option 3 (Web)** - works instantly!

**For full mobile experience**: Use **Option 2 (Physical Device)** - faster than emulator

**For development**: Use **Option 1 (Android Studio)** - full tooling support

---

## 📞 Need Help?

If you encounter issues:
1. Run `flutter doctor -v` and check for errors
2. Ensure backend is running: `http://localhost:5000/health`
3. Check API URL in `lib/utils/app_constants.dart`
   - For emulator: `http://10.0.2.2:5000/api`
   - For physical device: `http://YOUR_PC_IP:5000/api`
   - For web: `http://localhost:5000/api`

---

**Next Step**: Choose one of the three options above and follow the steps!
