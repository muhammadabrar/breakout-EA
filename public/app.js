const API_BASE = '/api';

let monthlyChart = null;
let selectedInstruments = ['us30', 'us100', 'xau'];
let selectedStrategies = ['Daily', 'Daily + London'];
let selectedEAs = ['Breakout EA by currency pro', 'Cyberspace EA'];

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
    
    // Get EA types from third filter group
    const eaGroup = document.querySelectorAll('.filter-group')[2];
    selectedEAs = Array.from(eaGroup.querySelectorAll('input[type="checkbox"]:checked'))
        .map(cb => cb.value);
    
    console.log('Filters updated:', { selectedInstruments, selectedStrategies, selectedEAs });
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
        // Fetch reports for all selected EAs
        const allReports = [];
        for (const eaName of selectedEAs) {
            const reports = await fetchAPI('/reports', { eaName });
            allReports.push(...reports);
        }
        
        const filteredReports = allReports.filter(r => 
            selectedInstruments.includes(r.instrument) && 
            selectedStrategies.includes(r.strategy) &&
            selectedEAs.includes(r.ea_name)
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
    tbody.innerHTML = reports.map(r => {
        const shortEAName = r.ea_name && r.ea_name.includes('Breakout') ? 'Breakout' : 
                           (r.ea_name && r.ea_name.includes('Cyberspace') ? 'Cyberspace' : r.ea_name || 'N/A');
        return `
        <tr>
            <td><strong>${r.instrument.toUpperCase()}</strong></td>
            <td>${r.strategy}</td>
            <td>${shortEAName}</td>
            <td class="${parseFloat(r.net_profit) >= 0 ? 'positive' : 'negative'}">
                ${formatCurrency(r.net_profit)}
            </td>
            <td>${formatNumber(r.total_trades)}</td>
            <td>${formatPercent(r.win_rate)}</td>
            <td class="negative">${formatCurrency(r.balance_drawdown_maximal)}</td>
        </tr>
    `;
    }).join('');
}

async function loadMonthlyReport() {
    showLoading();
    try {
        // Fetch monthly data for each EA separately
        const eaDataMap = {};
        
        for (const eaName of selectedEAs) {
            const monthlyDataPromises = selectedInstruments.flatMap(instrument =>
                selectedStrategies.map(strategy =>
                    fetchAPI('/monthly-pnl', { instrument, strategy, eaName }).then(data =>
                        data.map(item => ({ ...item, month: new Date(item.month).toISOString() }))
                    )
                )
            );
            
            const allMonthlyData = (await Promise.all(monthlyDataPromises)).flat();
            
            // Group by month and sum all instruments/strategies for this EA
            const grouped = allMonthlyData.reduce((acc, item) => {
                const monthKey = item.month;
                if (!acc[monthKey]) {
                    acc[monthKey] = {
                        month: item.month,
                        monthFormatted: formatDate(item.month),
                        totalPnL: 0,
                        totalTrades: 0,
                        winningTrades: 0,
                        losingTrades: 0,
                        instruments: {}
                    };
                }
                acc[monthKey].totalPnL += parseFloat(item.monthly_pnl || 0);
                acc[monthKey].totalTrades += parseInt(item.trade_count || 0);
                acc[monthKey].winningTrades += parseInt(item.winning_trades || 0);
                acc[monthKey].losingTrades += parseInt(item.losing_trades || 0);
                
                if (!acc[monthKey].instruments[item.instrument]) {
                    acc[monthKey].instruments[item.instrument] = 0;
                }
                acc[monthKey].instruments[item.instrument] += parseFloat(item.monthly_pnl || 0);
                
                return acc;
            }, {});
            
            eaDataMap[eaName] = Object.values(grouped).sort((a, b) => 
                new Date(b.month) - new Date(a.month)
            );
        }
        
        displayMonthlyReport(eaDataMap);
    } catch (error) {
        console.error('Error loading monthly report:', error);
        alert('Error loading monthly report: ' + error.message);
    } finally {
        hideLoading();
    }
}

function displayMonthlyReport(eaDataMap) {
    // Get all unique months across all EAs
    const allMonths = new Set();
    Object.values(eaDataMap).forEach(eaData => {
        eaData.forEach(item => allMonths.add(item.month));
    });
    
    const sortedMonths = Array.from(allMonths).sort((a, b) => new Date(b) - new Date(a));
    
    // Combine data from all EAs by month
    const combinedMonthlyData = sortedMonths.map(month => {
        const monthData = {
            month,
            monthFormatted: formatDate(month),
            eas: {}
        };
        
        // Get data for each EA for this month
        Object.entries(eaDataMap).forEach(([eaName, eaData]) => {
            const monthItem = eaData.find(item => item.month === month);
            if (monthItem) {
                monthData.eas[eaName] = monthItem;
            }
        });
        
        return monthData;
    });
    
    // Calculate statistics from all EA data combined
    const allEAData = Object.values(eaDataMap).flat();
    const profitableMonths = allEAData.filter(item => item.totalPnL > 0);
    const losingMonths = allEAData.filter(item => item.totalPnL < 0);
    
    const avgProfit = profitableMonths.length > 0
        ? profitableMonths.reduce((sum, item) => sum + item.totalPnL, 0) / profitableMonths.length
        : 0;
    
    const avgLoss = losingMonths.length > 0
        ? losingMonths.reduce((sum, item) => sum + item.totalPnL, 0) / losingMonths.length
        : 0;
    
    const maxProfit = allEAData.length > 0
        ? Math.max(...allEAData.map(item => item.totalPnL))
        : 0;
    
    const maxLoss = allEAData.length > 0
        ? Math.min(...allEAData.map(item => item.totalPnL))
        : 0;
    
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
            <p class="stat-subtitle">${losingMonths.length} losing months</p>
        </div>
        <div class="stat-card">
            <h3>Max Profit (Single Month)</h3>
            <p class="stat-value positive">${formatCurrency(maxProfit)}</p>
        </div>
        <div class="stat-card">
            <h3>Max Loss (Single Month)</h3>
            <p class="stat-value negative">${formatCurrency(maxLoss)}</p>
        </div>
    `;
    
    // Update calendar grid - show both EAs side by side
    const calendarGrid = document.getElementById('calendarGrid');
    calendarGrid.innerHTML = combinedMonthlyData.map(monthData => {
        const date = new Date(monthData.month);
        const monthName = date.toLocaleDateString('en-US', { month: 'short' });
        const year = date.getFullYear();
        
        // Build EA comparison cards
        const eaCards = Object.entries(monthData.eas).map(([eaName, eaItem]) => {
            const shortEAName = eaName.includes('Breakout') ? 'Breakout' : 'Cyberspace';
            const winRate = eaItem.totalTrades > 0 ? (eaItem.winningTrades / eaItem.totalTrades * 100).toFixed(1) : 0;
            
            // Build instrument breakdown for this EA
            const instrumentBreakdown = selectedInstruments
                .filter(inst => eaItem.instruments[inst] !== undefined)
                .map(inst => {
                    const pnl = eaItem.instruments[inst];
                    return `
                        <div class="calendar-instrument">
                            <span class="instrument-label">${inst.toUpperCase()}:</span>
                            <span class="${pnl >= 0 ? 'positive' : 'negative'}">${formatCurrency(pnl)}</span>
                        </div>
                    `;
                }).join('');
            
            return `
                <div class="calendar-ea-card ${eaItem.totalPnL >= 0 ? 'profit' : 'loss'}">
                    <div class="calendar-ea-name">${shortEAName} EA</div>
                    <div class="calendar-pnl ${eaItem.totalPnL >= 0 ? 'positive' : 'negative'}">
                        ${formatCurrency(eaItem.totalPnL)}
                    </div>
                    <div class="calendar-instruments">
                        ${instrumentBreakdown}
                    </div>
                    <div class="calendar-stats">
                        <div>Win Rate: ${winRate}%</div>
                        <div>Trades: ${formatNumber(eaItem.totalTrades)}</div>
                    </div>
                </div>
            `;
        }).join('');
        
        return `
            <div class="calendar-month-wrapper">
                <div class="calendar-month-header">
                    <div class="calendar-month">${monthName}</div>
                    <div class="calendar-year">${year}</div>
                </div>
                <div class="calendar-eas-container">
                    ${eaCards}
                </div>
            </div>
        `;
    }).join('');
    
    // Update chart with combined totals
    const labels = combinedMonthlyData.map(item => item.monthFormatted).reverse();
    const totalPnLData = combinedMonthlyData.map(item => {
        return Object.values(item.eas).reduce((sum, eaItem) => sum + eaItem.totalPnL, 0);
    }).reverse();
    
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
            strategies: selectedStrategies.join(','),
            eaNames: selectedEAs.join(',')
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
    tbody.innerHTML = stats.map(item => {
        const shortEAName = item.ea_name && item.ea_name.includes('Breakout') ? 'Breakout' : 
                           (item.ea_name && item.ea_name.includes('Cyberspace') ? 'Cyberspace' : item.ea_name || 'N/A');
        return `
        <tr>
            <td><strong>${item.instrument.toUpperCase()}</strong></td>
            <td>${item.strategy}</td>
            <td>${shortEAName}</td>
            <td class="${parseFloat(item.total_net_profit) >= 0 ? 'positive' : 'negative'}">
                ${formatCurrency(item.total_net_profit)}
            </td>
            <td>${formatNumber(item.total_trades)}</td>
            <td>${formatPercent(item.combined_win_rate)}</td>
            <td class="negative">${formatCurrency(item.max_drawdown)}</td>
        </tr>
    `;
    }).join('');
}

function showLoading() {
    document.getElementById('loading').style.display = 'block';
}

function hideLoading() {
    document.getElementById('loading').style.display = 'none';
}

// Initialize
loadOverview();

