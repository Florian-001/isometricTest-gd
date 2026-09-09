import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { buildWorkbook, classSheets, exportReference, loadRuntime } from '../addons/class_ability_reference/write_reference.mjs';

const modules = process.argv[2] || process.env.CLASS_ABILITIES_NODE_MODULES || path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules');
const runtime = await loadRuntime(modules);
const directory = path.resolve('.godot/class_ability_spreadsheet_tests');
await fs.mkdir(directory, { recursive: true });
const output = path.join(directory, 'fixture.xlsx');
await fs.unlink(output).catch(error => { if (error.code !== 'ENOENT') throw error; });
const data = { rows: [
  { class_id: 'first', class: '=Literal <&>', level: 2, ability: 'Spell | [test] ×', description: 'Line one\n' + 'Long description with status effects and targeting requirements. '.repeat(9) },
  { class_id: null, class: 'All classes', level: null, ability: 'Strike', description: 'Basic attack.' },
  { class_id: null, class: 'All classes', level: null, ability: 'Shoot', description: 'Ranged basic attack.' },
  { class_id: 'second', class: '=Literal <&>', level: 3, ability: 'Different unlock', description: 'Same display name, different class.' },
  { class_id: 'empty', class: 'Empty class', level: null, ability: '—', description: 'No class unlocks; basic attacks are still available.' },
] };
const groups = classSheets(data);
assert.deepEqual(groups.map(group => group.name), ['=Literal <&>', '=Literal <&> (2)', 'Empty class']);
const names = classSheets({ rows: ['Mage/Fire', 'mage:fire', 'A'.repeat(50), 'A'.repeat(51), 'History', "'[]'", 'All classes'].map((name, index) => ({ ...data.rows[0], class_id: String(index), class: name })) }).map(group => group.name);
assert.equal(new Set(names.map(name => name.toLowerCase())).size, names.length);
assert.ok(names.every(name => name.length > 0 && name.length <= 31 && !/[\\/?*:[\]]/.test(name) && !name.startsWith("'") && !name.endsWith("'") && name.toLowerCase() !== 'history'));
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
for (const group of groups) {
  const sheet = reopened.worksheets.getItem(group.name);
  assert.deepEqual(sheet.getRange('A5:E5').values, [['Index', 'Class', 'Unlock Level', 'Ability', 'Description']]);
  const values = sheet.getRange('A6:E8').values;
  assert.deepEqual(values, group.rows.map((row, index) => [row.level === null && row.class_id !== null ? null : index + 1, row.class, row.level, row.ability, row.description]));
  assert.deepEqual(values.slice(0, 2).map(row => [row[0], row[3]]), [[1, 'Strike'], [2, 'Shoot']]);
  if (group.name === 'Empty class') assert.equal(values[2][0], null);
  else {
    assert.equal(typeof values[2][0], 'number');
    assert.equal(typeof values[2][2], 'number');
  }
  assert.equal(values[0][2], null);
}
const zip = await runtime.JSZip.loadAsync(before);
assert.equal(Object.keys(zip.files).filter(name => /^xl\/worksheets\/sheet\d+\.xml$/.test(name)).length, 3);
for (let index = 1; index <= groups.length; index++) {
  const sheetXml = await zip.file(`xl/worksheets/sheet${index}.xml`).async('string');
  assert.match(sheetXml, /ySplit="5"[^>]*state="frozen"/);
  assert.match(sheetXml, /min="1" max="1" width="8"/); // 64px index column.
  assert.doesNotMatch(sheetXml, /<(?:x:)?f[ >]/);
  assert.match(await zip.file(`xl/tables/table${index}.xml`).async('string'), /autoFilter ref="A5:E8"/);
}

// Inserting an unlock ahead of another at the same level shifts its reference index.
const added = { rows: [{ ...data.rows[0], ability: 'New first unlock' }, ...data.rows] };
assert.equal((await exportReference(runtime, added, output)).changed, true);
const withAdded = await SpreadsheetFile.importXlsx(await FileBlob.load(output));
assert.deepEqual(withAdded.worksheets.getItem(groups[0].name).getRange('A8:E9').values.map(row => [row[0], row[3]]), [[3, 'New first unlock'], [4, data.rows[0].ability]]);
assert.deepEqual(withAdded.worksheets.getItem(groups[1].name).getRange('A6:A8').values, [[1], [2], [3]]);
assert.equal((await exportReference(runtime, data, output)).changed, true);
const afterRemoval = await SpreadsheetFile.importXlsx(await FileBlob.load(output));
assert.deepEqual(afterRemoval.worksheets.getItem(groups[0].name).getRange('A8:E8').values.map(row => [row[0], row[3]]), [[3, data.rows[0].ability]]);

// A changed required layout is stale even when the resource records still match.
const changedLayout = buildWorkbook(runtime.artifact, data);
changedLayout.worksheets.getItem(groups[1].name).freezePanes.freezeRows(1);
await (await SpreadsheetFile.exportXlsx(changedLayout)).save(output);
const staleBytes = await fs.readFile(output);
assert.equal((await exportReference(runtime, data, output, { check: true })).ok, false);
assert.deepEqual(await fs.readFile(output), staleBytes);
assert.equal((await exportReference(runtime, data, output)).changed, true);
const validBytes = await fs.readFile(output);
await assert.rejects(exportReference(runtime, { rows: [{ ...data.rows[0], level: '2' }] }, output), /Invalid class ability record/);
assert.deepEqual(await fs.readFile(output), validBytes);

const review = process.argv.find(argument => argument === '--review' || argument.startsWith('--review='));
if (review) {
  const input = path.resolve(review === '--review' ? 'CLASS_ABILITIES.xlsx' : review.slice('--review='.length));
  const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(input));
  const rows = JSON.parse(await fs.readFile('.godot/class_ability_reference/shipped_rows.json', 'utf8')).rows;
  const shippedGroups = classSheets({ rows });
  const shippedZip = await runtime.JSZip.loadAsync(await fs.readFile(input));
  assert.equal(Object.keys(shippedZip.files).filter(name => /^xl\/worksheets\/sheet\d+\.xml$/.test(name)).length, shippedGroups.length);
  for (const [sheetIndex, group] of shippedGroups.entries()) {
    const lastRow = group.rows.length + 5;
    const matrix = workbook.worksheets.getItem(group.name).getRange(`A6:E${lastRow}`).values;
    assert.deepEqual(matrix, group.rows.map((row, index) => [row.level === null && row.class_id !== null ? null : index + 1, row.class, row.level, row.ability, row.description]));
    const inspection = await workbook.inspect({ kind: 'table', range: `'${group.name.replaceAll("'", "''")}'!A5:E${lastRow}`, include: 'values,formulas', tableMaxRows: group.rows.length + 1, tableMaxCols: 5 });
    await fs.writeFile(path.join(directory, `class-${sheetIndex + 1}-inspection.ndjson`), inspection.ndjson);
    const image = await workbook.render({ sheetName: group.name, range: `A1:E${lastRow}`, scale: 1, format: 'png' });
    await fs.writeFile(path.join(directory, `class-${sheetIndex + 1}.png`), new Uint8Array(await image.arrayBuffer()));
  }
  const image = await reopened.render({ sheetName: groups[0].name, range: 'A1:E8', scale: 1, format: 'png' });
  await fs.writeFile(path.join(directory, 'long-description.png'), new Uint8Array(await image.arrayBuffer()));
}
console.log('CLASS_ABILITY_SPREADSHEET_TESTS_OK (per-sheet numeric indices, additions/removals, empty classes, separate sheets, shared attacks, round-trip values, filters, frozen headers, unchanged output, read-only checks, layout drift, invalid data)');
