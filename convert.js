const XLSX = require('xlsx');
const fs = require('fs');
const path = require('path');

const inputFile = process.argv[2] || 'trades.xlsx';
const outputFile = process.argv[3] || 'trades_clean.csv';

if (!fs.existsSync(inputFile)) {
  console.error(`Input file not found: ${inputFile}`);
  process.exit(1);
}

console.log(`Reading ${inputFile}...`);
const wb = XLSX.readFile(inputFile);
const ws = wb.Sheets[wb.SheetNames[0]];
const data = XLSX.utils.sheet_to_json(ws, {header:1});

let csv = 'Time,Position,Symbol,Type,Volume,Price,S/L,T/P,Time,Price,Commission,Swap,Profit\n';
for (let i = 0; i < data.length; i++) {
  const row = data[i];
  if (!row || !row[0]) continue;
  const time = String(row[0] || '').trim();
  // Match YYYY.MM.DD
  if (!time.match(/\d{4}\.\d{2}\.\d{2}/)) continue;
  if (row.length < 13) continue;
  csv += row.slice(0, 13).map(v => String(v || '').trim()).join(',') + '\n';
}

const lines = csv.split('\n').filter(l => l.trim());
fs.writeFileSync(outputFile, csv);
console.log(`Created ${outputFile} with ${lines.length - 1} trades`);
console.log('Header: ' + lines[0]);
if (lines.length > 1) {
  console.log('First trade: ' + lines[1]);
  console.log('Last trade: ' + lines[lines.length - 1]);
}
