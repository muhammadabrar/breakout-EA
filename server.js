import express from 'express';
import cors from 'cors';
import { getAllReports } from './queries.js';
import { getMonthlyPnL } from './queries.js';
import { getCombinedStats } from './queries.js';
import { getMaxDrawdown } from './queries.js';
import { getWinRate } from './queries.js';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// API Routes
app.get('/api/reports', async (req, res) => {
  try {
    const { eaName } = req.query;
    const reports = await getAllReports(eaName || null);
    res.json(reports);
  } catch (error) {
    console.error('Error fetching reports:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/monthly-pnl', async (req, res) => {
  try {
    const { instrument, strategy, eaName } = req.query;
    const monthlyPnL = await getMonthlyPnL(
      instrument || null,
      strategy || null,
      eaName || null
    );
    res.json(monthlyPnL);
  } catch (error) {
    console.error('Error fetching monthly PnL:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/combined-stats', async (req, res) => {
  try {
    const { instruments, strategies, eaNames } = req.query;
    const instrumentsArray = instruments ? instruments.split(',') : [];
    const strategiesArray = strategies ? strategies.split(',') : [];
    const eaNamesArray = eaNames ? eaNames.split(',') : [];
    
    const stats = await getCombinedStats(instrumentsArray, strategiesArray, eaNamesArray);
    res.json(stats);
  } catch (error) {
    console.error('Error fetching combined stats:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/drawdown', async (req, res) => {
  try {
    const { instrument, strategy } = req.query;
    const drawdown = await getMaxDrawdown(
      instrument || null,
      strategy || null
    );
    res.json(drawdown);
  } catch (error) {
    console.error('Error fetching drawdown:', error);
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/win-rate', async (req, res) => {
  try {
    const { instrument, strategy } = req.query;
    const winRate = await getWinRate(
      instrument || null,
      strategy || null
    );
    res.json(winRate);
  } catch (error) {
    console.error('Error fetching win rate:', error);
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});

