import { 
  getMaxDrawdown, 
  getWinRate, 
  getMonthlyPnL, 
  getCombinedStats,
  getAllReports 
} from './queries.js';

/**
 * Example script showing how to use the query functions
 */
async function runExamples() {
  console.log('=== Example Queries ===\n');

  // Get all reports
  console.log('1. All Reports:');
  const allReports = await getAllReports();
  console.log(allReports);
  console.log('\n');

  // Get max drawdown for all instruments
  console.log('2. Max Drawdown (All Instruments):');
  const maxDrawdowns = await getMaxDrawdown();
  console.log(maxDrawdowns);
  console.log('\n');

  // Get max drawdown for US30
  console.log('3. Max Drawdown (US30 only):');
  const us30Drawdown = await getMaxDrawdown('us30');
  console.log(us30Drawdown);
  console.log('\n');

  // Get win rates
  console.log('4. Win Rates (All):');
  const winRates = await getWinRate();
  console.log(winRates);
  console.log('\n');

  // Get monthly PnL
  console.log('5. Monthly PnL (All):');
  const monthlyPnL = await getMonthlyPnL();
  console.log(monthlyPnL);
  console.log('\n');

  // Get monthly PnL for US30
  console.log('6. Monthly PnL (US30 only):');
  const us30MonthlyPnL = await getMonthlyPnL('us30');
  console.log(us30MonthlyPnL);
  console.log('\n');

  // Get combined statistics
  console.log('7. Combined Stats (All Instruments):');
  const combinedStats = await getCombinedStats(['us30', 'us100', 'xau'], ['Daily', 'Daily + London']);
  console.log(combinedStats);
  console.log('\n');

  // Get combined statistics for specific instruments
  console.log('8. Combined Stats (US30 and US100, Daily only):');
  const specificStats = await getCombinedStats(['us30', 'us100'], ['Daily']);
  console.log(specificStats);
  console.log('\n');
}

runExamples().catch(console.error);

