// The page's own plugins: list numbers and the empty note's words, Find in Note, web addresses as links, tables kept
// plain, files a note from elsewhere keeps, and a line to type in under a last table or file.
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';

/// Each numbered item's number, by the Markdown's rules: a table, a file or a code block starts the count again; a
/// line at a level ends the deeper lists, and a line that is not a numbered item ends the list at its own level.
export function numbersOf(doc) {
  const numbers = new Map();
  let counts = new Map();
  doc.forEach((node, pos) => {
    const name = node.type.name;
    if (name === 'table' || name === 'attachment' || name === 'codeBlock') { counts = new Map(); return; }
    const level = node.attrs.indent ?? 0;
    const numbered = name === 'item' && node.attrs.kind === 'numbered';
    for (const at of [...counts.keys()]) if (at > level || (!numbered && at === level)) counts.delete(at);
    if (numbered) {
      counts.set(level, (counts.get(level) ?? 0) + 1);
      numbers.set(pos, counts.get(level));
    }
  });
  return numbers;
}

/// Where the empty note's words show: the first empty line after the last file, when the note has no words at all.
export function placeholderAt(doc) {
  let words = false;
  let lastFile = -1;
  const lines = [];
  doc.forEach((node, pos) => {
    if (node.type.name === 'attachment') { lastFile = pos; return; }
    if (node.type.name === 'table' || node.textContent.length) { words = true; return; }
    if (node.isTextblock) lines.push({ pos, node });
    else if (node.type.name === 'item') lines.push({ pos: pos + 1, node: node.firstChild });
  });
  if (words) return null;
  return lines.find(line => line.pos > lastFile) ?? null;
}

export const lookKey = new PluginKey('look');

let numberVersions = 0;

/// The list numbers and the empty note's words. Numbers are not decorations, as one on each of many lines makes each
/// change slow: list marks read them here, and `version` grows when one changes.
function lookOf(doc, text, old, mapping) {
  const numbers = numbersOf(doc);
  const empty = text ? placeholderAt(doc) : null;
  const emptyAt = empty ? empty.pos : -1;
  let version = old?.version;
  if (!old || old.numbers.size !== numbers.size) version = ++numberVersions;
  else {
    for (const [pos, n] of old.numbers) {
      if (numbers.get(mapping ? mapping.map(pos) : pos) !== n) { version = ++numberVersions; break; }
    }
  }
  if (old && old.text === text && (old.emptyAt < 0 ? emptyAt < 0 : (mapping ? mapping.map(old.emptyAt) : old.emptyAt) === emptyAt)) {
    return { text, numbers, version, emptyAt, set: mapping ? old.set.map(mapping, doc) : old.set };
  }
  const set = empty
    ? DecorationSet.create(doc, [Decoration.node(empty.pos, empty.pos + empty.node.nodeSize,
      { class: 'is-empty', 'data-placeholder': text })])
    : DecorationSet.empty;
  return { text, numbers, version, emptyAt, set };
}

/// The list numbers and the empty note's words, made again only when the note changes.
export function lookPlugin(placeholder) {
  return new Plugin({
    key: lookKey,
    state: {
      init: (_, state) => lookOf(state.doc, placeholder(), null, null),
      apply(tr, value, _, state) {
        const meta = tr.getMeta(lookKey);
        if (meta) return lookOf(state.doc, meta.text, value, tr.docChanged ? tr.mapping : null);
        return tr.docChanged ? lookOf(state.doc, value.text, value, tr.mapping) : value;
      },
    },
    props: {
      decorations: state => lookKey.getState(state).set,
    },
  });
}

export const findKey = new PluginKey('find');

function matchesOf(doc, query) {
  if (!query) return [];
  const needle = query.toLocaleLowerCase();
  const found = [];
  doc.descendants((node, pos) => {
    if (!node.isTextblock) return true;
    const text = node.textContent.toLocaleLowerCase();
    for (let at = text.indexOf(needle); at >= 0; at = text.indexOf(needle, at + needle.length)) {
      found.push({ from: pos + 1 + at, to: pos + 1 + at + needle.length });
    }
    return false;
  });
  return found;
}

/// Find in Note: each match drawn, the current one stronger.
export function findPlugin() {
  return new Plugin({
    key: findKey,
    state: {
      init: () => ({ query: '', matches: [], index: 0 }),
      apply(tr, value) {
        const meta = tr.getMeta(findKey);
        if (meta && 'query' in meta) {
          const matches = matchesOf(tr.doc, meta.query);
          return { query: meta.query, matches, index: 0 };
        }
        if (meta && 'index' in meta) return { ...value, index: meta.index };
        if (tr.docChanged && value.query) {
          const matches = matchesOf(tr.doc, value.query);
          return { ...value, matches, index: Math.min(value.index, Math.max(0, matches.length - 1)) };
        }
        return value;
      },
    },
    props: {
      decorations(state) {
        const { matches, index } = findKey.getState(state);
        if (!matches.length) return null;
        return DecorationSet.create(state.doc, matches.map((match, i) =>
          Decoration.inline(match.from, match.to, { class: i === index ? 'found now' : 'found' })));
      },
    },
  });
}

const ADDRESS = /(?:https?:\/\/|www\.)[^\s<>"]+/gi;
const END = /[.,;:!?)\]}'"]+$/;

/// The web addresses in [text], each with where it starts and ends.
export function addressesIn(text) {
  const found = [];
  for (const match of text.matchAll(ADDRESS)) {
    const words = match[0].replace(END, '');
    if (!words.includes('.') || /:\/\/$/.test(words) || words.length === 0) continue;
    if (/^(?:https?:\/\/)?www\.?$/i.test(words)) continue;
    found.push({ from: match.index, to: match.index + words.length, words });
  }
  return found;
}

/// A quiet transaction that gives each web address in the words a link, and takes the link off words that are no
/// longer an address; null when nothing changes. A link the person made stays as it is.
export function autoLinks(state) {
  const link = state.schema.marks.link;
  const tr = state.tr;
  state.doc.descendants((node, pos, parent) => {
    if (!node.isTextblock) return true;
    if (node.type.name === 'codeBlock' || parent.type.spec.tableRole) return false;
    const start = pos + 1;
    const wanted = addressesIn(node.textContent);
    const autos = [];
    const own = [];
    node.forEach((child, offset) => {
      const mark = link.isInSet(child.marks);
      if (!mark) return;
      const range = { from: start + offset, to: start + offset + child.nodeSize, mark };
      (mark.attrs.auto ? autos : own).push(range);
    });
    const keep = wanted.filter(w => !own.some(o => o.from < start + w.to && o.to > start + w.from));
    const same = (a, w) => a.mark.attrs.href === w.words;
    // An auto link run is right when its letters are exactly one wanted address.
    const runs = [];
    for (const range of autos) {
      const last = runs.at(-1);
      if (last && last.to === range.from && last.mark.eq(range.mark)) last.to = range.to;
      else runs.push({ ...range });
    }
    const right = runs.length === keep.length && runs.every((run, i) =>
      run.from === start + keep[i].from && run.to === start + keep[i].to && same(run, keep[i]));
    if (right) return false;
    for (const run of runs) tr.removeMark(run.from, run.to, run.mark);
    for (const w of keep) tr.addMark(start + w.from, start + w.to, link.create({ href: w.words, auto: true }));
    return false;
  });
  if (!tr.docChanged) return null;
  return tr.setMeta('addToHistory', false).setMeta('quiet', true);
}

/// The ids of the files in [doc].
export function fileIds(doc) {
  const ids = new Set();
  doc.forEach(node => { if (node.type.name === 'attachment') ids.add(node.attrs.id); });
  return ids;
}

/// A note from elsewhere keeps its files: a change that takes one out is refused, unless it is the app's own.
export function keepFilesPlugin(keeps) {
  return new Plugin({
    filterTransaction(tr, state) {
      if (!keeps() || !tr.docChanged || tr.getMeta('quiet') || tr.getMeta('load')) return true;
      const after = fileIds(tr.doc);
      for (const id of fileIds(state.doc)) if (!after.has(id)) return false;
      return true;
    },
  });
}

/// Tables stay plain, their first row the header; a last table or file keeps a line under it to type in.
export function tidyPlugin() {
  return new Plugin({
    appendTransaction(transactions, _, state) {
      if (!transactions.some(tr => tr.docChanged)) return null;
      const { schema } = state;
      const tr = state.tr;
      state.doc.forEach((node, pos) => {
        if (node.type.name !== 'table') return;
        let rowPos = pos + 1;
        node.forEach((row, _, r) => {
          let cellPos = rowPos + 1;
          row.forEach(cell => {
            const type = r === 0 ? schema.nodes.tableHeader : schema.nodes.tableCell;
            if (cell.type !== type) tr.setNodeMarkup(cellPos, type, cell.attrs);
            let marked = false;
            cell.descendants(child => { if (child.marks.length) marked = true; });
            if (marked) tr.removeMark(cellPos + 1, cellPos + cell.nodeSize - 1, null);
            cellPos += cell.nodeSize;
          });
          rowPos += row.nodeSize;
        });
      });
      const last = tr.doc.lastChild;
      if (last && (last.type.name === 'table' || last.type.name === 'attachment')) {
        tr.insert(tr.doc.content.size, schema.nodes.paragraph.create());
      }
      return tr.docChanged ? tr : null;
    },
  });
}

/// Selects match [index] of Find, without taking the keyboard.
export function selectMatch(state, index) {
  const { matches } = findKey.getState(state);
  const tr = state.tr.setMeta(findKey, { index });
  const match = matches[index];
  if (match) tr.setSelection(TextSelection.create(state.doc, match.from, match.to));
  return tr;
}
