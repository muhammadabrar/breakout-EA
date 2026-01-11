import fs from 'fs-extra';
import { parse } from 'csv-parse/sync';

export function parseBalanceReport(csvPath) {
  // Read file as buffer to detect encoding
  const buffer = fs.readFileSync(csvPath);
  
  // Check for UTF-16 BOM (FE FF for BE, FF FE for LE)
  let csvContent;
  if (buffer[0] === 0xFF && buffer[1] === 0xFE) {
    // UTF-16 Little Endian (most common on Windows) - skip BOM (first 2 bytes)
    csvContent = buffer.slice(2).toString('utf16le');
  } else if (buffer[0] === 0xFE && buffer[1] === 0xFF) {
    // UTF-16 Big Endian - skip BOM (first 2 bytes)
    csvContent = buffer.slice(2).toString('utf16be');
  } else {
    // Assume UTF-8
    csvContent = buffer.toString('utf-8');
  }
  
  const records = parse(csvContent, {
    columns: true,
    skip_empty_lines: true,
    delimiter: '\t',
    trim: true,
    relax_column_count: true, // Allow rows with different column counts
    skip_records_with_error: true, // Skip malformed rows
  });

  const balanceData = records
    .filter(record => {
      // Only process records that have all required fields
      return record['<DATE>'] && record['<BALANCE>'] !== undefined && record['<EQUITY>'] !== undefined;
    })
    .map(record => {
      try {
        // Parse date from format "2023.01.01 00:00"
        const dateStr = record['<DATE>'];
        if (!dateStr) return null;

        const [datePart, timePart] = dateStr.split(' ');
        if (!datePart) return null;

        const [year, month, day] = datePart.split('.');
        if (!year || !month || !day) return null;

        const [hour, minute] = timePart ? timePart.split(':') : ['00', '00'];
        
        const dateTime = new Date(
          parseInt(year),
          parseInt(month) - 1,
          parseInt(day),
          parseInt(hour),
          parseInt(minute)
        );

        // Validate date
        if (isNaN(dateTime.getTime())) return null;

        return {
          dateTime: dateTime.toISOString(),
          balance: parseFloat(record['<BALANCE>']) || 0,
          equity: parseFloat(record['<EQUITY>']) || 0,
          depositLoad: parseFloat(record['<DEPOSIT LOAD>'] || record['<DEPOSIT_LOAD>']) || 0,
        };
      } catch (error) {
        // Skip invalid records
        console.warn(`Skipping invalid record: ${JSON.stringify(record)}`);
        return null;
      }
    })
    .filter(record => record !== null); // Remove null entries

  return balanceData;
}

