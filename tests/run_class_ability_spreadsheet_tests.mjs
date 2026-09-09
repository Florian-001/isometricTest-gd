import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildWorkbook, exportReference, loadRuntime, SHEET } from '../addons/class_ability_reference/write_reference.mjs';

const modules = process.argv[2] || process.env.CLASS_ABILITIES_NODE_MODULES || path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
const runtime = await loadRuntime(modules);
const directory = path.resolve('.godot/class_ability_spreadsheet_tests');
await fs.mkdir(directory, { recursive: true });
const output = path.join(directory, 'fixture.xlsx');
await fs.unlink(output).catch(error => { if (error.code !== 'ENOENT') throw error; });
const data = { rows: [
  { class: '=Literal <&>', level: 2, ability: 'Spell | [test] ×', description: 'Line one\n' + 'Long description with status effects and targeting requirements. '.repeat(9) },
  { class: 'All classes', level: null, ability: 'Strike', description: 'Basic attack.' },
] };
assert.equal((await exportReference(runtime, data, output, { check: true })).ok, false);
await assert.rejects(fs.access(output));
assert.equal((await exportReference(runtime, data, output)).changed, true);
const before = await fs.readFile(output);
const modified = (await fs.stat(output)).mtimeMs;
assert.deepEqual(await exportReference(runtime, data, output), { ok: true, changed: false, errors: [] });
assert.equal((await fs.stat(output)).mtimeMs, modified);
assert.equal((await exportReference(runtime, data, output, { check: true })).ok, true);
assert.deepEqual(await fs.readFile(output), before);

const { SpreadsheetFile, FileBlob } = runtime.artifact;
const reopened = await SpreadsheetFile.importXlsx(await FileBlob.load(output));
const values = reopened.worksheets.getItem(SHEET).getRange('A6:D7').values;
assert.equal(values[0][0], data.rows[0].class);
assert.equal(values[0][1], 2);
assert.equal(typeof values[0][1], 'number');
assert.equal(values[0][2], data.rows[0].ability);
assert.equal(values[0][3], data.rows[0].description);
assert.equal(values[1][1], null);
const zip = await runtime.JSZip.loadAsync(before);
const sheetXml = await zip.file('xl/worksheets/sheet1.xml').async('string');
assert.match(sheetXml, /ySplit="5"[^>]*state="frozen"/);
assert.doesNotMatch(sheetXml, /<(?:x:)?f[ >]/);
assert.match(await zip.file('xl/tables/table1.xml').async('string'), /autoFilter ref="A5:D7"/);

// A changed required layout is stale even when the resource records still match.
const changedLayout = buildWorkbook(runtime.artifact, data);
changedLayout.worksheets.getItem(SHEET).freezePanes.freezeRows(1);
await (await SpreadsheetFile.exportXlsx(changedLayout)).save(output);
const staleBytes = await fs.readFile(output);
assert.equal((await exportReference(runtime, data, output, { check: true })).ok, false);
assert.deepEqual(await fs.readFile(output), staleBytes);
assert.equal((await exportReference(runtime, data, output)).changed, true);
const validBytes = await fs.readFile(output);
await assert.rejects(exportReference(runtime, { rows: [{ ...data.rows[0], level: '2' }] }, output), /Invalid class ability record/);
assert.deepEqual(await fs.readFile(output), validBytes);

if (process.argv.includes('--review')) {
  const input = path.resolve('CLASS_ABILITIES.xlsx');
  const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
  const rows = JSON.parse(await fs.readFile('.godot/class_ability_reference/shipped_rows.json', 'utf8')).rows;
  const matrix = workbook.worksheets.getItem(SHEET).getRange(`A6:D${rows.length + 5}`).values;
  assert.deepEqual(matrix, rows.map(row => [row.class, row.level, row.ability, row.description]));
  const inspection = await workbook.inspect({ kind: 'table', range: `'${SHEET}'!A5:D${rows.length + 5}`, include: 'values,formulas', tableMaxRows: rows.length + 1, tableMaxCols: 4 });
  await fs.writeFile(path.join(directory, 'reopened-inspection.ndjson'), inspection.ndjson);
  for (let start = 1, index = 1; start <= rows.length + 5; start += 10, index++) {
    const image = await workbook.render({ sheetName: SHEET, range: `A${start}:D${Math.min(rows.length + 5, start + 9)}`, scale: 1, format: 'png' });
    await fs.writeFile(path.join(directory, `reopened-${index}.png`), new Uint8Array(await image.arrayBuffer()));
  }
  const image = await reopened.render({ sheetName: SHEET, range: 'A1:D7', scale: 1, format: 'png' });
  await fs.writeFile(path.join(directory, 'long-description.png'), new Uint8Array(await image.arrayBuffer()));
}
console.log('CLASS_ABILITY_SPREADSHEET_TESTS_OK (round-trip records, numeric levels, literal text, filters, frozen headers, unchanged output, read-only checks, layout drift, invalid data)');
