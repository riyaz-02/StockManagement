# Jewellery Stock & Container Management System

A production-ready mobile application for managing jewellery inventory with barcode/QR scanning, container-wise visual placement, audit reporting, and repair tracking.

## 🎯 Features

- **Barcode/QR Scanning**: Single source of truth for item identification
- **Container Management**: Visual slot-based placement system
- **Tally System**: Error-free stock counting with double-scan prevention
- **Repair Tracking**: Slot reservation options (free or reserve)
- **Booking System**: Customer booking management
- **Multi-language**: English + Bengali support
- **Role-based Access**: Admin, Staff, and Viewer roles
- **Reports**: Daily summary, PDF/Excel tally reports

## 📁 Project Structure

```
StockManagement/
├── backend/                 # Node.js + Express API
│   ├── controllers/        # Business logic
│   ├── models/            # MongoDB schemas
│   ├── routes/            # API endpoints
│   ├── middleware/        # Auth & validation
│   ├── server.js          # Entry point
│   ├── seed.js            # Database seeder
│   └── package.json
└── flutter_app/           # Flutter mobile app (to be created)
```

## 🚀 Backend Setup

### Prerequisites

- Node.js (v16 or higher)
- MongoDB (local or MongoDB Atlas)
- npm or yarn

### Installation

1. **Navigate to backend directory**:
   ```bash
   cd backend
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Configure environment variables**:
   ```bash
   cp .env.example .env
   ```

   Edit `.env` file:
   ```env
   PORT=5000
   MONGODB_URI=mongodb://localhost:27017/jewellery_stock
   JWT_SECRET=your_secure_random_string_here
   JWT_EXPIRE=7d
   ```

   For MongoDB Atlas:
   ```env
   MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/jewellery_stock
   ```

4. **Seed the database** (creates admin user and sample containers):
   ```bash
   npm run seed
   ```

   Default credentials:
   - **Admin**: Mobile: `9999999999`, Password: `admin123`
   - **Staff**: Mobile: `8888888888`, Password: `staff123`

5. **Start the server**:
   ```bash
   # Development mode (with auto-reload)
   npm run dev

   # Production mode
   npm start
   ```

   Server will run on `http://localhost:5000`

### API Endpoints

#### Authentication
- `POST /api/auth/login` - User login
- `POST /api/auth/register` - Register new user (admin only)
- `GET /api/auth/me` - Get current user
- `PUT /api/auth/language` - Update language preference

#### Containers
- `GET /api/containers` - List all containers
- `GET /api/containers/:id` - Get container details
- `POST /api/containers` - Create container
- `PUT /api/containers/:id` - Update container
- `DELETE /api/containers/:id` - Delete container (admin only)
- `POST /api/containers/find-slot` - Find best slot for item

#### Items
- `GET /api/items` - List all items
- `GET /api/items/:id` - Get item details
- `GET /api/items/barcode/:code` - Get item by barcode
- `POST /api/items` - Create item (auto-assigns container)
- `PUT /api/items/:id` - Update item
- `DELETE /api/items/:id` - Delete item (admin only)
- `PUT /api/items/:id/sell` - Mark item as sold
- `PUT /api/items/:id/remove-temporarily` - Temporarily remove item

#### Scan
- `POST /api/scan` - Scan barcode and get item details

#### Repair
- `GET /api/repair` - List items in repair
- `GET /api/repair/history/:itemId` - Get repair history
- `POST /api/repair/send` - Send item to repair
- `POST /api/repair/return` - Return item from repair

#### Tally
- `GET /api/tally` - List tally sessions
- `GET /api/tally/:id` - Get tally session details
- `POST /api/tally/start` - Start new tally session
- `POST /api/tally/scan` - Scan item during tally
- `POST /api/tally/lock` - Lock tally session

#### Bookings
- `GET /api/bookings` - List bookings
- `GET /api/bookings/:id` - Get booking details
- `POST /api/bookings` - Create booking
- `PUT /api/bookings/:id/cancel` - Cancel booking
- `PUT /api/bookings/:id/complete` - Complete booking (mark as sold)

#### Reports
- `GET /api/reports/daily` - Daily summary report
- `GET /api/reports/tally/:id/pdf` - Generate tally PDF
- `GET /api/reports/tally/:id/excel` - Generate tally Excel

### Testing the API

Use Postman, Insomnia, or curl to test endpoints:

```bash
# Login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"mobile": "9999999999", "password": "admin123"}'

# Get containers (requires token)
curl -X GET http://localhost:5000/api/containers \
  -H "Authorization: Bearer YOUR_TOKEN_HERE"
```

## 📱 Flutter App Setup

*(To be implemented)*

The Flutter app will be created in the `flutter_app` directory with:
- Barcode scanning using camera
- Visual container layouts
- Tally workflow
- English + Bengali localization
- Offline support

## 🗄️ Database Schema

### Collections

1. **Users**: User accounts with roles (admin/staff/viewer)
2. **Containers**: Storage containers with slot arrays
3. **Items**: Jewellery items with barcode, status, and container assignment
4. **RepairLogs**: Repair tracking with slot reservation
5. **TallySessions**: Stock audit sessions with weight calculations
6. **Bookings**: Customer bookings

### Item Status Flow

```
active → booked → sold
active → in_repair → active
active → temporarily_removed → active
```

### Repair Slot Reservation

When sending item to repair:
- **Free Place**: Slot becomes available for other items
- **Reserve Place**: Slot locked until item returns

## 🔐 Security

- JWT-based authentication
- Role-based access control (RBAC)
- Password hashing with bcrypt
- Protected routes with middleware

## 📊 Business Rules

1. **One item = One slot** (strict enforcement)
2. **No double scan** during tally (prevents errors)
3. **Repair items excluded** from stock weight
4. **Barcode is unique** (single source of truth)
5. **System assigns slots** (not manual selection)

## 🌍 Deployment

### Backend Deployment

**Option 1: Heroku**
```bash
heroku create jewellery-stock-api
heroku config:set MONGODB_URI=your_mongodb_atlas_uri
heroku config:set JWT_SECRET=your_secret
git push heroku main
```

**Option 2: DigitalOcean/AWS**
- Set up Node.js server
- Install MongoDB or use MongoDB Atlas
- Configure environment variables
- Use PM2 for process management
- Set up Nginx as reverse proxy

### Database Deployment

**MongoDB Atlas** (Recommended):
1. Create free cluster at mongodb.com/cloud/atlas
2. Whitelist IP addresses
3. Create database user
4. Get connection string
5. Update `MONGODB_URI` in `.env`

## 🛠️ Development

### Adding New Features

1. Create model in `models/`
2. Create controller in `controllers/`
3. Create routes in `routes/`
4. Register routes in `server.js`

### Code Structure

- **Models**: Mongoose schemas with validation
- **Controllers**: Business logic and data processing
- **Routes**: API endpoint definitions
- **Middleware**: Authentication and authorization

## 📝 License

This project is proprietary software for jewellery shop management.

## 🤝 Support

For issues or questions, contact the development team.

---

**Version**: 1.0.0  
**Last Updated**: December 2025
