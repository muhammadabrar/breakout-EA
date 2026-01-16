import pool from './db.js';

/**
 * Get max drawdown across all instruments and strategies
 */
export async function getMaxDrawdown(instrument = null, strategy = null) {
  let query = `
    SELECT 
      instrument,
      strategy,
      MAX(balance_drawdown_maximal) as max_balance_drawdown,
      MAX(equity_drawdown_maximal) as max_equity_drawdown,
      MAX(balance_drawdown_relative) as max_balance_drawdown_pct,
      MAX(equity_drawdown_relative) as max_equity_drawdown_pct
    FROM reports
    WHERE 1=1
  `;
  const params = [];

  if (instrument) {
    query += ` AND instrument = $${params.length + 1}`;
    params.push(instrument);
  }

  if (strategy) {
    query += ` AND strategy = $${params.length + 1}`;
    params.push(strategy);
  }

  query += ` GROUP BY instrument, strategy ORDER BY max_balance_drawdown DESC`;

  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Get win rate across all instruments and strategies
 */
export async function getWinRate(instrument = null, strategy = null) {
  let query = `
    SELECT 
      instrument,
      strategy,
      AVG(win_rate) as avg_win_rate,
      AVG(loss_rate) as avg_loss_rate,
      SUM(profitable_trades) as total_profitable_trades,
      SUM(total_trades) as total_trades,
      ROUND(SUM(profitable_trades)::numeric / NULLIF(SUM(total_trades), 0) * 100, 2) as overall_win_rate
    FROM reports
    WHERE 1=1
  `;
  const params = [];

  if (instrument) {
    query += ` AND instrument = $${params.length + 1}`;
    params.push(instrument);
  }

  if (strategy) {
    query += ` AND strategy = $${params.length + 1}`;
    params.push(strategy);
  }

  query += ` GROUP BY instrument, strategy ORDER BY overall_win_rate DESC`;

  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Get monthly PnL for all available months
 */
export async function getMonthlyPnL(instrument = null, strategy = null, eaName = null) {
  let query = `
    SELECT 
      DATE_TRUNC('month', d.time) as month,
      d.instrument,
      d.strategy,
      r.ea_name,
      SUM(d.profit) as monthly_pnl,
      COUNT(*) as trade_count,
      SUM(CASE WHEN d.profit > 0 THEN 1 ELSE 0 END) as winning_trades,
      SUM(CASE WHEN d.profit < 0 THEN 1 ELSE 0 END) as losing_trades
    FROM deals d
    JOIN reports r ON d.report_id = r.id
    WHERE d.profit IS NOT NULL
  `;
  const params = [];

  if (instrument) {
    query += ` AND d.instrument = $${params.length + 1}`;
    params.push(instrument);
  }

  if (strategy) {
    query += ` AND d.strategy = $${params.length + 1}`;
    params.push(strategy);
  }

  if (eaName) {
    query += ` AND r.ea_name = $${params.length + 1}`;
    params.push(eaName);
  }

  query += `
    GROUP BY DATE_TRUNC('month', d.time), d.instrument, d.strategy, r.ea_name
    ORDER BY month DESC, d.instrument, d.strategy, r.ea_name
  `;

  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Get combined statistics across multiple instruments
 */
export async function getCombinedStats(instruments = [], strategies = [], eaNames = []) {
  let query = `
    SELECT 
      instrument,
      strategy,
      ea_name,
      SUM(net_profit) as total_net_profit,
      SUM(profitable_trades) as total_profitable_trades,
      SUM(total_trades) as total_trades,
      ROUND(SUM(profitable_trades)::numeric / NULLIF(SUM(total_trades), 0) * 100, 2) as combined_win_rate,
      MAX(balance_drawdown_maximal) as max_drawdown,
      MAX(equity_drawdown_maximal) as max_equity_drawdown
    FROM reports
    WHERE 1=1
  `;
  const params = [];

  if (instruments.length > 0) {
    query += ` AND instrument = ANY($${params.length + 1})`;
    params.push(instruments);
  }

  if (strategies.length > 0) {
    query += ` AND strategy = ANY($${params.length + 1})`;
    params.push(strategies);
  }

  if (eaNames.length > 0) {
    query += ` AND ea_name = ANY($${params.length + 1})`;
    params.push(eaNames);
  }

  query += ` GROUP BY instrument, strategy, ea_name ORDER BY total_net_profit DESC`;

  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Get all reports summary
 */
export async function getAllReports(eaName = null) {
  let query = `
    SELECT 
      id,
      instrument,
      strategy,
      ea_name,
      net_profit,
      profitable_trades,
      total_trades,
      win_rate,
      loss_rate,
      balance_drawdown_maximal,
      equity_drawdown_maximal,
      consecutive_wins,
      consecutive_losses,
      max_consecutive_wins,
      max_consecutive_losses
    FROM reports
    WHERE 1=1
  `;
  const params = [];

  if (eaName) {
    query += ` AND ea_name = $1`;
    params.push(eaName);
  }

  query += ` ORDER BY instrument, strategy, ea_name`;

  const result = await pool.query(query, params);
  return result.rows;
}

/**
 * Get balance and equity time series for a specific report
 */
export async function getBalanceEquitySeries(reportId) {
  const query = `
    SELECT 
      date_time,
      balance,
      equity,
      deposit_load
    FROM balance_equity
    WHERE report_id = $1
    ORDER BY date_time ASC
  `;

  const result = await pool.query(query, [reportId]);
  return result.rows;
}

/**
 * Get deals for a specific report
 */
export async function getDeals(reportId, limit = null) {
  let query = `
    SELECT 
      deal_number,
      time,
      symbol,
      type,
      direction,
      volume,
      in_price,
      out_price,
      profit,
      commission,
      swap,
      balance,
      comment
    FROM deals
    WHERE report_id = $1
    ORDER BY time ASC
  `;

  const params = [reportId];

  if (limit) {
    query += ` LIMIT $2`;
    params.push(limit);
  }

  const result = await pool.query(query, params);
  return result.rows;
}

