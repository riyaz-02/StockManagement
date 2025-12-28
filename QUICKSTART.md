# Jewellery Stock Management System - Quick Start Guide

## 🚀 Quick Setup

### Backend Setup

1. **Navigate to backend and install dependencies**:
   ```bash
   cd backend
   npm install
   ```

2. **Seed the database** (creates admin user and sample containers):
   ```bash
   npm run seed
   ```

3. **Start the backend server**:
   ```bash
   npm run dev
   ```

   Server will run on `http://localhost:5000`

### Flutter App Setup

1. **Navigate to Flutter app**:
   ```bash
   cd flutter_app
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the app**:
   ```bash
   # For Android emulator
   flutter run

   # For specific device
   flutter devices
   flutter run -d <device-id>
   ```

## 📱 Default Login Credentials

- **Admin**: Mobile `9999999999`, Password `admin123`
- **Staff**: Mobile `8888888888`, Password `staff123`

## ✅ What's Working

### Backend (100% Complete)
- ✅ Authentication with JWT
- ✅ Container management with slot system
- ✅ Item management with auto-assignment
- ✅ Barcode scanning
- ✅ Repair workflow with slot reservation
- ✅ Tally system with double-scan prevention
- ✅ Booking system
- ✅ PDF/Excel reports

### Flutter App (70% Complete)
- ✅ Splash screen with initialization
- ✅ Login with bilingual support (English/Bengali)
- ✅ Home dashboard
- ✅ Scan item with barcode scanner
- ✅ Add new items with auto-assignment
- ✅ Container list
- ✅ Tally workflow (start, scan, lock)
- ✅ Settings with language toggle
- 🚧 Repair management (placeholder)
- 🚧 Reports (placeholder)

## 🔧 Configuration

### API URL Configuration

Edit `flutter_app/lib/utils/app_constants.dart`:

```dart
// For Android emulator
static const String baseUrl = 'http://10.0.2.2:5000/api';

// For iOS simulator
static const String baseUrl = 'http://localhost:5000/api';

// For real device (replace with your computer's IP)
static const String baseUrl = 'http://192.168.1.100:5000/api';
```

To find your IP address:
- **Windows**: `ipconfig` (look for IPv4 Address)
- **Mac/Linux**: `ifconfig` or `ip addr`

### MongoDB Configuration

The backend is configured to use MongoDB Atlas. Connection string is in `backend/.env`:

```env
MONGODB_URI=mongodb+srv://riyazjisce:sg4Ua6VfYEztDCVC@companyresearchassistan.rfodcjr.mongodb.net/jewellery_stock?retryWrites=true&w=majority&appName=CompanyResearchAssistant
```

## 📋 Testing the App

1. **Start backend**: `cd backend && npm run dev`
2. **Run Flutter app**: `cd flutter_app && flutter run`
3. **Login** with default credentials
4. **Test features**:
   - Scan Item: Use barcode scanner or manual entry
   - Add Item: Create new jewellery item (auto-assigned to container)
   - Containers: View all containers and their slots
   - Start Tally: Begin stock audit, scan items, lock tally
   - Settings: Switch language between English and Bengali

## 🎯 Core Features Demo

### 1. Add New Item
1. Tap "Add Item" from home
2. Fill in item details (name, type, metal, purity, weight)
3. Leave barcode empty for auto-generation
4. Save - item will be auto-assigned to best container

### 2. Scan Item
1. Tap "Scan Item" from home
2. Use camera to scan barcode OR enter manually
3. View item details

### 3. Tally Workflow
1. Tap "Start Tally" from home
2. Enter description and start
3. Scan items one by one (prevents double-scan)
4. View progress and weight
5. Lock tally to complete

## 🐛 Troubleshooting

### Backend Issues

**MongoDB Connection Error**:
- Check internet connection
- Verify MongoDB Atlas credentials
- Check if IP is whitelisted in MongoDB Atlas

**Port Already in Use**:
```bash
# Change PORT in backend/.env
PORT=5001
```

### Flutter Issues

**Cannot connect to API**:
- Ensure backend is running
- Check API URL in `app_constants.dart`
- For real device, use computer's IP address
- Disable firewall if needed

**Barcode Scanner Not Working**:
- Grant camera permissions
- Check AndroidManifest.xml has camera permission
- For iOS, add camera usage description in Info.plist

**Build Errors**:
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

## 📚 API Endpoints

Base URL: `http://localhost:5000/api`

### Authentication
- `POST /auth/login` - Login
- `GET /auth/me` - Get current user

### Items
- `GET /items` - List items
- `POST /items` - Create item
- `GET /items/barcode/:code` - Get by barcode
- `POST /scan` - Scan barcode

### Containers
- `GET /containers` - List containers
- `GET /containers/:id` - Get container details

### Tally
- `POST /tally/start` - Start tally
- `POST /tally/scan` - Scan item in tally
- `POST /tally/lock` - Lock tally

### Reports
- `GET /reports/daily` - Daily summary
- `GET /reports/tally/:id/pdf` - Tally PDF
- `GET /reports/tally/:id/excel` - Tally Excel

## 🔐 Security Notes

- Change JWT_SECRET in production
- Use environment variables for sensitive data
- Implement proper authentication on frontend
- Use HTTPS in production

## 📞 Support

For issues or questions, check the walkthrough.md file for detailed implementation guide.

---

**Status**: Backend 100% ✅ | Flutter 70% ✅ | Ready for Testing 🚀
