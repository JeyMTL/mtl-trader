const XLSX = require('xlsx');
const fs = require('fs');
const wb = XLSX.readFile('D:\\mtl-trader\\trades.xlsx');
const ws = wb.Sheets[wb.SheetNames[0]];
const data = XLSX.utils.sheet_to_json(ws, {header:1});

let csv = 'Time,Position,Symbol,Type,Volume,Price,S/L,T/P,Time,Price,Commission,Swap,Profit\n';
for (let i = 7; i < data.length; i++) {
  const row = data[i];
  if (!row || !row[0]) continue;
  const time = String(row[0] || '').trim();
  if (!time.match(/\d{4}\.\d{2}\.\d{2}/)) continue;
  if (row.length < 13) continue;
  csv += row.slice(0, 13).join(',') + '\n';
}

const lines = csv.split('\n').filter(l => l.trim());
fs.writeFileSync('C:\\Users\\JeyMTLL\\Pictures\\trades_clean.csv', csv);
console.log('Created trades_clean.csv with ' + (lines.length - 1) + ' trades');
console.log('Header: ' + lines[0]);
console.log('First trade: ' + lines[1]);
console.log('Last trade: ' + lines[lines.length - 1]);
