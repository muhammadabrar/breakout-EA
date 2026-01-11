import pool from '../db.js';

export async function uploadDeals(reportId, instrument, strategy, deals) {
  // Delete existing deals for this report
  await pool.query(
    'DELETE FROM deals WHERE report_id = $1',
    [reportId]
  );

  if (deals.length === 0) {
    return;
  }

  // Insert deals in batches using unnest
  const batchSize = 500;
  for (let i = 0; i < deals.length; i += batchSize) {
    const batch = deals.slice(i, i + batchSize);
    
    // Prepare arrays for unnest
    const reportIds = batch.map(() => reportId);
    const instruments = batch.map(() => instrument);
    const strategies = batch.map(() => strategy);
    const dealNumbers = batch.map(d => d.dealNumber);
    const times = batch.map(d => d.time);
    const symbols = batch.map(d => d.symbol || null);
    const types = batch.map(d => d.type || null);
    const directions = batch.map(d => d.direction || null);
    const volumes = batch.map(d => d.volume || 0);
    const inPrices = batch.map(d => d.inPrice);
    const outPrices = batch.map(d => d.outPrice);
    const profits = batch.map(d => d.profit || 0);
    const commissions = batch.map(d => d.commission || 0);
    const swaps = batch.map(d => d.swap || 0);
    const balances = batch.map(d => d.balance || null);
    const comments = batch.map(d => d.comment || null);

    const query = `
      INSERT INTO deals (
        report_id, instrument, strategy, deal_number, time, symbol, type, direction,
        volume, in_price, out_price, profit, commission, swap, balance, comment
      )
      SELECT * FROM unnest(
        $1::INTEGER[],
        $2::VARCHAR[],
        $3::VARCHAR[],
        $4::INTEGER[],
        $5::TIMESTAMP[],
        $6::VARCHAR[],
        $7::VARCHAR[],
        $8::VARCHAR[],
        $9::DECIMAL(10,2)[],
        $10::DECIMAL(15,5)[],
        $11::DECIMAL(15,5)[],
        $12::DECIMAL(15,2)[],
        $13::DECIMAL(10,2)[],
        $14::DECIMAL(10,2)[],
        $15::DECIMAL(15,2)[],
        $16::TEXT[]
      )
    `;

    await pool.query(query, [
      reportIds,
      instruments,
      strategies,
      dealNumbers,
      times,
      symbols,
      types,
      directions,
      volumes,
      inPrices,
      outPrices,
      profits,
      commissions,
      swaps,
      balances,
      comments
    ]);
  }
}

