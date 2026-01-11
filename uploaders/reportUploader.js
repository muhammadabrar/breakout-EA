import pool from '../db.js';

export async function uploadReport(reportData) {
  const {
    instrument,
    strategy,
    eaName = 'Breakout EA by currency pro',
    netProfit,
    profitableTrades,
    totalTrades,
    winRate,
    lossRate,
    balanceDrawdownAbsolute,
    balanceDrawdownMaximal,
    balanceDrawdownRelative,
    equityDrawdownAbsolute,
    equityDrawdownMaximal,
    equityDrawdownRelative,
    consecutiveWins,
    consecutiveLosses,
    maxConsecutiveWins,
    maxConsecutiveLosses,
  } = reportData;

  const query = `
    INSERT INTO reports (
      instrument, strategy, ea_name, net_profit, profitable_trades, total_trades,
      win_rate, loss_rate, balance_drawdown_absolute, balance_drawdown_maximal,
      balance_drawdown_relative, equity_drawdown_absolute, equity_drawdown_maximal,
      equity_drawdown_relative, consecutive_wins, consecutive_losses,
      max_consecutive_wins, max_consecutive_losses
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
    ON CONFLICT (instrument, strategy) 
    DO UPDATE SET
      ea_name = EXCLUDED.ea_name,
      net_profit = EXCLUDED.net_profit,
      profitable_trades = EXCLUDED.profitable_trades,
      total_trades = EXCLUDED.total_trades,
      win_rate = EXCLUDED.win_rate,
      loss_rate = EXCLUDED.loss_rate,
      balance_drawdown_absolute = EXCLUDED.balance_drawdown_absolute,
      balance_drawdown_maximal = EXCLUDED.balance_drawdown_maximal,
      balance_drawdown_relative = EXCLUDED.balance_drawdown_relative,
      equity_drawdown_absolute = EXCLUDED.equity_drawdown_absolute,
      equity_drawdown_maximal = EXCLUDED.equity_drawdown_maximal,
      equity_drawdown_relative = EXCLUDED.equity_drawdown_relative,
      consecutive_wins = EXCLUDED.consecutive_wins,
      consecutive_losses = EXCLUDED.consecutive_losses,
      max_consecutive_wins = EXCLUDED.max_consecutive_wins,
      max_consecutive_losses = EXCLUDED.max_consecutive_losses
    RETURNING id;
  `;

  const result = await pool.query(query, [
    instrument,
    strategy,
    eaName,
    netProfit,
    profitableTrades,
    totalTrades,
    winRate,
    lossRate,
    balanceDrawdownAbsolute,
    balanceDrawdownMaximal,
    balanceDrawdownRelative,
    equityDrawdownAbsolute,
    equityDrawdownMaximal,
    equityDrawdownRelative,
    consecutiveWins,
    consecutiveLosses,
    maxConsecutiveWins,
    maxConsecutiveLosses,
  ]);

  return result.rows[0].id;
}

export async function getReportId(instrument, strategy) {
  const query = 'SELECT id FROM reports WHERE instrument = $1 AND strategy = $2';
  const result = await pool.query(query, [instrument, strategy]);
  return result.rows[0]?.id || null;
}

