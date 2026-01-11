import { getAllReports } from './queries.js';

/**
 * Main entry point - displays summary of all reports
 */
async function main() {
  try {
    console.log('Breakout EA Data Uploader\n');
    console.log('Available commands:');
    console.log('  npm run setup-db  - Set up database schema');
    console.log('  npm run upload    - Upload all reports to database');
    console.log('  npm run queries   - Run example queries\n');

    // Try to get reports if database is set up
    try {
      const reports = await getAllReports();
      if (reports.length > 0) {
        console.log(`Found ${reports.length} report(s) in database:\n`);
        reports.forEach(report => {
          console.log(`  ${report.instrument.toUpperCase()} - ${report.strategy}:`);
          console.log(`    Net Profit: ${report.net_profit || 'N/A'}`);
          console.log(`    Win Rate: ${report.win_rate || 'N/A'}%`);
          console.log(`    Total Trades: ${report.total_trades || 'N/A'}`);
          console.log('');
        });
      } else {
        console.log('No reports found in database. Run "npm run upload" to upload data.\n');
      }
    } catch (error) {
      console.log('Database not connected or not set up. Run "npm run setup-db" first.\n');
    }
  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  } finally {
    process.exit(0);
  }
}

main();

