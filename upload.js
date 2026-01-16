import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';
import { parseHtmlReport } from './parsers/htmlParser.js';
import { parseBalanceReport } from './parsers/csvParser.js';
import { parseDeals } from './parsers/dealsParser.js';
import { uploadReport, getReportId } from './uploaders/reportUploader.js';
import { uploadBalanceData } from './uploaders/balanceUploader.js';
import { uploadDeals } from './uploaders/dealsUploader.js';

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

// Detect EA name from directory name or file content
function detectEAName(dirName, htmlPath = null) {
  const dirNameLower = dirName.toLowerCase();
  
  // Check directory name for EA indicators
  if (dirNameLower.includes('cyberspace') || dirNameLower.includes('cyber')) {
    return 'Cyberspace EA';
  }
  if (dirNameLower.includes('breakout')) {
    return 'Breakout EA by currency pro';
  }
  
  // If HTML path provided, try to detect from file content
  if (htmlPath) {
    try {
      const htmlContent = fs.readFileSync(htmlPath, 'utf-8');
      if (htmlContent.toLowerCase().includes('cyberspace') || htmlContent.toLowerCase().includes('cyber')) {
        return 'Cyberspace EA';
      }
      if (htmlContent.toLowerCase().includes('breakout')) {
        return 'Breakout EA by currency pro';
      }
    } catch (error) {
      // If can't read file, continue with default
    }
  }
  
  // Default to Breakout EA
  return 'Breakout EA by currency pro';
}

async function processDirectory(dirPath) {
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

  // Detect EA name
  const eaName = detectEAName(dirName, htmlPath);
  console.log(`  EA Name: ${eaName}`);

  // Parse HTML report for statistics
  let reportData;
  try {
    reportData = parseHtmlReport(htmlPath);
    reportData.instrument = instrument;
    reportData.strategy = strategy;
    reportData.eaName = eaName; // Add EA name to report data
  } catch (error) {
    console.error(`  Error parsing HTML report: ${error.message}`);
    return;
  }

  // Upload report statistics
  let reportId;
  try {
    reportId = await uploadReport(reportData);
    console.log(`  ✓ Uploaded report statistics (ID: ${reportId})`);
  } catch (error) {
    console.error(`  Error uploading report: ${error.message}`);
    return;
  }

  // Find and parse balance CSV
  const csvFiles = fs.readdirSync(dirPath).filter(f => 
    (f.includes('balance') || f.includes('Balance')) && f.endsWith('.csv')
  );
  
  if (csvFiles.length > 0) {
    const csvPath = path.join(dirPath, csvFiles[0]);
    console.log(`  Parsing balance CSV: ${csvFiles[0]}`);
    
    try {
      const balanceData = parseBalanceReport(csvPath);
      await uploadBalanceData(reportId, instrument, strategy, balanceData);
      console.log(`  ✓ Uploaded ${balanceData.length} balance/equity records`);
    } catch (error) {
      console.error(`  Error uploading balance data: ${error.message}`);
    }
  } else {
    console.log(`  No balance CSV found in ${dirName}`);
  }

  // Parse and upload deals
  try {
    const deals = parseDeals(htmlPath);
    // Filter out deals without in/out prices (only keep closed trades)
    const closedTrades = deals.filter(d => d.inPrice !== null && d.outPrice !== null);
    await uploadDeals(reportId, instrument, strategy, closedTrades);
    console.log(`  ✓ Uploaded ${closedTrades.length} deals`);
  } catch (error) {
    console.error(`  Error uploading deals: ${error.message}`);
  }
}

async function main() {
  const baseDir = __dirname;
  const entries = fs.readdirSync(baseDir, { withFileTypes: true });

  console.log('Starting upload process...\n');

  for (const entry of entries) {
    if (entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'node_modules') {
      const dirPath = path.join(baseDir, entry.name);
      await processDirectory(dirPath);
    }
  }

  console.log('\n✓ Upload process completed!');
  process.exit(0);
}

main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});

