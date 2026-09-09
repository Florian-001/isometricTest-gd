import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';

export const HEADER_ROW = 5;
const HEADERS = ['Index', 'Class', 'Unlock Level', 'Ability', 'Description'];
const WIDTHS = [64, 150, 112, 182, 720];

export async function loadRuntime(modules) {
  const require = createRequire(path.join(path.resolve(modules), '__class_reference__.cjs'));
  return {
    artifact: await import(pathToFileURL(require.resolve('@oai/artifact-tool')).href),
    JSZip: require('jszip'),
  };
}

// Resource labels remain literal text, including names beginning with '='.
const text = value => value.startsWith('=') ? `'${value}` : value;

export function classSheets(data) {
  if (!Array.isArray(data.rows) || !data.rows.length) throw new Error('No class ability records supplied.');
  const shared = [];
  const classes = new Map();
  for (const row of data.rows) {
    if (![row.class, row.ability, row.description].every(value => typeof value === 'string') ||
        !(row.class_id === null || (typeof row.class_id === 'string' && row.class_id.length > 0)) ||
        !(row.level === null || (Number.isInteger(row.level) && row.level > 0))) {
      throw new Error('Invalid class ability record.');
    }
    if (row.class_id === null) shared.push(row);
    else {
      if (!classes.has(row.class_id)) classes.set(row.class_id, { title: row.class, rows: [] });
      const group = classes.get(row.class_id);
      if (group.title !== row.class) throw new Error(`Inconsistent class name for ${row.class_id}.`);
      group.rows.push(row);
    }
  }
  if (!classes.size) throw new Error('No classes supplied.');
  const used = new Set(['history']); // Excel reserves History for change tracking.
  const truncate = (value, length) => value.slice(0, length).replace(/[\uD800-\uDBFF]$/, '').replace(/'+$/, '');
  return [...classes.values()].map(group => {
    const base = group.title.replace(/[\u0000-\u001f\u007f\\/?*:[\]]/g, ' ').trim().replace(/^'+|'+$/g, '').trim() || 'Class';
    let name = truncate(base, 31);
    for (let suffix = 2; used.has(name.toLowerCase()); suffix++) {
      const ending = ` (${suffix})`;
      name = truncate(base, 31 - ending.length) + ending;
    }
    used.add(name.toLowerCase());
    return { name, title: group.title, rows: [...shared, ...group.rows] };
  });
}

export function buildWorkbook(artifact, data) {
  const workbook = artifact.Workbook.create();
  classSheets(data).forEach((group, index) => addClassSheet(workbook, group, index));
  workbook.recalculate();
  return workbook;
}

function addClassSheet(workbook, data, index) {
  const sheet = workbook.worksheets.add(data.name);
  const lastRow = HEADER_ROW + data.rows.length;
  const body = sheet.getRange(`A1:E${lastRow}`);
  body.format.font = { name: 'Arial', size: 11, color: '#253246' };
  body.format.verticalAlignment = 'center';
  sheet.showGridLines = false;
  sheet.tabColor = '#243B53';
  sheet.getRange('A2:E2').merge();
  sheet.getRange('A2').values = [[text(`${data.title} abilities`)]];
  sheet.getRange('A2:E2').format.borders = { bottom: { style: 'thin', color: '#C7D0DB' } };
  sheet.getRange('A2').format.font = { name: 'Arial', size: 16, bold: true, color: '#243B53' };
  sheet.getRange('A2:E2').format.wrapText = true;
  sheet.getRange('A2:E2').format.rowHeight = Math.max(28, Math.ceil((data.title.length + 10) / 95) * 24);
  sheet.getRange('A3:E3').values = [[
    'Per sheet', 'Generated reference', 'Class levels', 'All classes = basic attacks',
    'Edit resources in Godot. Saved changes update this file. Close and reopen Excel to see updates. Indices show reference order, not permanent IDs. Blank unlock level = no class-level requirement.',
  ]];
  sheet.getRange('A3:E3').format.font = { name: 'Arial', size: 10, color: '#526276' };
  sheet.getRange('A3:E3').format.wrapText = true;
  sheet.getRange('A3:E3').format.rowHeight = 42;
  sheet.getRange('A4:E4').format.rowHeight = 8;
  let abilityIndex = 0;
  const values = data.rows.map(row => [
    // A class row with no unlock level is the informational empty-class row.
    row.class_id !== null && row.level === null ? null : ++abilityIndex,
    text(row.class), row.level, text(row.ability), text(row.description),
  ]);
  sheet.getRange(`A${HEADER_ROW}:E${lastRow}`).values = [HEADERS, ...values];
  const table = sheet.tables.add(`A${HEADER_ROW}:E${lastRow}`, true, `ClassAbilities${index + 1}`);
  table.style = 'TableStyleMedium2';
  table.showFilterButton = true;
  const header = sheet.getRange(`A${HEADER_ROW}:E${HEADER_ROW}`);
  header.format.fill = '#243B53';
  header.format.font = { name: 'Arial', size: 11, bold: true, color: '#FFFFFF' };
  header.format.horizontalAlignment = 'center';
  header.format.rowHeight = 27;
  for (let col = 0; col < WIDTHS.length; col++) {
    sheet.getRangeByIndexes(0, col, lastRow, 1).format.columnWidthPx = WIDTHS[col];
  }
  const rows = sheet.getRange(`A${HEADER_ROW + 1}:E${lastRow}`);
  rows.format.wrapText = true;
  rows.format.verticalAlignment = 'top';
  for (const column of ['A', 'C']) {
    sheet.getRange(`${column}${HEADER_ROW + 1}:${column}${lastRow}`).setNumberFormat('0');
    sheet.getRange(`${column}${HEADER_ROW + 1}:${column}${lastRow}`).format.horizontalAlignment = 'center';
  }
  data.rows.forEach((row, index) => {
    const range = sheet.getRangeByIndexes(HEADER_ROW + index, 0, 1, HEADERS.length);
    range.format.fill = index % 2 === 0 ? '#F0F3F7' : '#FFFFFF';
    range.format.borders = { bottom: { style: 'thin', color: '#DCE3EB' } };
    // Estimate conservatively at Arial 11, preserving explicit line breaks.
    const lines = Math.max(...['', row.class, '', row.ability, row.description].map((value, col) =>
      value.split('\n').reduce((total, line) => total + Math.max(1, Math.ceil(line.length / ((WIDTHS[col] - 20) / 7.2))), 0)));
    range.format.rowHeight = Math.max(32, lines * 15 + 12);
  });
  sheet.freezePanes.freezeRows(HEADER_ROW);
}

// Compare the actual cells, table and layout XML. ZIP times and document timestamps
// do not participate, and a copied workbook needs no machine-local freshness cache.
export async function workbookContent(JSZip, bytes) {
  const zip = await JSZip.loadAsync(bytes);
  const names = Object.keys(zip.files).filter(name => /^xl\/(workbook\.xml|styles\.xml|sharedStrings\.xml|worksheets\/.*\.xml|tables\/.*\.xml|theme\/.*\.xml)$/.test(name)).sort();
  if (!names.includes('xl/workbook.xml') || !names.some(name => name.startsWith('xl/tables/'))) throw new Error('Missing workbook table.');
  return Promise.all(names.map(async name => {
    const rels = zip.file(path.posix.join(path.posix.dirname(name), '_rels', `${path.posix.basename(name)}.rels`));
    const targets = new Map();
    if (rels) {
      for (const relation of (await rels.async('string')).matchAll(/<(?:\w+:)?Relationship\s[^>]*\/?\s*>/g)) {
        const attributes = Object.fromEntries([...relation[0].matchAll(/([\w:]+)="([^"]*)"/g)].map(match => [match[1], match[2]]));
        targets.set(attributes.Id, `${attributes.Type}|${attributes.TargetMode ?? ''}|${attributes.Target}`);
      }
    }
    // Export assigns random relationship IDs; their resolved targets are stable.
    const xml = (await zip.file(name).async('string')).replace(/r:id="([^"]*)"/g, (_, id) => {
      if (!targets.has(id)) throw new Error(`Unresolved workbook relationship: ${id}`);
      return `r:id="${targets.get(id)}"`;
    });
    return [name, xml];
  }));
}

export async function exportReference(runtime, data, output, { check = false } = {}) {
  if (path.extname(output).toLowerCase() !== '.xlsx') throw new Error('Output must use the .xlsx extension.');
  const workbook = buildWorkbook(runtime.artifact, data);
  const file = await runtime.artifact.SpreadsheetFile.exportXlsx(workbook);
  const scratch = await fs.mkdtemp(path.join(os.tmpdir(), 'class-reference-'));
  const scratchFile = path.join(scratch, 'export.xlsx');
  let bytes;
  try {
    await file.save(scratchFile);
    bytes = await fs.readFile(scratchFile);
  } finally {
    await fs.unlink(scratchFile).catch(() => {});
    await fs.unlink(`${scratchFile}.inspect.ndjson`).catch(() => {});
    await fs.rmdir(scratch);
  }
  let existing;
  let destinationExists = false;
  try {
    existing = await fs.readFile(output);
    destinationExists = true;
  } catch (error) {
    if (['EACCES', 'EPERM', 'EBUSY'].includes(error.code)) destinationExists = true;
    else if (error.code !== 'ENOENT') throw error;
  }
  let same = false;
  if (existing) {
    try { same = JSON.stringify(await workbookContent(runtime.JSZip, existing)) === JSON.stringify(await workbookContent(runtime.JSZip, bytes)); }
    catch { /* Invalid or incomplete workbook: replace only after successful export. */ }
  }
  if (same) return { ok: true, changed: false, errors: [] };
  if (check) return { ok: false, changed: false, errors: ['Workbook is missing, stale, or has a different table layout.'] };
  const pendingDirectory = path.join(path.dirname(output), '.godot', 'class_ability_reference');
  await fs.mkdir(pendingDirectory, { recursive: true });
  const pending = path.join(pendingDirectory, `workbook-pending-${process.pid}-${Date.now()}.xlsx`);
  await fs.writeFile(pending, bytes, { flag: 'wx' });
  try {
    await fs.rename(pending, output);
    return { ok: true, changed: true, errors: [] };
  } catch (error) {
    if (['EACCES', 'EPERM', 'EBUSY'].includes(error.code) && destinationExists) {
      return { ok: false, changed: false, locked: true, pending_path: pending, errors: ['Workbook is open or locked. Close it in Excel to allow the pending update.'] };
    }
    await fs.unlink(pending).catch(() => {});
    throw error;
  }
}

async function main() {
  const args = {};
  for (const argument of process.argv.slice(2)) {
    if (argument === '--check') args.check = true;
    else if (/^--(modules|input|output)=/.test(argument)) {
      const at = argument.indexOf('=');
      args[argument.slice(2, at)] = argument.slice(at + 1);
    } else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!args.modules || !args.input || !args.output) throw new Error('Expected --modules, --input and --output.');
  const runtime = await loadRuntime(args.modules);
  const data = JSON.parse(await fs.readFile(args.input, 'utf8'));
  return exportReference(runtime, data, path.resolve(args.output), args);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => ({ ok: false, changed: false, errors: [error.message] })).then(result => {
    console.log(`CLASS_REFERENCE_RESULT=${JSON.stringify(result)}`);
    process.exitCode = result.ok ? 0 : (result.locked ? 3 : 1);
  });
}
