# Breakout EA Dashboard Frontend

A modern web dashboard for viewing trading performance data with filtering by instruments and strategies.

## Features

- 📊 **Overview Dashboard**: View all reports with key statistics
- 📈 **Monthly Reports**: Interactive charts showing monthly P&L
- 📋 **Combined Statistics**: Compare multiple instruments and strategies
- 🔍 **Filtering**: Select specific instruments (US30, US100, XAU) and strategies (Daily, Daily + London)
- 💹 **Real-time Data**: Live data from PostgreSQL database

## Getting Started

### Start the Server

```bash
npm run server
```

The server will start on `http://localhost:3000`

### Access the Dashboard

Open your web browser and navigate to:
```
http://localhost:3000
```

## Usage

### Filters

1. **Select Instruments**: Check/uncheck US30, US100, XAU
2. **Select Strategies**: Check/uncheck Daily, Daily + London
3. Click **"Apply Filters"** to update all views

### Tabs

- **Overview**: Summary statistics and reports table
- **Monthly Report**: Chart and table showing monthly P&L
- **Combined Stats**: Aggregated statistics by instrument/strategy

## API Endpoints

The server provides the following API endpoints:

- `GET /api/reports` - Get all reports
- `GET /api/monthly-pnl?instrument=us30&strategy=Daily` - Get monthly P&L
- `GET /api/combined-stats?instruments=us30,us100&strategies=Daily` - Get combined statistics
- `GET /api/drawdown?instrument=us30&strategy=Daily` - Get drawdown data
- `GET /api/win-rate?instrument=us30&strategy=Daily` - Get win rate data

## Project Structure

```
/
├── server.js              # Express API server
├── public/                # Frontend files
│   ├── index.html        # Main HTML page
│   ├── style.css         # Styling
│   └── app.js            # Frontend JavaScript
├── queries.js            # Database query functions
└── db.js                 # Database connection
```

