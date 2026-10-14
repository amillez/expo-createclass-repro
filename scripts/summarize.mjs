// Prints a Markdown table of results/raw.csv: median and raw runs per configuration, in MiB.
import { readFileSync } from 'node:fs';

const [header, ...lines] = readFileSync(new URL('../results/raw.csv', import.meta.url), 'utf8').trim().split('\n');
const columns = header.split(',');
const rows = lines.map((line, i) => {
  const values = line.split(',');
  const row = Object.fromEntries(values.map((value, j) => [columns[j], value]));
  if (values.length !== columns.length || !/^\d+$/.test(row.kb) || !/^\d*$/.test(row.native_heap_kb)) {
    throw new Error(`malformed row ${i + 2} in results/raw.csv: ${line}`);
  }
  return row;
});

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
};
const mib = (kb) => (kb / 1024).toFixed(1);

const groups = new Map();
for (const row of rows) {
  const key = `${row.platform}|${row.metric}|${row.classes}|${row.patch}`;
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(row);
}

console.log('| Platform | Metric | Classes | Patch | Runs | Median (MiB) | Raw runs (MiB) | Native Heap PSS median (MiB) |');
console.log('| --- | --- | ---: | --- | ---: | ---: | --- | ---: |');
for (const group of groups.values()) {
  const { platform, metric, classes, patch } = group[0];
  const values = group.map((row) => Number(row.kb));
  const native = group.filter((row) => row.native_heap_kb).map((row) => Number(row.native_heap_kb));
  console.log(
    `| ${platform} | ${metric} | ${classes} | ${patch} | ${group.length} | ${mib(median(values))} | ` +
      `${values.map(mib).join(', ')} | ${native.length ? mib(median(native)) : 'n/a'} |`
  );
}
