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

export default pool;
// IT_crew*1111
// postgresql://postgres:IT_crew*1111@db.ejrxhqcujctbglxgbqwk.supabase.co:5432/postgres
