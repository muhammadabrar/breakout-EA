import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';
import { parseHtmlReport } from './parsers/htmlParser.js';
import { parseDeals } from './parsers/dealsParser.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Map directory names to instruments and strategies
function detectInstrumentAndStrategy(dirName) {
  let instrument = null;
  let strategy = null;

  // Detect instrument
  if (dirName.toLowerCase().includes('us30')) {
    instrument = 'us30';
  } else if (dirName.toLowerCase().includes('us100')) {
    instrument = 'us100';
  } else if (dirName.toLowerCase().includes('xau')) {
    instrument = 'xau';
  }

  // Detect strategy
  if (dirName.toLowerCase().includes('daily + london') || dirName.toLowerCase().includes('daily+london')) {
    strategy = 'Daily + London';
  } else if (dirName.toLowerCase().includes('daily only') || dirName.toLowerCase().includes('daily')) {
    strategy = 'Daily';
  }

  return { instrument, strategy };
}

async function processDirectory(dirPath, outputDir) {
  const dirName = path.basename(dirPath);
  const { instrument, strategy } = detectInstrumentAndStrategy(dirName);

  if (!instrument || !strategy) {
    console.log(`Skipping ${dirName}: Could not detect instrument or strategy`);
    return;
  }

  console.log(`\nProcessing: ${dirName}`);
  console.log(`  Instrument: ${instrument}, Strategy: ${strategy}`);

  // Find HTML report
  const htmlFiles = fs.readdirSync(dirPath).filter(f => f.endsWith('.html') && f.includes('report'));
  if (htmlFiles.length === 0) {
    console.log(`  No HTML report found in ${dirName}`);
    return;
  }

  const htmlPath = path.join(dirPath, htmlFiles[0]);
  console.log(`  Parsing HTML report: ${htmlFiles[0]}`);

  // Parse HTML report for statistics
  let reportData;
  try {
    reportData = parseHtmlReport(htmlPath);
    reportData.instrument = instrument;
    reportData.strategy = strategy;
    console.log(`  ✓ Parsed report statistics`);
    console.log(`    Net Profit: ${reportData.netProfit}`);
    console.log(`    Total Trades: ${reportData.totalTrades}`);
    console.log(`    Win Rate: ${reportData.winRate}%`);
  } catch (error) {
    console.error(`  Error parsing HTML report: ${error.message}`);
    console.error(`  Stack: ${error.stack}`);
    return;
  }

  // Parse deals
  let deals;
  try {
    deals = parseDeals(htmlPath);
    console.log(`  ✓ Parsed ${deals.length} deals`);
    
    // Filter out deals without in/out prices (only keep closed trades)
    const closedTrades = deals.filter(d => d.inPrice !== null && d.outPrice !== null);
    console.log(`    Closed trades: ${closedTrades.length}`);
    console.log(`    Deals with inPrice: ${deals.filter(d => d.inPrice !== null).length}`);
    console.log(`    Deals with outPrice: ${deals.filter(d => d.outPrice !== null).length}`);
    
    // Store all deals, not just closed trades
    deals = deals;
  } catch (error) {
    console.error(`  Error parsing deals: ${error.message}`);
    console.error(`  Stack: ${error.stack}`);
    deals = [];
  }

  // Create output directory for this instrument/strategy
  const outputSubDir = path.join(outputDir, `${instrument}_${strategy.replace(/\s+/g, '_')}`);
  await fs.ensureDir(outputSubDir);

  // Save report data to JSON
  const reportFile = path.join(outputSubDir, 'report.json');
  await fs.writeJSON(reportFile, reportData, { spaces: 2 });
  console.log(`  ✓ Saved report to: ${reportFile}`);

  // Save deals to JSON
  const dealsFile = path.join(outputSubDir, 'deals.json');
  await fs.writeJSON(dealsFile, deals, { spaces: 2 });
  console.log(`  ✓ Saved ${deals.length} deals to: ${dealsFile}`);

  // Also save a summary
  const summary = {
    instrument,
    strategy,
    reportDataKeys: Object.keys(reportData),
    reportDataValues: reportData,
    totalDeals: deals.length,
    closedTrades: deals.filter(d => d.inPrice !== null && d.outPrice !== null).length,
    sampleDeal: deals[0] || null,
  };
  const summaryFile = path.join(outputSubDir, 'summary.json');
  await fs.writeJSON(summaryFile, summary, { spaces: 2 });
  console.log(`  ✓ Saved summary to: ${summaryFile}`);
}

async function main() {
  const baseDir = __dirname;
  const outputDir = path.join(baseDir, 'parsed-data');
  
  // Clean and create output directory
  await fs.remove(outputDir);
  await fs.ensureDir(outputDir);

  console.log('Starting parsing process...');
  console.log(`Output directory: ${outputDir}\n`);

  const entries = fs.readdirSync(baseDir, { withFileTypes: true });

  for (const entry of entries) {
    if (entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'node_modules' && entry.name !== 'parsed-data') {
      const dirPath = path.join(baseDir, entry.name);
      await processDirectory(dirPath, outputDir);
    }
  }

  console.log('\n✓ Parsing process completed!');
  console.log(`All parsed data saved to: ${outputDir}`);
  process.exit(0);
}

main().catch(error => {
  console.error('Fatal error:', error);
  console.error('Stack:', error.stack);
  process.exit(1);
});

