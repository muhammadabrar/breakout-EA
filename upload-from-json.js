import fs from 'fs-extra';
import path from 'path';
import { fileURLToPath } from 'url';
import { uploadReport } from './uploaders/reportUploader.js';
import { uploadDeals } from './uploaders/dealsUploader.js';
import { uploadBalanceData } from './uploaders/balanceUploader.js';
import { parseBalanceReport } from './parsers/csvParser.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function uploadFromJson(jsonDir) {
  console.log('Starting upload from JSON files...\n');
  console.log(`Reading from: ${jsonDir}\n`);

  // Get all subdirectories in parsed-data
  const entries = fs.readdirSync(jsonDir, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const subDir = path.join(jsonDir, entry.name);
    const reportFile = path.join(subDir, 'report.json');
    const dealsFile = path.join(subDir, 'deals.json');

    // Check if files exist
    if (!fs.existsSync(reportFile)) {
      console.log(`Skipping ${entry.name}: report.json not found`);
      continue;
    }

    console.log(`\nProcessing: ${entry.name}`);

    try {
      // Read and upload report
      const reportData = await fs.readJSON(reportFile);
      
      // Always set EA name to Cyberspace EA for reports uploaded from cyberspace EA directory
      reportData.eaName = 'Cyberspace EA';
      
      console.log(`  Reading report.json...`);
      console.log(`    Instrument: ${reportData.instrument}, Strategy: ${reportData.strategy}`);
      console.log(`    EA Name: ${reportData.eaName}`);
      console.log(`    Net Profit: ${reportData.netProfit}, Total Trades: ${reportData.totalTrades}`);

      const reportId = await uploadReport(reportData);
      console.log(`  ✓ Uploaded report statistics (ID: ${reportId})`);

      // Try to upload balance data from CSV if it exists
      // Find the original directory to get the CSV file
      const instrument = reportData.instrument;
      const strategy = reportData.strategy;
      
      // Map strategy names back to directory format
      let strategyDirPart;
      if (strategy === 'Daily') {
        strategyDirPart = 'daily only';
      } else if (strategy === 'Daily + London') {
        strategyDirPart = 'daily + london';
      } else {
        strategyDirPart = strategy.toLowerCase().replace(/\s+/g, ' ');
      }
      
      const strategyDirName = `${instrument} - ${strategyDirPart}`;
      const originalDir = path.join(__dirname, 'cyberspace EA', strategyDirName);

      if (fs.existsSync(originalDir)) {
        const csvFiles = fs.readdirSync(originalDir).filter(f => 
          (f.includes('balance') || f.includes('Balance')) && f.endsWith('.csv')
        );

        if (csvFiles.length > 0) {
          const csvPath = path.join(originalDir, csvFiles[0]);
          console.log(`  Parsing balance CSV: ${csvFiles[0]}`);
          
          try {
            const balanceData = parseBalanceReport(csvPath);
            await uploadBalanceData(reportId, instrument, strategy, balanceData);
            console.log(`  ✓ Uploaded ${balanceData.length} balance/equity records`);
          } catch (error) {
            console.error(`  Error uploading balance data: ${error.message}`);
          }
        } else {
          console.log(`  No balance CSV found in ${strategyDirName}`);
        }
      } else {
        console.log(`  Original directory not found: ${strategyDirName}`);
      }

      // Upload deals if file exists
      if (fs.existsSync(dealsFile)) {
        const deals = await fs.readJSON(dealsFile);
        console.log(`  Reading deals.json... (${deals.length} deals)`);
        
        // Filter out deals without in/out prices (only keep closed trades)
        const closedTrades = deals.filter(d => d.inPrice !== null && d.outPrice !== null);
        console.log(`    Closed trades: ${closedTrades.length}`);
        console.log(`    Deals with inPrice: ${deals.filter(d => d.inPrice !== null).length}`);
        console.log(`    Deals with outPrice: ${deals.filter(d => d.outPrice !== null).length}`);
        
        // For now, upload all deals (even if they don't have inPrice/outPrice matched)
        // The dealsUploader expects certain fields, let's upload what we have
        await uploadDeals(reportId, instrument, strategy, deals);
        console.log(`  ✓ Uploaded ${deals.length} deals`);
      } else {
        console.log(`  No deals.json found`);
      }

    } catch (error) {
      console.error(`  Error processing ${entry.name}: ${error.message}`);
      console.error(`  Stack: ${error.stack}`);
    }
  }

  console.log('\n✓ Upload process completed!');
}

async function main() {
  const jsonDir = path.join(__dirname, 'cyberspace EA', 'parsed-data');
  
  if (!fs.existsSync(jsonDir)) {
    console.error(`Error: Directory ${jsonDir} does not exist.`);
    console.error('Please run parse-to-json.js first to generate the JSON files.');
    process.exit(1);
  }

  try {
    await uploadFromJson(jsonDir);
    process.exit(0);
  } catch (error) {
    console.error('Fatal error:', error);
    console.error('Stack:', error.stack);
    process.exit(1);
  }
}

main();

