# Breakout EA Data Uploader

Node.js application to upload MT5 report data (HTML reports, CSV balance reports, and deals) to PostgreSQL database for analysis and comparison across multiple instruments.

## Features

- Parses HTML reports to extract trading statistics
- Parses CSV balance reports to extract balance and equity time series
- Parses deals from HTML reports to extract trade details (in price, out price, profit)
- Stores data in PostgreSQL with proper relationships
- Supports multiple instruments (US30, US100, XAU)
- Supports multiple strategies (Daily, Daily + London)
- Query helpers for aggregations (max drawdown, win rate, monthly PnL)

## Prerequisites

- Node.js (v16 or higher)
- PostgreSQL (v12 or higher)

## Installation

1. Install dependencies:
```bash
npm install
```

2. Create a `.env` file based on `.env.example`:
```bash
cp .env.example .env
```

3. Edit `.env` with your PostgreSQL credentials:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=breakout_ea
DB_USER=postgres
DB_PASSWORD=your_password
```

4. Create the database:
```bash
createdb breakout_ea
```

5. Set up the database schema:
```bash
npm run setup-db
```

## Usage

### Upload Data

To upload all reports from the directory structure:
```bash
npm run upload
```

The script will:
- Automatically detect instrument and strategy from directory names
- Parse HTML reports for statistics
- Parse CSV balance reports for balance/equity data
- Parse deals from HTML reports
- Upload everything to PostgreSQL

### Directory Structure

The application expects the following directory structure:
```
breakout-EA/
├── us30 - daily + london/
│   ├── html report.html
│   ├── balance report.csv
│   └── ...
├── us30 - daily only/
│   ├── html report.html
│   ├── balance chart.csv
│   └── ...
├── us100 - daily + london/
│   └── ...
└── xau - daily only/
    └── ...
```

## Database Schema

### Reports Table
Stores main trading statistics:
- `instrument` (us30, us100, xau)
- `strategy` (Daily, Daily + London)
- `net_profit`, `profitable_trades`, `total_trades`
- `win_rate`, `loss_rate`
- `balance_drawdown_*`, `equity_drawdown_*`
- `consecutive_wins`, `consecutive_losses`

### Balance_Equity Table
Stores time series balance and equity data:
- `report_id` (foreign key to reports)
- `date_time`, `balance`, `equity`

### Deals Table
Stores individual trade details:
- `report_id` (foreign key to reports)
- `deal_number`, `time`, `symbol`
- `in_price`, `out_price`, `profit`
- `commission`, `swap`, `balance`

## Query Examples

### Get Max Drawdown
```javascript
import { getMaxDrawdown } from './queries.js';

// All instruments
const drawdowns = await getMaxDrawdown();

// Specific instrument
const us30Drawdown = await getMaxDrawdown('us30');

// Specific instrument and strategy
const us30DailyDrawdown = await getMaxDrawdown('us30', 'Daily');
```

### Get Win Rate
```javascript
import { getWinRate } from './queries.js';

const winRates = await getWinRate();
```

### Get Monthly PnL
```javascript
import { getMonthlyPnL } from './queries.js';

// All months
const monthlyPnL = await getMonthlyPnL();

// Specific instrument
const us30MonthlyPnL = await getMonthlyPnL('us30');
```

### Get Combined Statistics
```javascript
import { getCombinedStats } from './queries.js';

// Compare multiple instruments
const stats = await getCombinedStats(['us30', 'us100', 'xau'], ['Daily', 'Daily + London']);
```

## Data Fields

### Main Report Fields
- **EA**: "Breakout EA by currency pro"
- **Strategy**: "Daily" or "Daily + London"
- **Instrument**: us30, us100, xau
- **Net Profit**: Total net profit
- **Profitable Trades**: Number of winning trades
- **Win Rate**: Percentage of winning trades
- **Loss Rate**: Percentage of losing trades
- **Balance Drawdown**: Maximum balance drawdown (absolute, relative)
- **Equity Drawdown**: Maximum equity drawdown (absolute, relative)
- **Consecutive Wins/Losses**: Average and maximum consecutive wins/losses

### Deal Fields
- **In Price**: Entry price
- **Out Price**: Exit price
- **Profit**: Trade profit/loss
- **Time**: Trade execution time

### Balance/Equity Fields
- **Balance**: Account balance at each timestamp
- **Equity**: Account equity at each timestamp
- **Date Time**: Timestamp for each record

## Notes

- The application uses PostgreSQL for better support of aggregations and analytical queries
- Data is uploaded separately for each report (statistics, balance data, deals)
- The upload script automatically detects instrument and strategy from directory names
- Existing data for the same instrument/strategy combination will be updated

