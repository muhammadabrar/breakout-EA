import pg from 'pg';
import dotenv from 'dotenv';
import fs from 'fs-extra';

dotenv.config();

const { Pool } = pg;

const pool = new Pool({
  host: process.env.DB_HOST || 'aws-1-ap-northeast-2.pooler.supabase.com',
  port: process.env.DB_PORT || 6543,
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres.ejrxhqcujctbglxgbqwk',
  password: process.env.DB_PASSWORD || 'IT_crew*1111',
});
async function setupDatabase() {
  try {
    console.log('Setting up database schema...');

    // Create reports table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS reports (
        id SERIAL PRIMARY KEY,
        instrument VARCHAR(10) NOT NULL,
        strategy VARCHAR(20) NOT NULL CHECK (strategy IN ('Daily', 'Daily + London')),
        ea_name VARCHAR(100) NOT NULL DEFAULT 'Breakout EA by currency pro',
        net_profit DECIMAL(15, 2),
        profitable_trades INTEGER,
        total_trades INTEGER,
        win_rate DECIMAL(5, 2),
        loss_rate DECIMAL(5, 2),
        balance_drawdown_absolute DECIMAL(15, 2),
        balance_drawdown_maximal DECIMAL(15, 2),
        balance_drawdown_relative DECIMAL(5, 2),
        equity_drawdown_absolute DECIMAL(15, 2),
        equity_drawdown_maximal DECIMAL(15, 2),
        equity_drawdown_relative DECIMAL(5, 2),
        consecutive_wins INTEGER,
        consecutive_losses INTEGER,
        max_consecutive_wins INTEGER,
        max_consecutive_losses INTEGER,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(instrument, strategy, ea_name)
      );
    `);
    
    // Migrate existing unique constraint if needed
    try {
      await pool.query(`
        ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_instrument_strategy_key;
      `);
    } catch (e) {
      // Constraint might not exist, ignore
    }

    // Create balance_equity table for time series data
    await pool.query(`
      CREATE TABLE IF NOT EXISTS balance_equity (
        id SERIAL PRIMARY KEY,
        report_id INTEGER REFERENCES reports(id) ON DELETE CASCADE,
        instrument VARCHAR(10) NOT NULL,
        strategy VARCHAR(20) NOT NULL,
        date_time TIMESTAMP NOT NULL,
        balance DECIMAL(15, 2) NOT NULL,
        equity DECIMAL(15, 2) NOT NULL,
        deposit_load DECIMAL(15, 4) DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create deals table
    await pool.query(`
      CREATE TABLE IF NOT EXISTS deals (
        id SERIAL PRIMARY KEY,
        report_id INTEGER REFERENCES reports(id) ON DELETE CASCADE,
        instrument VARCHAR(10) NOT NULL,
        strategy VARCHAR(20) NOT NULL,
        deal_number INTEGER NOT NULL,
        time TIMESTAMP NOT NULL,
        symbol VARCHAR(50),
        type VARCHAR(20),
        direction VARCHAR(10),
        volume DECIMAL(10, 2),
        in_price DECIMAL(15, 5),
        out_price DECIMAL(15, 5),
        profit DECIMAL(15, 2),
        commission DECIMAL(10, 2) DEFAULT 0,
        swap DECIMAL(10, 2) DEFAULT 0,
        balance DECIMAL(15, 2),
        comment TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    `);

    // Create indexes for better query performance
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_reports_instrument_strategy ON reports(instrument, strategy);
      CREATE INDEX IF NOT EXISTS idx_reports_ea_name ON reports(ea_name);
      CREATE INDEX IF NOT EXISTS idx_reports_instrument_strategy_ea ON reports(instrument, strategy, ea_name);
      CREATE INDEX IF NOT EXISTS idx_balance_equity_report_id ON balance_equity(report_id);
      CREATE INDEX IF NOT EXISTS idx_balance_equity_instrument_strategy ON balance_equity(instrument, strategy);
      CREATE INDEX IF NOT EXISTS idx_balance_equity_date_time ON balance_equity(date_time);
      CREATE INDEX IF NOT EXISTS idx_deals_report_id ON deals(report_id);
      CREATE INDEX IF NOT EXISTS idx_deals_instrument_strategy ON deals(instrument, strategy);
      CREATE INDEX IF NOT EXISTS idx_deals_time ON deals(time);
    `);

    console.log('Database schema created successfully!');
  } catch (error) {
    console.error('Error setting up database:', error);
    throw error;
  } finally {
    await pool.end();
  }
}

setupDatabase();

