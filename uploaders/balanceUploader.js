import pool from '../db.js';

export async function uploadBalanceData(reportId, instrument, strategy, balanceData) {
  // Delete existing balance data for this report
  await pool.query(
    'DELETE FROM balance_equity WHERE report_id = $1',
    [reportId]
  );

  if (balanceData.length === 0) {
    return;
  }

  // Insert balance data in batches
  const batchSize = 500;
  for (let i = 0; i < balanceData.length; i += batchSize) {
    const batch = balanceData.slice(i, i + batchSize);
    
    // Prepare arrays for unnest
    const reportIds = batch.map(() => reportId);
    const instruments = batch.map(() => instrument);
    const strategies = batch.map(() => strategy);
    const dateTimes = batch.map(item => item.dateTime);
    const balances = batch.map(item => item.balance);
    const equities = batch.map(item => item.equity);
    const depositLoads = batch.map(item => item.depositLoad);

    const query = `
      INSERT INTO balance_equity (report_id, instrument, strategy, date_time, balance, equity, deposit_load)
      SELECT * FROM unnest(
        $1::INTEGER[],
        $2::VARCHAR[],
        $3::VARCHAR[],
        $4::TIMESTAMP[],
        $5::DECIMAL(15,2)[],
        $6::DECIMAL(15,2)[],
        $7::DECIMAL(15,4)[]
      )
    `;

    await pool.query(query, [
      reportIds,
      instruments,
      strategies,
      dateTimes,
      balances,
      equities,
      depositLoads
    ]);
  }
}

