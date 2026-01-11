const API_BASE = '/api';

let monthlyChart = null;
let selectedInstruments = ['us30', 'us100', 'xau'];
let selectedStrategies = ['Daily', 'Daily + London'];

// Tab switching
document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
        
        btn.classList.add('active');
        document.getElementById(btn.dataset.tab).classList.add('active');
        
        // Update filters when switching tabs
        updateSelectedFilters();
        
        if (btn.dataset.tab === 'monthly') {
            loadMonthlyReport();
        } else if (btn.dataset.tab === 'stats') {
            loadCombinedStats();
        } else if (btn.dataset.tab === 'overview') {
            loadOverview();
        }
    });
});

// Filter checkboxes
document.querySelectorAll('.filter-group input[type="checkbox"]').forEach(cb => {
    cb.addEventListener('change', () => {
        updateSelectedFilters();
    });
});

document.getElementById('applyFilters').addEventListener('click', () => {
    updateSelectedFilters();
    loadOverview();
    // Only load other tabs if they're currently active
    const activeTab = document.querySelector('.tab-btn.active').dataset.tab;
    if (activeTab === 'monthly') {
        loadMonthlyReport();
    } else if (activeTab === 'stats') {
        loadCombinedStats();
    }
});

function updateSelectedFilters() {
    // Get instruments from first filter group
    const instrumentGroup = document.querySelectorAll('.filter-group')[0];
    selectedInstruments = Array.from(instrumentGroup.querySelectorAll('input[type="checkbox"]:checked'))
        .map(cb => cb.value);
    
    // Get strategies from second filter group
    const strategyGroup = document.querySelectorAll('.filter-group')[1];
    selectedStrategies = Array.from(strategyGroup.querySelectorAll('input[type="checkbox"]:checked'))
        .map(cb => cb.value);
    
    console.log('Filters updated:', { selectedInstruments, selectedStrategies });
}

async function fetchAPI(endpoint, params = {}) {
    const queryString = new URLSearchParams(params).toString();
    const url = `${API_BASE}${endpoint}${queryString ? '?' + queryString : ''}`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
    return await response.json();
}

function formatCurrency(value) {
    if (value === null || value === undefined) return '$0.00';
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    }).format(value);
}

function formatNumber(value) {
    if (value === null || value === undefined) return '0';
    return new Intl.NumberFormat('en-US').format(value);
}

function formatPercent(value) {
    if (value === null || value === undefined) return '0%';
    return `${parseFloat(value).toFixed(2)}%`;
}

function formatDate(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-US', { year: 'numeric', month: 'short' });
}

async function loadOverview() {
    showLoading();
    try {
        const reports = await fetchAPI('/reports');
        const filteredReports = reports.filter(r => 
            selectedInstruments.includes(r.instrument) && 
            selectedStrategies.includes(r.strategy)
        );
        
        displayOverview(filteredReports);
    } catch (error) {
        console.error('Error loading overview:', error);
        alert('Error loading overview: ' + error.message);
    } finally {
        hideLoading();
    }
}

function displayOverview(reports) {
    // Calculate totals
    const totalProfit = reports.reduce((sum, r) => sum + (parseFloat(r.net_profit) || 0), 0);
    const totalTrades = reports.reduce((sum, r) => sum + (parseInt(r.total_trades) || 0), 0);
    const totalProfitable = reports.reduce((sum, r) => sum + (parseInt(r.profitable_trades) || 0), 0);
    const winRate = totalTrades > 0 ? (totalProfitable / totalTrades * 100) : 0;
    const maxDrawdown = Math.max(...reports.map(r => parseFloat(r.balance_drawdown_maximal) || 0));
    
    document.getElementById('totalProfit').textContent = formatCurrency(totalProfit);
    document.getElementById('totalTrades').textContent = formatNumber(totalTrades);
    document.getElementById('winRate').textContent = formatPercent(winRate);
    document.getElementById('maxDrawdown').textContent = formatCurrency(maxDrawdown);
    
    // Display table
    const tbody = document.getElementById('reportsBody');
    tbody.innerHTML = reports.map(r => `
        <tr>
            <td><strong>${r.instrument.toUpperCase()}</strong></td>
            <td>${r.strategy}</td>
            <td class="${parseFloat(r.net_profit) >= 0 ? 'positive' : 'negative'}">
                ${formatCurrency(r.net_profit)}
            </td>
            <td>${formatNumber(r.total_trades)}</td>
            <td>${formatPercent(r.win_rate)}</td>
            <td class="negative">${formatCurrency(r.balance_drawdown_maximal)}</td>
        </tr>
    `).join('');
}

async function loadMonthlyReport() {
    showLoading();
    try {
        // Fetch monthly data for all selected combinations
        const monthlyDataPromises = selectedInstruments.flatMap(instrument =>
            selectedStrategies.map(strategy =>
                fetchAPI('/monthly-pnl', { instrument, strategy }).then(data =>
                    data.map(item => ({ ...item, month: new Date(item.month).toISOString() }))
                )
            )
        );
        
        const allMonthlyData = (await Promise.all(monthlyDataPromises)).flat();
        
        // Group by month and instrument/strategy
        const grouped = allMonthlyData.reduce((acc, item) => {
            const key = `${item.month}_${item.instrument}_${item.strategy}`;
            if (!acc[key]) {
                acc[key] = item;
            } else {
                acc[key].monthly_pnl = (parseFloat(acc[key].monthly_pnl) || 0) + (parseFloat(item.monthly_pnl) || 0);
                acc[key].trade_count = (parseInt(acc[key].trade_count) || 0) + (parseInt(item.trade_count) || 0);
                acc[key].winning_trades = (parseInt(acc[key].winning_trades) || 0) + (parseInt(item.winning_trades) || 0);
                acc[key].losing_trades = (parseInt(acc[key].losing_trades) || 0) + (parseInt(item.losing_trades) || 0);
            }
            return acc;
        }, {});
        
        const monthlyArray = Object.values(grouped).sort((a, b) => 
            new Date(b.month) - new Date(a.month)
        );
        
        displayMonthlyReport(monthlyArray);
    } catch (error) {
        console.error('Error loading monthly report:', error);
        alert('Error loading monthly report: ' + error.message);
    } finally {
        hideLoading();
    }
}

function displayMonthlyReport(data) {
    // Group by month and sum all instruments/strategies first
    const monthlyTotals = data.reduce((acc, item) => {
        const monthKey = formatDate(item.month);
        if (!acc[monthKey]) {
            acc[monthKey] = {
                month: item.month,
                monthFormatted: monthKey,
                totalPnL: 0,
                totalTrades: 0,
                winningTrades: 0,
                losingTrades: 0,
                instruments: {} // Track per-instrument totals
            };
        }
        acc[monthKey].totalPnL += parseFloat(item.monthly_pnl || 0);
        acc[monthKey].totalTrades += parseInt(item.trade_count || 0);
        acc[monthKey].winningTrades += parseInt(item.winning_trades || 0);
        acc[monthKey].losingTrades += parseInt(item.losing_trades || 0);
        
        // Track per-instrument totals
        if (!acc[monthKey].instruments[item.instrument]) {
            acc[monthKey].instruments[item.instrument] = 0;
        }
        acc[monthKey].instruments[item.instrument] += parseFloat(item.monthly_pnl || 0);
        
        return acc;
    }, {});
    
    const monthlyArray = Object.values(monthlyTotals).sort((a, b) => 
        new Date(b.month) - new Date(a.month)
    );
    
    // Calculate statistics from combined totals
    const profitableMonths = monthlyArray.filter(item => item.totalPnL > 0);
    const losingMonths = monthlyArray.filter(item => item.totalPnL < 0);
    
    const avgProfit = profitableMonths.length > 0
        ? profitableMonths.reduce((sum, item) => sum + item.totalPnL, 0) / profitableMonths.length
        : 0;
    
    const avgLoss = losingMonths.length > 0
        ? losingMonths.reduce((sum, item) => sum + item.totalPnL, 0) / losingMonths.length
        : 0;
    
    const lossMonthCount = losingMonths.length;
    
    const maxProfit = monthlyArray.length > 0
        ? Math.max(...monthlyArray.map(item => item.totalPnL))
        : 0;
    
    const maxLoss = monthlyArray.length > 0
        ? Math.min(...monthlyArray.map(item => item.totalPnL))
        : 0;
    
    const maxProfitMonth = monthlyArray.find(item => item.totalPnL === maxProfit);
    const maxLossMonth = monthlyArray.find(item => item.totalPnL === maxLoss);
    
    // Display statistics
    const statsContainer = document.getElementById('monthlyStats');
    statsContainer.innerHTML = `
        <div class="stat-card">
            <h3>Average Profit per Month</h3>
            <p class="stat-value positive">${formatCurrency(avgProfit)}</p>
            <p class="stat-subtitle">${profitableMonths.length} profitable months</p>
        </div>
        <div class="stat-card">
            <h3>Average Loss per Month</h3>
            <p class="stat-value negative">${formatCurrency(avgLoss)}</p>
            <p class="stat-subtitle">${lossMonthCount} losing months</p>
        </div>
        <div class="stat-card">
            <h3>Max Profit (Single Month)</h3>
            <p class="stat-value positive">${formatCurrency(maxProfit)}</p>
            <p class="stat-subtitle">${maxProfitMonth ? maxProfitMonth.monthFormatted : 'N/A'}</p>
        </div>
        <div class="stat-card">
            <h3>Max Loss (Single Month)</h3>
            <p class="stat-value negative">${formatCurrency(maxLoss)}</p>
            <p class="stat-subtitle">${maxLossMonth ? maxLossMonth.monthFormatted : 'N/A'}</p>
        </div>
    `;
    
    // Calculate worst months by instrument
    const worstMonthsByInstrument = selectedInstruments.map(instrument => {
        const instrumentData = data.filter(item => item.instrument === instrument);
        if (instrumentData.length === 0) return null;
        
        const worstMonth = instrumentData.reduce((worst, current) => {
            const currentPnL = parseFloat(current.monthly_pnl || 0);
            const worstPnL = parseFloat(worst.monthly_pnl || 0);
            return currentPnL < worstPnL ? current : worst;
        });
        
        return worstMonth;
    }).filter(item => item !== null && parseFloat(item.monthly_pnl) < 0);
    
    // Display worst months table
    if (worstMonthsByInstrument.length > 0) {
        const worstMonthsBody = document.getElementById('worstMonthsBody');
        worstMonthsBody.innerHTML = worstMonthsByInstrument
            .sort((a, b) => parseFloat(a.monthly_pnl) - parseFloat(b.monthly_pnl))
            .map(item => `
                <tr>
                    <td><strong>${item.instrument.toUpperCase()}</strong></td>
                    <td>${formatDate(item.month)}</td>
                    <td>${item.strategy}</td>
                    <td class="negative">${formatCurrency(item.monthly_pnl)}</td>
                    <td>${formatNumber(item.trade_count)}</td>
                </tr>
            `).join('');
        
        document.getElementById('worstMonthsContainer').style.display = 'block';
    } else {
        document.getElementById('worstMonthsContainer').style.display = 'none';
    }
    
    // Update table with combined totals (monthlyArray already calculated above)
    const tbody = document.getElementById('monthlyBody');
    tbody.innerHTML = monthlyArray.map(item => {
        const winRate = item.totalTrades > 0 ? (item.winningTrades / item.totalTrades * 100) : 0;
        return `
            <tr>
                <td><strong>${item.monthFormatted}</strong></td>
                <td class="${item.totalPnL >= 0 ? 'positive' : 'negative'}">
                    <strong>${formatCurrency(item.totalPnL)}</strong>
                </td>
                <td>${formatNumber(item.totalTrades)}</td>
                <td class="positive">${formatNumber(item.winningTrades)}</td>
                <td class="negative">${formatNumber(item.losingTrades)}</td>
                <td>${formatPercent(winRate)}</td>
            </tr>
        `;
    }).join('');
    
    // Update calendar grid
    const calendarGrid = document.getElementById('calendarGrid');
    calendarGrid.innerHTML = monthlyArray.map(item => {
        const date = new Date(item.month);
        const monthName = date.toLocaleDateString('en-US', { month: 'short' });
        const year = date.getFullYear();
        const winRate = item.totalTrades > 0 ? (item.winningTrades / item.totalTrades * 100).toFixed(1) : 0;
        
        // Build instrument breakdown
        const instrumentBreakdown = selectedInstruments
            .filter(inst => item.instruments[inst] !== undefined)
            .map(inst => {
                const pnl = item.instruments[inst];
                return `
                    <div class="calendar-instrument">
                        <span class="instrument-label">${inst.toUpperCase()}:</span>
                        <span class="${pnl >= 0 ? 'positive' : 'negative'}">${formatCurrency(pnl)}</span>
                    </div>
                `;
            }).join('');
        
        return `
            <div class="calendar-item ${item.totalPnL >= 0 ? 'profit' : 'loss'}">
                <div class="calendar-month">${monthName}</div>
                <div class="calendar-year">${year}</div>
                <div class="calendar-pnl ${item.totalPnL >= 0 ? 'positive' : 'negative'}">
                    ${formatCurrency(item.totalPnL)}
                </div>
                <div class="calendar-instruments">
                    ${instrumentBreakdown}
                </div>
                <div class="calendar-stats">
                    <div>Trades: ${formatNumber(item.totalTrades)}</div>
                    <div>Win Rate: ${formatPercent(winRate)}</div>
                    <div>Wins: <span class="positive">${formatNumber(item.winningTrades)}</span></div>
                    <div>Losses: <span class="negative">${formatNumber(item.losingTrades)}</span></div>
                </div>
            </div>
        `;
    }).join('');
    
    // Update chart with combined totals
    const labels = monthlyArray.map(item => item.monthFormatted).reverse();
    const totalPnLData = monthlyArray.map(item => item.totalPnL).reverse();
    
    const datasets = [{
        label: 'Total P&L (All Instruments)',
        data: totalPnLData,
        borderColor: 'rgb(102, 126, 234)',
        backgroundColor: 'rgba(102, 126, 234, 0.2)',
        tension: 0.4,
        fill: true
    }];
    
    const ctx = document.getElementById('monthlyChart').getContext('2d');
    
    if (monthlyChart) {
        monthlyChart.destroy();
    }
    
    monthlyChart = new Chart(ctx, {
        type: 'line',
        data: { labels, datasets },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                },
                title: {
                    display: true,
                    text: 'Monthly P&L by Instrument'
                }
            },
            scales: {
                y: {
                    beginAtZero: false,
                    ticks: {
                        callback: function(value) {
                            return formatCurrency(value);
                        }
                    }
                }
            }
        }
    });
}

async function loadCombinedStats() {
    showLoading();
    try {
        const stats = await fetchAPI('/combined-stats', {
            instruments: selectedInstruments.join(','),
            strategies: selectedStrategies.join(',')
        });
        
        displayCombinedStats(stats);
    } catch (error) {
        console.error('Error loading combined stats:', error);
        alert('Error loading combined stats: ' + error.message);
    } finally {
        hideLoading();
    }
}

function displayCombinedStats(stats) {
    const tbody = document.getElementById('statsBody');
    tbody.innerHTML = stats.map(item => `
        <tr>
            <td><strong>${item.instrument.toUpperCase()}</strong></td>
            <td>${item.strategy}</td>
            <td class="${parseFloat(item.total_net_profit) >= 0 ? 'positive' : 'negative'}">
                ${formatCurrency(item.total_net_profit)}
            </td>
            <td>${formatNumber(item.total_trades)}</td>
            <td>${formatPercent(item.combined_win_rate)}</td>
            <td class="negative">${formatCurrency(item.max_drawdown)}</td>
        </tr>
    `).join('');
}

function showLoading() {
    document.getElementById('loading').style.display = 'block';
}

function hideLoading() {
    document.getElementById('loading').style.display = 'none';
}

// Initialize
loadOverview();

