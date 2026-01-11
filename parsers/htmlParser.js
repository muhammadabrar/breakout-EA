import fs from 'fs-extra';
import * as cheerio from 'cheerio';

export function parseHtmlReport(htmlPath) {
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

  const data = {};

  // Extract instrument from Symbol field
  const symbolText = $('td:contains("Symbol:")').next().text().trim();
  const instrumentMatch = symbolText.match(/(US30|US100|XAU)/i);
  if (instrumentMatch) {
    data.instrument = instrumentMatch[1].toLowerCase();
    if (data.instrument === 'us30') data.instrument = 'us30';
    else if (data.instrument === 'us100') data.instrument = 'us100';
    else if (data.instrument === 'xau') data.instrument = 'xau';
  }

  // Helper function to extract numeric value from table cells
  function extractValue(label, isPercentage = false) {
    const cell = $('td:contains("' + label + '")').next();
    let text = cell.text().trim();
    
    if (isPercentage) {
      // Extract percentage value (e.g., "4.17%" or "4.89% (2 904.80)")
      const match = text.match(/([\d.]+)%/);
      return match ? parseFloat(match[1]) : null;
    } else {
      // Remove spaces and parse number
      text = text.replace(/\s/g, '');
      const match = text.match(/-?[\d.]+/);
      return match ? parseFloat(match[0]) : null;
    }
  }

  // Extract main statistics
  data.netProfit = extractValue('Total Net Profit:');
  data.balanceDrawdownAbsolute = extractValue('Balance Drawdown Absolute:');
  data.equityDrawdownAbsolute = extractValue('Equity Drawdown Absolute:');
  data.balanceDrawdownMaximal = extractValue('Balance Drawdown Maximal:');
  data.equityDrawdownMaximal = extractValue('Equity Drawdown Maximal:');
  data.balanceDrawdownRelative = extractValue('Balance Drawdown Relative:', true);
  data.equityDrawdownRelative = extractValue('Equity Drawdown Relative:', true);

  // Extract trade statistics
  data.totalTrades = extractValue('Total Trades:');
  
  // Extract profitable trades count and win rate
  const profitTradesText = $('td:contains("Profit Trades (% of total):")').next().text().trim();
  const profitMatch = profitTradesText.match(/(\d+)\s*\(/);
  data.profitableTrades = profitMatch ? parseInt(profitMatch[1]) : null;
  const profitPctMatch = profitTradesText.match(/([\d.]+)%/);
  data.winRate = profitPctMatch ? parseFloat(profitPctMatch[1]) : null;

  const lossTradesText = $('td:contains("Loss Trades (% of total):")').next().text().trim();
  const lossMatch = lossTradesText.match(/([\d.]+)%/);
  data.lossRate = lossMatch ? parseFloat(lossMatch[1]) : null;

  // Extract consecutive wins/losses
  const maxConsecutiveWinsText = $('td:contains("Maximum consecutive wins ($):")').next().text().trim();
  const maxConsecutiveWinsMatch = maxConsecutiveWinsText.match(/(\d+)/);
  data.maxConsecutiveWins = maxConsecutiveWinsMatch ? parseInt(maxConsecutiveWinsMatch[1]) : null;

  const maxConsecutiveLossesText = $('td:contains("Maximum consecutive losses ($):")').next().text().trim();
  const maxConsecutiveLossesMatch = maxConsecutiveLossesText.match(/(\d+)/);
  data.maxConsecutiveLosses = maxConsecutiveLossesMatch ? parseInt(maxConsecutiveLossesMatch[1]) : null;

  const avgConsecutiveWinsText = $('td:contains("Average consecutive wins:")').next().text().trim();
  data.consecutiveWins = avgConsecutiveWinsText ? parseFloat(avgConsecutiveWinsText) : null;

  const avgConsecutiveLossesText = $('td:contains("Average consecutive losses:")').next().text().trim();
  data.consecutiveLosses = avgConsecutiveLossesText ? parseFloat(avgConsecutiveLossesText) : null;

  return data;
}

