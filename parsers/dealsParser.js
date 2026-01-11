import fs from 'fs-extra';
import * as cheerio from 'cheerio';

export function parseDeals(htmlPath) {
  // Read file as buffer to detect encoding
  const buffer = fs.readFileSync(htmlPath);
  
  // Check for UTF-16 BOM (FE FF for BE, FF FE for LE)
  let html;
  if (buffer[0] === 0xFF && buffer[1] === 0xFE) {
    // UTF-16 Little Endian (most common on Windows) - skip BOM (first 2 bytes)
    html = buffer.slice(2).toString('utf16le');
  } else if (buffer[0] === 0xFE && buffer[1] === 0xFF) {
    // UTF-16 Big Endian - skip BOM (first 2 bytes)
    html = buffer.slice(2).toString('utf16be');
  } else {
    // Assume UTF-8
    html = buffer.toString('utf-8');
  }
  
  const $ = cheerio.load(html);

  const deals = [];

  // Find the Deals table
  const dealsTable = $('th:contains("Deals")').closest('table');
  
  if (dealsTable.length === 0) {
    return deals;
  }

  // Get all rows after the header
  dealsTable.find('tr').each((index, row) => {
    if (index === 0) return; // Skip header row

    const cells = $(row).find('td');
    if (cells.length < 13) return;

    const timeStr = $(cells[0]).text().trim();
    const dealNumber = parseInt($(cells[1]).text().trim());
    const symbol = $(cells[2]).text().trim();
    const type = $(cells[3]).text().trim();
    const direction = $(cells[4]).text().trim();
    const volume = parseFloat($(cells[5]).text().trim().replace(/\s/g, '')) || 0;
    const price = parseFloat($(cells[6]).text().trim().replace(/\s/g, '')) || 0;
    const order = $(cells[7]).text().trim();
    const commission = parseFloat($(cells[8]).text().trim().replace(/\s/g, '')) || 0;
    const swap = parseFloat($(cells[9]).text().trim().replace(/\s/g, '')) || 0;
    const profit = parseFloat($(cells[10]).text().trim().replace(/\s/g, '')) || 0;
    const balance = parseFloat($(cells[11]).text().trim().replace(/\s/g, '')) || 0;
    const comment = $(cells[12]).text().trim();

    // Skip balance entries
    if (type === 'balance') return;

    // Parse date from format "2023.01.01 00:00:00"
    let dateTime = null;
    if (timeStr) {
      const [datePart, timePart] = timeStr.split(' ');
      if (datePart && timePart) {
        const [year, month, day] = datePart.split('.');
        const [hour, minute, second] = timePart.split(':');
        dateTime = new Date(
          parseInt(year),
          parseInt(month) - 1,
          parseInt(day),
          parseInt(hour || 0),
          parseInt(minute || 0),
          parseInt(second || 0)
        );
      }
    }

    if (!dateTime) return;

    deals.push({
      dealNumber,
      time: dateTime.toISOString(),
      symbol,
      type,
      direction,
      volume,
      price,
      order,
      commission,
      swap,
      profit,
      balance,
      comment,
    });
  });

  // Process deals to match in/out prices for trades
  const processedDeals = [];
  const openTrades = new Map(); // Map order number to trade entry

  deals.forEach(deal => {
    if (deal.direction === 'in') {
      // Opening a trade
      openTrades.set(deal.order, {
        ...deal,
        inPrice: deal.price,
      });
    } else if (deal.direction === 'out') {
      // Closing a trade
      const openTrade = openTrades.get(deal.order);
      if (openTrade) {
        processedDeals.push({
          dealNumber: deal.dealNumber,
          time: deal.time,
          symbol: deal.symbol,
          type: deal.type,
          direction: deal.direction,
          volume: deal.volume,
          inPrice: openTrade.inPrice,
          outPrice: deal.price,
          profit: deal.profit,
          commission: deal.commission + (openTrade.commission || 0),
          swap: deal.swap + (openTrade.swap || 0),
          balance: deal.balance,
          comment: deal.comment,
        });
        openTrades.delete(deal.order);
      } else {
        // No matching open trade, use current deal
        processedDeals.push({
          dealNumber: deal.dealNumber,
          time: deal.time,
          symbol: deal.symbol,
          type: deal.type,
          direction: deal.direction,
          volume: deal.volume,
          inPrice: null,
          outPrice: deal.price,
          profit: deal.profit,
          commission: deal.commission,
          swap: deal.swap,
          balance: deal.balance,
          comment: deal.comment,
        });
      }
    }
  });

  return processedDeals;
}

