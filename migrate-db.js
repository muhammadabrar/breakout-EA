import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

const pool = new Pool({
  host: process.env.DB_HOST || 'aws-1-ap-northeast-2.pooler.supabase.com',
  port: process.env.DB_PORT || 6543,
  database: process.env.DB_NAME || 'postgres',
  user: process.env.DB_USER || 'postgres.ejrxhqcujctbglxgbqwk',
  password: process.env.DB_PASSWORD || 'IT_crew*1111',
});

async function migrateDatabase() {
  try {
    console.log('Migrating database schema...');

    // Check if table exists
    const tableCheck = await pool.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.tables 
        WHERE table_name = 'reports'
      );
    `);

    if (!tableCheck.rows[0].exists) {
      console.log('Reports table does not exist. Please run setup-db.js first.');
      return;
    }

    // Check if ea_name column exists
    const columnCheck = await pool.query(`
      SELECT EXISTS (
        SELECT FROM information_schema.columns 
        WHERE table_name = 'reports' AND column_name = 'ea_name'
      );
    `);

    if (!columnCheck.rows[0].exists) {
      console.log('Adding ea_name column...');
      await pool.query(`
        ALTER TABLE reports 
        ADD COLUMN ea_name VARCHAR(100) NOT NULL DEFAULT 'Breakout EA by currency pro';
      `);
      console.log('✓ Added ea_name column');
    }

    // Drop old unique constraint if it exists
    try {
      await pool.query(`
        ALTER TABLE reports 
        DROP CONSTRAINT IF EXISTS reports_instrument_strategy_key;
      `);
      console.log('✓ Dropped old unique constraint (instrument, strategy)');
    } catch (e) {
      console.log('Old constraint does not exist or already dropped');
    }

    // Try to drop constraint by name if it exists with different name
    try {
      const constraints = await pool.query(`
        SELECT constraint_name 
        FROM information_schema.table_constraints 
        WHERE table_name = 'reports' 
        AND constraint_type = 'UNIQUE'
        AND constraint_name != 'reports_instrument_strategy_ea_name_key';
      `);
      
      for (const row of constraints.rows) {
        await pool.query(`ALTER TABLE reports DROP CONSTRAINT IF EXISTS ${row.constraint_name};`);
        console.log(`✓ Dropped constraint: ${row.constraint_name}`);
      }
    } catch (e) {
      // Ignore errors
    }

    // Add new unique constraint with ea_name
    try {
      await pool.query(`
        ALTER TABLE reports 
        ADD CONSTRAINT reports_instrument_strategy_ea_name_key 
        UNIQUE (instrument, strategy, ea_name);
      `);
      console.log('✓ Added new unique constraint (instrument, strategy, ea_name)');
    } catch (e) {
      if (e.message.includes('already exists')) {
        console.log('✓ Unique constraint (instrument, strategy, ea_name) already exists');
      } else {
        throw e;
      }
    }

    // Create indexes if they don't exist
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_reports_ea_name ON reports(ea_name);
    `);
    console.log('✓ Created index on ea_name');

    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_reports_instrument_strategy_ea ON reports(instrument, strategy, ea_name);
    `);
    console.log('✓ Created composite index on (instrument, strategy, ea_name)');

    console.log('\n✓ Database migration completed successfully!');
  } catch (error) {
    console.error('Error migrating database:', error);
    throw error;
  } finally {
    await pool.end();
  }
}

migrateDatabase();

