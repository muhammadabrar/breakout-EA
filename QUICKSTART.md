# Quick Start Guide

## 1. Install Dependencies

```bash
npm install
```

## 2. Set Up PostgreSQL Database

Make sure PostgreSQL is running and create the database:

```bash
createdb breakout_ea
```

## 3. Configure Database Connection

Create a `.env` file:

```bash
cp .env.example .env
```

Edit `.env` with your PostgreSQL credentials:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=breakout_ea
DB_USER=postgres
DB_PASSWORD=your_password
```

## 4. Initialize Database Schema

```bash
npm run setup-db
```

This creates the following tables:
- `reports` - Main trading statistics
- `balance_equity` - Time series balance and equity data
- `deals` - Individual trade details

## 5. Upload Data

```bash
npm run upload
```

This will:
- Scan all directories in the project
- Detect instrument (us30, us100, xau) and strategy (Daily, Daily + London) from directory names
- Parse HTML reports for statistics
- Parse CSV balance reports for balance/equity data
- Parse deals from HTML reports
- Upload everything to PostgreSQL

## 6. Query Data

Run example queries:

```bash
npm run queries
```

Or use the query functions in your own code:

```javascript
import { getMaxDrawdown, getWinRate, getMonthlyPnL } from './queries.js';

// Get max drawdown for all instruments
const drawdowns = await getMaxDrawdown();

// Get win rates
const winRates = await getWinRate();

// Get monthly PnL
const monthlyPnL = await getMonthlyPnL();
```

## Directory Structure

The upload script expects directories named like:
- `us30 - daily + london/`
- `us30 - daily only/`
- `us100 - daily + london/`
- `xau - daily only/`

Each directory should contain:
- HTML report file (e.g., `html report.html`)
- CSV balance report (e.g., `balance report.csv`)

## Troubleshooting

### Database Connection Error
- Check PostgreSQL is running: `pg_isready`
- Verify credentials in `.env`
- Ensure database exists: `psql -l | grep breakout_ea`

### No Data Uploaded
- Check directory names match expected format
- Verify HTML and CSV files exist in each directory
- Check console output for error messages

### Parsing Errors
- Ensure HTML files are valid MT5 reports
- Check CSV files use tab delimiter
- Verify file encoding is UTF-8

