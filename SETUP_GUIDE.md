# 📦 Jewellery Stock Management System - Complete Setup Guide

## 📋 Table of Contents
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Detailed Setup](#detailed-setup)
- [Configuration](#configuration)
- [Running the Application](#running-the-application)
- [Default Credentials](#default-credentials)
- [Features Overview](#features-overview)
- [Troubleshooting](#troubleshooting)

---

## 🔧 Prerequisites

### Required Software
1. **Node.js** (v14 or higher)
   - Download from [nodejs.org](https://nodejs.org/)
   - Verify: `node --version` and `npm --version`

2. **Flutter** (v3.0 or higher)
   - Download from [flutter.dev](https://flutter.dev/docs/get-started/install)
   - Verify: `flutter --version`

3. **MongoDB Atlas Account** (Free tier works)
   - Sign up at [mongodb.com/cloud/atlas](https://www.mongodb.com/cloud/atlas)
   - Or use local MongoDB installation

4. **Code Editor** (Optional but recommended)
   - VS Code with Flutter/Dart extensions
   - Android Studio

5. **Device/Emulator**
   - Android Emulator, iOS Simulator, or Chrome browser
   - For mobile: Android Studio or Xcode

---

## 🚀 Quick Start

### 1. Clone/Download the Project
```bash
cd f:\StockManagement
```

### 2. Backend Setup (5 minutes)
```bash
# Navigate to backend
cd backend

# Install dependencies
npm install

# Seed database (creates admin user & sample data)
npm run seed

# Start server
npm run dev
```
✅ Backend should be running on `http://localhost:5000`

### 3. Flutter App Setup (5 minutes)
```bash
# Navigate to Flutter app
cd flutter_app

# Install dependencies
flutter pub get

# Run on Chrome (easiest for testing)
flutter run -d chrome

# OR run on Android emulator
flutter run

# OR run on specific device
flutter devices
flutter run -d <device-id>
```

### 4. Login
- Open the app
- Use default credentials:
  - **Admin**: Mobile `9999999999`, Password `admin123`
  - **Staff**: Mobile `8888888888`, Password `staff123`

---

## 📖 Detailed Setup

### Backend Configuration

#### 1. Environment Variables
Create/verify `backend/.env` file:
```env
# Server Configuration
PORT=5000
NODE_ENV=development

# MongoDB Connection
MONGODB_URI=mongodb+srv://riyazjisce:sg4Ua6VfYEztDCVC@companyresearchassistan.rfodcjr.mongodb.net/jewellery_stock?retryWrites=true&w=majority&appName=CompanyResearchAssistant

# JWT Secret (Change in production!)
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production

# File Upload
MAX_FILE_SIZE=5242880
```

#### 2. Database Seeding
The seed script creates:
- Admin user (mobile: 9999999999)
- Staff user (mobile: 8888888888)
- Sample containers (Rings I, Rings II, Bangles I)
- Sample items with barcodes

```bash
cd backend
npm run seed
```

#### 3. Start Backend
```bash
# Development mode (with auto-reload)
npm run dev

# OR Production mode
npm start
```

### Flutter App Configuration

#### 1. API URL Setup
Edit `flutter_app/lib/utils/app_constants.dart`:

```dart
class AppConstants {
  // Choose based on your setup:
  
  // For Chrome/Web
  static const String baseUrl = 'http://localhost:5000/api';
  
  // For Android Emulator
  // static const String baseUrl = 'http://10.0.2.2:5000/api';
  
  // For iOS Simulator
  // static const String baseUrl = 'http://localhost:5000/api';
  
  // For Real Device (replace with your computer's IP)
  // static const String baseUrl = 'http://192.168.1.100:5000/api';
}
```

**Finding Your IP Address:**
- Windows: `ipconfig` (look for IPv4 Address)
- Mac/Linux: `ifconfig` or `ip addr show`

#### 2. Install Dependencies
```bash
cd flutter_app
flutter pub get
```

#### 3. Platform-Specific Setup

**For Android:**
- Ensure Android SDK is installed
- Create/start an Android emulator
- Permissions are already configured in `AndroidManifest.xml`

**For iOS:**
- Requires macOS with Xcode
- Camera permissions configured in `Info.plist`

**For Web/Chrome:**
- No additional setup needed
- Best for quick testing

---

## ⚙️ Configuration

### Database Configuration

#### Using MongoDB Atlas (Recommended)
1. Create free cluster at [mongodb.com/cloud/atlas](https://www.mongodb.com/cloud/atlas)
2. Create database user
3. Whitelist IP address (0.0.0.0/0 for testing)
4. Get connection string
5. Update `MONGODB_URI` in `backend/.env`

#### Using Local MongoDB
```env
MONGODB_URI=mongodb://localhost:27017/jewellery_stock
```

### File Upload Configuration
- Max file size: 5MB (configurable in `.env`)
- Supported formats: JPG, PNG, JPEG
- Upload directory: `backend/uploads/`

---

## 🎮 Running the Application

### Development Mode

**Terminal 1 - Backend:**
```bash
cd backend
npm run dev
```

**Terminal 2 - Flutter:**
```bash
cd flutter_app
flutter run -d chrome
```

### Production Mode

**Backend:**
```bash
cd backend
npm start
```

**Flutter (Build):**
```bash
# Android APK
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web
```

---

## 🔑 Default Credentials

### Admin Account
- **Mobile:** `9999999999`
- **Password:** `admin123`
- **Permissions:** Full access

### Staff Account
- **Mobile:** `8888888888`
- **Password:** `staff123`
- **Permissions:** Limited access

> ⚠️ **Security Note:** Change these credentials in production!

---

## ✨ Features Overview

### ✅ Fully Implemented Features

#### Item Management
- ✅ Add new items with image upload
- ✅ Auto-generate barcodes (5-digit unique)
- ✅ Auto-assign to optimal containers
- ✅ Edit item details
- ✅ Soft delete (Recycle Bin)
- ✅ Barcode scanning

#### Container Management
- ✅ Create containers with slot layouts
- ✅ Visual slot grid (3x3, 4x4, 5x5)
- ✅ Auto-assignment based on item type & weight
- ✅ Slot reservation system
- ✅ QR code generation

#### Customer Interactions
- ✅ Wishlist management
- ✅ Booking system with advance payment
- ✅ Customer tracking (mobile-based)
- ✅ Booking status updates (Pending, Manufacturing, Cancelled)

#### Sales & Operations
- ✅ Sell items with customer details
- ✅ Send to repair with vendor tracking
- ✅ Slot reservation during repair
- ✅ Expected return date tracking

#### Tally System
- ✅ Start stock audit
- ✅ Barcode scanning with duplicate prevention
- ✅ Real-time weight calculation
- ✅ Lock tally to prevent changes
- ✅ PDF & Excel export

#### Reports
- ✅ Daily summary reports
- ✅ Tally reports (PDF/Excel)
- ✅ Container occupancy reports

#### UI/UX
- ✅ Bilingual support (English/Bengali)
- ✅ Glassmorphism design
- ✅ Responsive layouts
- ✅ Image carousel for items
- ✅ Barcode display (vertical)
- ✅ Weight badge on images

---

## 🐛 Troubleshooting

### Backend Issues

#### MongoDB Connection Failed
```
Error: MongoNetworkError: failed to connect to server
```
**Solutions:**
- Check internet connection
- Verify MongoDB Atlas credentials
- Whitelist your IP in MongoDB Atlas
- Check firewall settings

#### Port Already in Use
```
Error: listen EADDRINUSE: address already in use :::5000
```
**Solutions:**
```bash
# Windows: Kill process on port 5000
netstat -ano | findstr :5000
taskkill /PID <PID> /F

# Linux/Mac
lsof -ti:5000 | xargs kill -9

# OR change port in .env
PORT=5001
```

### Flutter Issues

#### Cannot Connect to Backend
```
SocketException: Failed to connect to localhost:5000
```
**Solutions:**
1. Ensure backend is running (`npm run dev`)
2. Check API URL in `app_constants.dart`
3. For Android emulator, use `10.0.2.2` instead of `localhost`
4. For real device, use computer's IP address
5. Disable firewall temporarily

#### Build Errors
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

#### Camera/Barcode Scanner Not Working
**Android:**
- Grant camera permission in app settings
- Check `AndroidManifest.xml` has camera permission

**iOS:**
- Add camera usage description in `Info.plist`

**Web:**
- Use HTTPS or localhost
- Grant camera permission in browser

#### Hot Reload Not Working
```bash
# Press 'R' in terminal for hot restart
# OR press 'r' for hot reload
```

### Common Errors

#### "setState() called during build"
- Already fixed in latest code
- If occurs, hot restart the app

#### "Item data disappearing"
- Fixed: API response parsing issue
- Ensure using latest code

#### Images Not Loading
- Check `baseUrl` in `app_constants.dart`
- Ensure backend is serving static files
- Verify image paths in database

---

## 📱 Testing the Application

### 1. Login Flow
- Launch app → See splash screen
- Login with admin credentials
- Verify dashboard loads

### 2. Add Item
- Tap "Add Item"
- Fill details (leave barcode empty for auto-generation)
- Upload image (optional)
- Save → Item auto-assigned to container

### 3. Scan Item
- Tap "Scan Item"
- Use camera or enter barcode manually
- View item details with image carousel

### 4. Manage Bookings
- Open item details
- Tap "Book" button
- Enter customer details
- View booking in customer interactions

### 5. Sell Item
- Open item details
- Tap "Sell" button
- Enter customer details
- Item status changes to "Sold"

### 6. Send to Repair
- Open item details
- Tap "Repair" button
- Enter vendor and repair type
- Choose to reserve slot
- Item status changes to "In Repair"

### 7. Tally Workflow
- Tap "Start Tally"
- Enter description
- Scan items (prevents duplicates)
- View progress
- Lock tally
- Export PDF/Excel

---

## 🔐 Security Best Practices

### For Production Deployment

1. **Change JWT Secret**
   ```env
   JWT_SECRET=use-a-strong-random-secret-here
   ```

2. **Use Environment Variables**
   - Never commit `.env` file
   - Use secure secret management

3. **Enable HTTPS**
   - Use SSL certificates
   - Configure reverse proxy (nginx)

4. **Update Default Passwords**
   - Change admin/staff passwords
   - Implement password policies

5. **Database Security**
   - Use strong MongoDB credentials
   - Restrict IP whitelist
   - Enable authentication

---

## 📚 API Documentation

### Base URL
```
http://localhost:5000/api
```

### Authentication
```
POST /auth/login
POST /auth/register
GET  /auth/me
```

### Items
```
GET    /items
POST   /items
GET    /items/:id
PUT    /items/:id
DELETE /items/:id
GET    /items/barcode/:code
POST   /items/:id/sell
POST   /items/:id/repair
```

### Containers
```
GET    /containers
POST   /containers
GET    /containers/:id
PUT    /containers/:id
DELETE /containers/:id
```

### Customers
```
POST   /customers/wishlist
DELETE /customers/wishlist
GET    /customers/interactions/:itemId
```

### Bookings
```
GET    /bookings
POST   /bookings
GET    /bookings/:id
PUT    /bookings/:id
DELETE /bookings/:id
```

### Tally
```
POST   /tally/start
POST   /tally/scan
POST   /tally/lock
GET    /tally/:id
```

### Reports
```
GET    /reports/daily
GET    /reports/tally/:id/pdf
GET    /reports/tally/:id/excel
```

---

## 📞 Support & Resources

- **QUICKSTART.md** - Quick reference guide
- **README.md** - Project overview
- **ANDROID_SETUP.md** - Android-specific setup

---

## ✅ Verification Checklist

After setup, verify:
- [ ] Backend running on port 5000
- [ ] MongoDB connected successfully
- [ ] Flutter app launches
- [ ] Can login with default credentials
- [ ] Can add new item
- [ ] Can scan barcode
- [ ] Images display correctly
- [ ] Barcode displays vertically
- [ ] Weight badge shows on images
- [ ] Can create booking
- [ ] Can sell item
- [ ] Can send to repair
- [ ] Tally workflow works

---

**Status:** ✅ Production Ready | Last Updated: January 2026
