// The note editor page of the Relay Everything phone app. The app loads one note into it and runs the format tools
// through it; the page tells the app each change. Messages from the app carry `do`; messages to the app carry `is`.
import { Editor, Extension, InputRule, getMarkRange } from '@tiptap/core';
import { UndoRedo } from '@tiptap/extensions';
import { AllSelection, EditorState, NodeSelection, Selection, TextSelection } from '@tiptap/pm/state';
import { Fragment, Slice } from '@tiptap/pm/model';
import { closeHistory, undoDepth, redoDepth } from '@tiptap/pm/history';
import {
  TableMap, addColumnAfter, addColumnBefore, addRowAfter, addRowBefore, deleteColumn, deleteRow, goToNextCell, isInTable,
} from '@tiptap/pm/tables';
import { schemaExtensions, Item, Attachment, kindOf } from './schema.js';
import { caretAt, headKind, indentLines, lineStyle, listOf, quote, setLineKind, tick, unwrapItem } from './lines.js';
import { pasteBlocks } from './paste.js';
import {
  autoLinks, findKey, findPlugin, keepFilesPlugin, lookKey, lookPlugin, selectMatch, tidyPlugin,
} from './plugins.js';
import { drawCard } from './cards.js';

// What the app set with the last `load`, and what it changed since.
const page = {
  editable: true,
  fromElsewhere: false,
  keys: false,
  appKeys: [],
  mac: false,
  highlight: 'purple',
  placeholder: '',
  bottom: 0,
  files: {},
  head: { date: '', above: [], below: [] },
  keyboard: true,
};

window.__sent = [];

/// Sends [message] to the app: through the app's `relayBridge` channel, else to the frame's parent.
function send(message) {
  window.__sent.push(message);
  if (window.__sent.length > 500) window.__sent.splice(0, 250);
  if (window.relayBridge?.postMessage) window.relayBridge.postMessage(JSON.stringify(message));
  else if (window.parent !== window) window.parent.postMessage({ relay: message }, '*');
}

/// Runs [run] at the next frame, or soon when the page draws no frames, such as while it waits off screen.
function nextFrame(run) {
  let done = false;
  const once = () => { if (!done) { done = true; run(); } };
  requestAnimationFrame(once);
  setTimeout(once, 100);
}

const tap = (id, action, value) => send(value === undefined ? { is: 'tap', id, action } : { is: 'tap', id, action, value });

// --- Node views -----------------------------------------------------------------------------------------------------

const itemViews = new Set();

/// A list item: its mark (a dot, a dash, a number or a round circle), then its lines.
class ItemView {
  constructor(node, view, getPos) {
    this.node = node;
    this.view = view;
    this.getPos = getPos;
    this.dom = document.createElement('div');
    this.dom.className = 'item';
    this.mark = document.createElement('span');
    this.mark.className = 'mark';
    this.mark.contentEditable = 'false';
    this.contentDOM = document.createElement('div');
    this.contentDOM.className = 'words';
    this.dom.append(this.mark, this.contentDOM);
    // A tap on a circle ticks it and leaves the caret and the keyboard where they are.
    this.mark.addEventListener('pointerdown', event => event.preventDefault());
    this.mark.addEventListener('mousedown', event => event.preventDefault());
    this.mark.addEventListener('click', event => {
      event.preventDefault();
      event.stopPropagation();
      if (this.node.attrs.kind !== 'task' || !page.editable) return;
      const pos = this.getPos();
      if (typeof pos !== 'number') return;
      this.view.dispatch(this.view.state.tr.setNodeMarkup(pos, null, { ...this.node.attrs, checked: !this.node.attrs.checked }));
    });
    itemViews.add(this);
    this.draw(node);
  }

  draw(node) {
    const { kind, checked, indent } = node.attrs;
    this.dom.dataset.kind = kind;
    this.dom.toggleAttribute('data-checked', !!checked);
    this.dom.style.setProperty('--indent', String(indent));
    let n = 1;
    if (kind === 'numbered') {
      const pos = this.getPos();
      n = (typeof pos === 'number' && lookKey.getState(this.view.state)?.numbers.get(pos)) || 1;
    }
    const look = `${kind}|${checked}|${n}`;
    if (this.look === look) return;
    this.look = look;
    if (kind === 'task') {
      this.mark.innerHTML = `<span class="circle" role="checkbox" aria-checked="${!!checked}" aria-label="${checked ? 'Ticked' : 'Not ticked'}">`
        + '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 12.5l3.2 3.2L17 9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>';
    } else {
      this.mark.textContent = kind === 'numbered' ? `${n}.` : kind === 'dashed' ? '–' : '•';
    }
  }

  update(node) {
    if (node.type !== this.node.type) return false;
    this.node = node;
    this.draw(node);
    return true;
  }

  stopEvent(event) { return this.mark.contains(event.target); }

  destroy() { itemViews.delete(this); }

  ignoreMutation(mutation) {
    if (mutation.type === 'selection') return false;
    return !this.contentDOM.contains(mutation.target) || mutation.target === this.contentDOM && mutation.type === 'attributes';
  }
}

const fileViews = new Set();

/// A file at its place in the words, drawn from the files the app sent.
class FileView {
  constructor(node) {
    this.node = node;
    this.dom = document.createElement('div');
    this.dom.className = 'attachment';
    this.dom.contentEditable = 'false';
    this.inner = document.createElement('div');
    this.inner.className = 'block';
    this.dom.append(this.inner);
    fileViews.add(this);
    this.draw();
  }

  draw() {
    const { id } = this.node.attrs;
    const view = page.files[id];
    drawCard(this.inner, id, view, tap);
    this.dom.classList.toggle('missing', !view);
    this.dom.dataset.attachment = id;
  }

  update(node) {
    if (node.type !== this.node.type) return false;
    this.node = node;
    this.draw();
    return true;
  }

  selectNode() { this.dom.classList.add('picked'); }
  deselectNode() { this.dom.classList.remove('picked'); }
  stopEvent(event) { return !event.type.startsWith('drag') && event.type !== 'drop'; }
  ignoreMutation() { return true; }
  destroy() { fileViews.delete(this); }
}

// --- Keys and typed marks -------------------------------------------------------------------------------------------

const inCell = $pos => {
  for (let d = $pos.depth; d > 0; d--) if ($pos.node(d).type.spec.tableRole?.includes('cell')) return d;
  return 0;
};

/// The cell below the caret in a table, with a new row from the last one.
function cellBelow(view) {
  let state = view.state;
  const depth = inCell(state.selection.$from);
  if (!depth) return false;
  const $from = state.selection.$from;
  const tablePos = $from.before(depth - 2);
  let map = TableMap.get($from.node(depth - 2));
  const rect = map.findCell($from.before(depth) - tablePos - 1);
  if (rect.bottom >= map.height) {
    addRowAfter(state, view.dispatch);
    state = view.state;
    map = TableMap.get(state.doc.nodeAt(tablePos));
  }
  const cellPos = tablePos + 1 + map.map[rect.bottom * map.width + rect.left];
  const cell = state.doc.nodeAt(cellPos);
  view.dispatch(state.tr.setSelection(TextSelection.create(state.doc, cellPos + 2 + cell.firstChild.content.size)).scrollIntoView());
  return true;
}

/// The next or the last cell, with the caret at the end of its words; Tab in the last cell adds a row.
function nextCell(view, direction) {
  const moved = () => {
    const state = view.state;
    view.dispatch(state.tr.setSelection(TextSelection.create(state.doc, state.selection.to)).scrollIntoView());
    return true;
  };
  if (goToNextCell(direction)(view.state, view.dispatch)) return moved();
  if (direction > 0 && addRowAfter(view.state, view.dispatch) && goToNextCell(1)(view.state, view.dispatch)) return moved();
  return true;
}

function enter(view, shift) {
  const { state } = view;
  const selection = state.selection;
  if (selection instanceof NodeSelection || selection instanceof AllSelection) return false;
  const $start = selection.$from;
  if ($start.parent.type.name === 'codeBlock') return false;
  if (inCell($start)) return cellBelow(view);
  const tr = state.tr;
  if (!selection.empty) tr.deleteSelection();
  const $at = tr.selection.$from;
  if (!$at.parent.isTextblock) return false;
  const marks = state.storedMarks || ($at.parentOffset && $at.marks());
  if ($at.depth >= 2 && $at.node(1).type.name === 'item') {
    const item = $at.node(1);
    if (shift) {
      tr.split($at.pos, 1, [{ type: state.schema.nodes.paragraph, attrs: { indent: 0 } }]);
      tr.setSelection(TextSelection.create(tr.doc, $at.pos + 2));
    } else if (item.childCount === 1 && item.content.size === 2) {
      // Return in an empty item ends the list.
      unwrapItem(tr, $at.before(1));
    } else {
      tr.split($at.pos, 2, [{ type: item.type, attrs: { ...item.attrs, checked: false } },
        { type: state.schema.nodes.paragraph, attrs: { indent: 0 } }]);
      tr.setSelection(TextSelection.create(tr.doc, $at.pos + 4));
    }
  } else if ($at.depth === 1) {
    const block = $at.parent;
    const name = block.type.name;
    if (name === 'blockquote' && block.content.size === 0) {
      tr.setNodeMarkup($at.before(1), state.schema.nodes.paragraph, { indent: block.attrs.indent });
    } else {
      const atEnd = $at.parentOffset === block.content.size;
      const after = name === 'heading' && atEnd ? { type: state.schema.nodes.paragraph, attrs: { indent: block.attrs.indent } }
        : name === 'heading' ? { type: block.type, attrs: { ...block.attrs, title: false } }
        : { type: block.type, attrs: block.attrs };
      tr.split($at.pos, 1, [after]);
      tr.setSelection(TextSelection.create(tr.doc, $at.pos + 2));
    }
  } else return false;
  if (marks) tr.ensureMarks(marks);
  view.dispatch(tr.scrollIntoView());
  return true;
}

function backspace(view) {
  const { state } = view;
  const $cursor = state.selection.$cursor;
  if (!$cursor || $cursor.parentOffset > 0) return false;
  const tr = state.tr;
  if ($cursor.depth === 2 && $cursor.node(1).type.name === 'item' && $cursor.index(1) === 0) {
    // At the start of an item's words: the item becomes lines of words.
    unwrapItem(tr, $cursor.before(1));
    view.dispatch(tr.scrollIntoView());
    return true;
  }
  if ($cursor.depth === 1 && $cursor.index(0) > 0) {
    const before = state.doc.child($cursor.index(0) - 1);
    if (before.type.name !== 'item') return false;
    // A line under an item joins the item's last line.
    const block = $cursor.parent;
    const blockPos = $cursor.before(1);
    const end = blockPos - 2;
    const content = block.type.name === 'codeBlock'
      ? (block.textContent ? Fragment.from(state.schema.text(block.textContent.replace(/\n/g, ' '))) : Fragment.empty)
      : block.content;
    tr.delete(blockPos, blockPos + block.nodeSize);
    tr.insert(end, content);
    tr.setSelection(TextSelection.create(tr.doc, end));
    view.dispatch(tr.scrollIntoView());
    return true;
  }
  return false;
}

function tab(view, step) {
  if (inCell(view.state.selection.$from)) return nextCell(view, step);
  const tr = indentLines(view.state, step);
  if (tr.docChanged) view.dispatch(tr);
  return true;
}

const NoteKeys = Extension.create({
  name: 'noteKeys',
  priority: 1000,
  addKeyboardShortcuts() {
    const view = () => this.editor.view;
    return {
      Enter: () => enter(view(), false),
      'Shift-Enter': () => enter(view(), true),
      Backspace: () => backspace(view()),
      Tab: () => tab(view(), 1),
      'Shift-Tab': () => tab(view(), -1),
      'Mod-z': () => undo(),
      'Mod-я': () => undo(),
    };
  },
});

// The marks typed at the start of a line, and the line each makes.
const typedMarks = [
  [/^(#{1,3}) $/, match => `header${match[1].length}`],
  [/^- $/, () => 'dashed'],
  [/^\* $/, () => 'bullet'],
  [/^1\. $/, () => 'numbered'],
  [/^\[ ?\] $/, () => 'unchecked'],
  [/^> $/, () => 'quote'],
];

const NoteRules = Extension.create({
  name: 'noteRules',
  addInputRules() {
    return typedMarks.map(([find, kindOfMatch]) => new InputRule({
      find,
      handler: ({ state, range, match }) => {
        const tr = state.tr;
        const $from = tr.doc.resolve(range.from);
        const topLine = $from.depth === 1;
        const firstOfItem = $from.depth === 2 && $from.node(1).type.name === 'item' && $from.index(1) === 0;
        if (!(topLine || firstOfItem) || inCell($from)) return null;
        const pos = $from.before(1);
        tr.delete(range.from, range.to);
        setLineKind(tr, pos, kindOfMatch(match));
        const $line = tr.doc.resolve(Math.min(pos + 1, tr.doc.content.size));
        tr.setSelection(TextSelection.near(tr.doc.resolve($line.pos + (tr.doc.nodeAt(pos)?.type.name === 'item' ? 1 : 0))));
        return undefined;
      },
    }));
  },
});

const NotePlugins = Extension.create({
  name: 'notePlugins',
  addProseMirrorPlugins: () => [
    lookPlugin(() => page.placeholder),
    findPlugin(),
    keepFilesPlugin(() => page.fromElsewhere),
    tidyPlugin(),
  ],
});

// --- The editor -----------------------------------------------------------------------------------------------------

let pasteId = 0;
let waitingPaste = 0;

/// The note's own copy, pasted back: the files the note does not have stay out.
function withoutUnknownFiles(fragment) {
  const kept = [];
  fragment.forEach(node => {
    if (node.type.name === 'attachment' && !(node.attrs.id in page.files)) return;
    kept.push(node.isLeaf ? node : node.copy(withoutUnknownFiles(node.content)));
  });
  return Fragment.from(kept);
}

const editorProps = {
  attributes: {
    class: 'note', spellcheck: 'true', autocapitalize: 'sentences', autocorrect: 'on', role: 'textbox',
    'aria-multiline': 'true', 'aria-label': 'Note',
  },
  scrollMargin: { top: 16, bottom: 16, left: 0, right: 0 },
  scrollThreshold: { top: 16, bottom: 16, left: 0, right: 0 },
  handlePaste(view, event) {
    const data = event.clipboardData;
    if (!data) return false;
    const html = data.getData('text/html') || '';
    const text = data.getData('text/plain') || '';
    const $from = view.state.selection.$from;
    if ($from.parent.type.name === 'codeBlock') {
      view.dispatch(view.state.tr.insertText(text.replace(/\r\n?/g, '\n')).scrollIntoView());
      return true;
    }
    if (inCell($from)) {
      view.dispatch(view.state.tr.insertText(text.replace(/\s+/g, ' ').trim()).scrollIntoView());
      return true;
    }
    if (html.includes('data-pm-slice')) return false;
    if (!html.trim() && !text) {
      if (data.files?.length) dropFiles(data.files);
      return true;
    }
    waitingPaste = ++pasteId;
    send({ is: 'paste', id: waitingPaste, html, text });
    return true;
  },
  transformPasted: slice => new Slice(withoutUnknownFiles(slice.content), slice.openStart, slice.openEnd),
  handleTripleClick(view, pos) {
    const $pos = view.state.doc.resolve(pos);
    let depth = $pos.depth;
    while (depth > 0 && !$pos.node(depth).isTextblock) depth--;
    const node = $pos.node(depth);
    if (!node.isTextblock) return false;
    const start = $pos.start(depth);
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, start, start + node.content.size)));
    return true;
  },
  handleDOMEvents: {
    // The page's own format tools style the words; the browser's own does not.
    beforeinput: (_, event) => {
      if (event.inputType?.startsWith('format')) { event.preventDefault(); return true; }
      return false;
    },
    blur: () => { setTimeout(quietLinks, 0); return false; },
  },
};

const editor = new Editor({
  element: document.getElementById('note'),
  extensions: [
    ...schemaExtensions.map(extension => extension === Item
      ? Item.extend({ addNodeView: () => ({ node, view, getPos }) => new ItemView(node, view, getPos) })
      : extension === Attachment ? Attachment.extend({ addNodeView: () => ({ node }) => new FileView(node) }) : extension),
    UndoRedo.configure({ depth: 500, newGroupDelay: 1000 }),
    NoteKeys,
    NoteRules,
    NotePlugins,
  ],
  content: { type: 'doc', content: [{ type: 'paragraph' }] },
  editable: false,
  injectCSS: false,
  enablePasteRules: false,
  editorProps,
});
window.editor = editor;
const view = editor.view;
const schema = editor.schema;

function undo() {
  if (editor.commands.undoInputRule()) return true;
  return editor.commands.undo();
}

/// Gives web addresses their links, quietly.
function quietLinks() {
  const tr = autoLinks(view.state);
  if (tr) view.dispatch(tr);
}

// --- Reading and editing --------------------------------------------------------------------------------------------

let placed = false;

function setEditing(on) {
  if (on && !page.editable) on = false;
  if (editor.isEditable !== on) editor.setEditable(on, false);
  keyboardAttribute();
  sendState();
}

function keyboardAttribute() {
  if (page.keyboard) view.dom.removeAttribute('inputmode');
  else view.dom.setAttribute('inputmode', 'none');
}

/// Editing at [selection], with the keyboard.
function startEditing(selection) {
  setEditing(true);
  if (selection) view.dispatch(view.state.tr.setSelection(selection));
  placed = true;
  view.focus();
  sendState();
}

function startReading() {
  setEditing(false);
  view.dom.blur();
  window.getSelection()?.removeAllRanges();
  quietLinks();
  sendState();
}

const endOf = doc => TextSelection.atEnd(doc);

function reveal() {
  const { head } = view.state.selection;
  let box;
  try { box = view.coordsAtPos(head); } catch { return; }
  const room = window.innerHeight - page.bottom - 16;
  if (box.bottom > room) window.scrollBy(0, box.bottom - room);
  else if (box.top < 16) window.scrollBy(0, box.top - 16);
}

document.addEventListener('click', event => {
  const target = event.target instanceof Element ? event.target : event.target?.parentElement;
  if (!target) return;
  const link = target.closest('a[href]');
  if (link) event.preventDefault();
  if (target.closest('.attachment, #head, #below, .mark')) return;
  if (editor.isEditable) return;
  if (link && view.dom.contains(link)) {
    send({ is: 'open', address: link.getAttribute('href') });
    return;
  }
  if (!page.editable) {
    send({ is: 'tap', action: 'words' });
    return;
  }
  const at = view.posAtCoords({ left: event.clientX, top: event.clientY });
  const doc = view.state.doc;
  const selection = at && view.dom.contains(target) ? TextSelection.near(doc.resolve(at.pos)) : endOf(doc);
  startEditing(selection);
});

// Files dropped on the page join the note through the app.
function dropFiles(list) {
  const files = [...list];
  Promise.all(files.map(file => new Promise(resolve => {
    const reader = new FileReader();
    reader.onload = () => resolve({ name: file.name, size: file.size, data: String(reader.result).replace(/^data:[^,]*,/, '') });
    reader.onerror = () => resolve(null);
    reader.readAsDataURL(file);
  }))).then(read => {
    const sent = read.filter(Boolean);
    if (sent.length) send({ is: 'drop', files: sent });
  });
}

const hasFiles = event => [...(event.dataTransfer?.types ?? [])].includes('Files');
document.addEventListener('dragover', event => { if (hasFiles(event)) event.preventDefault(); }, true);
document.addEventListener('drop', event => {
  if (!hasFiles(event)) return;
  event.preventDefault();
  event.stopPropagation();
  dropFiles(event.dataTransfer.files);
}, true);

// --- Keys -----------------------------------------------------------------------------------------------------------

/// The format keys, by key code, with Shift and Alt: as Notes on a Mac has them.
const formatKeys = {
  'KeyB': ['bold'], 'KeyI': ['italic'], 'KeyU': ['underline'],
  'Shift+KeyX': ['strike'], 'Shift+KeyE': ['highlight'],
  'Shift+KeyT': ['line', 'title'], 'Shift+KeyH': ['line', 'heading'], 'Shift+KeyJ': ['line', 'subheading'],
  'Shift+KeyB': ['line', 'body'], 'Shift+KeyM': ['line', 'monostyled'],
  'Shift+Digit7': ['list', 'bullet'], 'Shift+Digit8': ['list', 'dashed'], 'Shift+Digit9': ['list', 'numbered'],
  'Shift+KeyL': ['checklist'], 'Shift+KeyU': ['tick'],
  'Quote': ['quote'], 'BracketRight': ['indent', 1], 'BracketLeft': ['indent', -1],
  'Alt+Digit1': ['line', 'title'], 'Alt+Digit2': ['line', 'heading'], 'Alt+Digit3': ['line', 'subheading'],
  'Alt+Digit0': ['line', 'body'],
  'KeyK': ['keys', 'link'], 'Alt+KeyT': ['keys', 'table'],
};

const appKeys = { 'Alt+KeyN': 'new-note', 'KeyF': 'find', 'Shift+Backspace': 'delete-note' };

document.addEventListener('keydown', event => {
  const mod = page.mac ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
  if (!mod) return;
  // Off a Mac, AltGr comes as Ctrl and Alt: a letter typed with it styles nothing.
  if (!page.mac && event.getModifierState?.('AltGraph')) return;
  const name = `${event.shiftKey ? 'Shift+' : ''}${event.altKey ? 'Alt+' : ''}${event.code}`;
  const consume = () => { event.preventDefault(); event.stopPropagation(); };
  const app = appKeys[name];
  if (app) {
    if (page.appKeys.includes(app)) { consume(); send({ is: 'keys', shortcut: app }); }
    return;
  }
  const format = page.keys && formatKeys[name];
  if (!format) return;
  consume();
  const [action, value] = format;
  if (action === 'keys') { send({ is: 'keys', shortcut: value }); return; }
  if (!editor.isEditable) return;
  run({ action, value: action === 'highlight' ? page.highlight : value });
}, true);

// --- What the format tools light ------------------------------------------------------------------------------------

/// Whether every letter of the selection has a mark of [type], and that mark when they all share one.
function markEverywhere(state, type) {
  const { from, to } = state.selection;
  let all = true;
  let shared;
  let letters = 0;
  state.doc.nodesBetween(from, to, (node, pos, parent) => {
    if (!node.isText || !parent.type.allowsMarkType(type)) return;
    const start = Math.max(from, pos), end = Math.min(to, pos + node.nodeSize);
    if (start >= end) return;
    letters++;
    const mark = type.isInSet(node.marks);
    if (!mark) { all = false; return; }
    if (shared === undefined) shared = mark;
    else if (shared && !shared.eq(mark)) shared = null;
  });
  return letters > 0 && all ? (shared ?? null) || true : false;
}

function marksAtCursor(state) {
  return state.storedMarks || state.selection.$from.marks();
}

function markState(state) {
  const selection = state.selection;
  const names = ['bold', 'italic', 'underline', 'strike'];
  const highlight = state.schema.marks.highlight;
  if (selection.empty) {
    const marks = marksAtCursor(state);
    const hl = highlight.isInSet(marks);
    return { marks: names.filter(name => state.schema.marks[name].isInSet(marks)), highlight: hl ? hl.attrs.colour : null };
  }
  const hl = markEverywhere(state, highlight);
  return {
    marks: names.filter(name => markEverywhere(state, state.schema.marks[name])),
    highlight: hl && hl !== true ? hl.attrs.colour : null,
  };
}

function linkState(state) {
  const type = state.schema.marks.link;
  const { selection } = state;
  if (selection.empty) {
    const $from = selection.$from;
    const mark = type.isInSet($from.nodeBefore?.marks ?? []) ?? type.isInSet($from.nodeAfter?.marks ?? []);
    return mark ? mark.attrs.href : null;
  }
  let href = null;
  state.doc.nodesBetween(selection.from, selection.to, node => {
    const mark = node.isText && type.isInSet(node.marks);
    if (mark && href === null) href = mark.attrs.href;
  });
  return href;
}

let lastState = '';

function sendState() {
  const state = view.state;
  const { selection } = state;
  const find = findKey.getState(state);
  const message = {
    is: 'state',
    ...markState(state),
    link: linkState(state),
    kind: selection instanceof NodeSelection ? kindOf(selection.node) : headKind(state),
    inTable: isInTable(state),
    canUndo: undoDepth(state) > 0,
    canRedo: redoDepth(state) > 0,
    // The page's own focus too: in WebKit the words keep the active element while a field of the app, such as Find
    // in Note's, has the keyboard.
    focus: view.hasFocus() && document.hasFocus(),
    editing: editor.isEditable,
    empty: selection.empty,
    found: find.query ? { count: find.matches.length, index: find.matches.length ? find.index : -1 } : null,
  };
  const text = JSON.stringify(message);
  if (text === lastState) return;
  lastState = text;
  send(message);
}

// --- Changes --------------------------------------------------------------------------------------------------------

let changed = false;
let changedQuiet = true;

editor.on('transaction', ({ transaction, appendedTransactions }) => {
  const docChanged = transaction.docChanged || appendedTransactions.some(tr => tr.docChanged);
  if (docChanged && !transaction.getMeta('load')) {
    if (!changed) nextFrame(flushChanged);
    changed = true;
    changedQuiet = changedQuiet && !!transaction.getMeta('quiet');
  }
  if (transaction.selectionSet && !transaction.getMeta('load')) placed = true;
  scheduleState();
  renumber();
  if (view.hasFocus() && (transaction.selectionSet || docChanged)) nextFrame(reveal);
});

let numbersDrawn = 0;

/// Each numbered item draws its number again when a number changed.
function renumber() {
  const { version } = lookKey.getState(view.state);
  if (version === numbersDrawn) return;
  numbersDrawn = version;
  for (const itemView of itemViews) if (itemView.node.attrs.kind === 'numbered') itemView.draw(itemView.node);
}
editor.on('focus', () => sendState());
editor.on('blur', () => sendState());
window.addEventListener('focus', () => sendState());
window.addEventListener('blur', () => sendState());

function flushChanged() {
  if (!changed) return;
  const quiet = changedQuiet;
  changed = false;
  changedQuiet = true;
  send(quiet ? { is: 'changed', doc: editor.getJSON(), quiet: true } : { is: 'changed', doc: editor.getJSON() });
}

let stateWaiting = false;
function scheduleState() {
  if (stateWaiting) return;
  stateWaiting = true;
  queueMicrotask(() => { stateWaiting = false; sendState(); });
}

// --- The app's runs -------------------------------------------------------------------------------------------------

const dispatch = tr => { if (tr && (tr.docChanged || tr.selectionSet || tr.storedMarksSet)) view.dispatch(tr); };

function toggleMark(name) {
  const state = view.state;
  const type = state.schema.marks[name];
  if (inCell(state.selection.$from)) return;
  if (state.selection.empty) {
    const has = type.isInSet(marksAtCursor(state));
    dispatch(has ? state.tr.removeStoredMark(type) : state.tr.addStoredMark(type.create()));
    return;
  }
  const everywhere = markEverywhere(state, type);
  const tr = state.tr;
  for (const range of state.selection.ranges) {
    if (everywhere) tr.removeMark(range.$from.pos, range.$to.pos, type);
    else tr.addMark(range.$from.pos, range.$to.pos, type.create());
  }
  dispatch(tr);
}

function setHighlight(colour) {
  const state = view.state;
  const type = state.schema.marks.highlight;
  if (state.selection.empty) {
    const tr = state.tr.removeStoredMark(type);
    if (colour) tr.addStoredMark(type.create({ colour }));
    dispatch(tr);
    return;
  }
  const { from, to } = state.selection;
  const tr = state.tr.removeMark(from, to, type);
  if (colour) tr.addMark(from, to, type.create({ colour }));
  dispatch(tr);
}

function setLink(href) {
  const state = view.state;
  const type = state.schema.marks.link;
  const { selection } = state;
  const tr = state.tr;
  if (selection.empty) {
    const range = getMarkRange(selection.$from, type);
    if (range) {
      tr.removeMark(range.from, range.to, type);
      if (href) tr.addMark(range.from, range.to, type.create({ href, auto: false }));
    } else if (href) {
      const marks = marksAtCursor(state).filter(mark => mark.type !== type);
      tr.insert(selection.from, state.schema.text(href, [...marks, type.create({ href, auto: false })]));
    }
  } else {
    tr.removeMark(selection.from, selection.to, type);
    if (href) tr.addMark(selection.from, selection.to, type.create({ href, auto: false }));
  }
  dispatch(tr);
}

function insertTable() {
  const state = view.state;
  const { nodes } = state.schema;
  const cell = (type) => type.create(null, nodes.paragraph.create());
  const table = nodes.table.create(null, [
    nodes.tableRow.create(null, [cell(nodes.tableHeader), cell(nodes.tableHeader)]),
    nodes.tableRow.create(null, [cell(nodes.tableCell), cell(nodes.tableCell)]),
  ]);
  const tr = state.tr;
  if (!state.selection.empty && !(state.selection instanceof NodeSelection)) tr.deleteSelection();
  const selection = tr.selection;
  const $at = selection.$from;
  let at;
  if (!(selection instanceof NodeSelection) && $at.parent.isTextblock && $at.depth >= 1 && !inCell($at)) {
    // In an item, its first or last line; else the line itself.
    const first = $at.depth === 1 || $at.index(1) === 0;
    const last = $at.depth === 1 || $at.index(1) === $at.node(1).childCount - 1;
    if ($at.parentOffset === 0 && first) {
      at = $at.before(1);
    } else if ($at.parentOffset === $at.parent.content.size && last) {
      // At the end of a line: the table goes under it.
      at = $at.after(1);
    } else {
      const depth = $at.depth;
      tr.split($at.pos, depth);
      at = $at.pos + depth;
    }
  } else {
    const $top = tr.doc.resolve(selection.to);
    at = $top.depth ? $top.after(1) : selection.to;
  }
  tr.insert(at, table);
  if (at + table.nodeSize >= tr.doc.content.size) tr.insert(tr.doc.content.size, nodes.paragraph.create());
  tr.setSelection(TextSelection.create(tr.doc, at + 4));
  view.dispatch(tr.scrollIntoView());
}

function tableAt(state) {
  const $from = state.selection.$from;
  for (let d = $from.depth; d > 0; d--) {
    if ($from.node(d).type.name === 'table') return { node: $from.node(d), pos: $from.before(d) };
  }
  if (state.selection instanceof NodeSelection && state.selection.node.type.name === 'table') {
    return { node: state.selection.node, pos: state.selection.from };
  }
  return null;
}

function convertTable() {
  const table = tableAt(view.state);
  if (!table) return;
  const { nodes } = view.state.schema;
  const lines = [];
  table.node.forEach(row => {
    const cells = [];
    row.forEach(cell => cells.push(cell.textContent));
    const text = cells.join('\t');
    lines.push(nodes.paragraph.create(null, text ? view.state.schema.text(text) : null));
  });
  const tr = view.state.tr.replaceWith(table.pos, table.pos + table.node.nodeSize, lines);
  tr.setSelection(TextSelection.create(tr.doc, table.pos + 1));
  view.dispatch(tr.scrollIntoView());
}

function deleteTable() {
  const table = tableAt(view.state);
  if (!table) return;
  const tr = view.state.tr;
  const last = table.pos + table.node.nodeSize >= tr.doc.content.size;
  if (last) tr.replaceWith(table.pos, table.pos + table.node.nodeSize, schema.nodes.paragraph.create());
  else tr.delete(table.pos, table.pos + table.node.nodeSize);
  caretAt(tr, last ? table.pos + 1 : table.pos);
  view.dispatch(tr.scrollIntoView());
}

function tableCount(state) {
  const table = tableAt(state);
  if (!table) return null;
  const map = TableMap.get(table.node);
  return { rows: map.height, columns: map.width };
}

function attach({ files = [], at = 'end', quiet = false } = {}) {
  if (!files.length) return;
  const state = view.state;
  const { doc } = state;
  const placed = files.map(file => schema.nodes.attachment.create({ id: file.id, name: file.name ?? '' }));
  const tr = state.tr;
  let index = -1;
  if (at === 'cursor') {
    const $head = state.selection.$head;
    index = $head.depth ? $head.index(0) : Math.min($head.index(0), doc.childCount - 1);
  }
  const from = index < 0 ? doc.childCount - 1 : index;
  const line = doc.child(from);
  const empty = (line.isTextblock || line.type.name === 'item') && line.textContent === '' && line.type.name !== 'codeBlock'
    ? true : line.isTextblock && line.content.size === 0;
  let posOf = i => { let pos = 0; for (let k = 0; k < i; k++) pos += doc.child(k).nodeSize; return pos; };
  let caret;
  if (empty || (index >= 0 && from < doc.childCount - 1)) {
    const to = empty ? from : from + 1;
    const pos = posOf(to);
    tr.insert(pos, placed);
    caret = pos + placed.reduce((sum, node) => sum + node.nodeSize, 0);
  } else {
    const pos = doc.content.size;
    tr.insert(pos, [...placed, schema.nodes.paragraph.create()]);
    caret = tr.doc.content.size - 2;
  }
  if (at === 'cursor') tr.setSelection(TextSelection.near(tr.doc.resolve(caret + (tr.doc.nodeAt(caret)?.type.name === 'item' ? 2 : 1))));
  if (quiet) tr.setMeta('addToHistory', false).setMeta('quiet', true);
  view.dispatch(tr.scrollIntoView());
}

function detach({ ids = [], quiet = false } = {}) {
  const gone = new Set(ids);
  const state = view.state;
  const tr = state.tr;
  const found = [];
  state.doc.forEach((node, pos) => { if (node.type.name === 'attachment' && gone.has(node.attrs.id)) found.push({ node, pos }); });
  if (!found.length) return;
  for (const { node, pos } of found.reverse()) tr.delete(pos, pos + node.nodeSize);
  if (tr.doc.childCount === 0) tr.insert(0, schema.nodes.paragraph.create());
  if (quiet) tr.setMeta('addToHistory', false).setMeta('quiet', true);
  view.dispatch(tr);
}

function find(query) {
  view.dispatch(view.state.tr.setMeta(findKey, { query: query ?? '' }));
  const { matches } = findKey.getState(view.state);
  if (matches.length) {
    view.dispatch(selectMatch(view.state, 0));
    revealMatch();
  }
}

function findStep(step) {
  const { matches, index } = findKey.getState(view.state);
  if (!matches.length) return;
  view.dispatch(selectMatch(view.state, (index + step + matches.length) % matches.length));
  revealMatch();
}

function revealMatch() {
  const { matches, index } = findKey.getState(view.state);
  const match = matches[index];
  if (!match) return;
  try {
    const box = view.coordsAtPos(match.from);
    const room = window.innerHeight - page.bottom;
    if (box.top < 60 || box.bottom > room - 16) window.scrollBy(0, box.top - room / 3);
  } catch { /* off the page */ }
}

function closeFind() {
  const { matches, index } = findKey.getState(view.state);
  const match = matches[index];
  const tr = view.state.tr.setMeta(findKey, { query: '' });
  if (match) tr.setSelection(TextSelection.create(tr.doc, match.to));
  view.dispatch(tr);
  startReading();
}

// The runs that are a step of their own for Undo, apart from the typing before and after them.
const ownSteps = new Set(['bold', 'italic', 'underline', 'strike', 'highlight', 'recolour', 'link', 'line', 'list', 'checklist',
  'tick', 'quote', 'indent', 'table', 'table-convert', 'table-delete', 'row-above', 'row-below', 'row-delete',
  'column-before', 'column-after', 'column-delete', 'attach', 'detach', 'focus']);

const closeStep = () => view.dispatch(closeHistory(view.state.tr));

function run(message) {
  if (!ownSteps.has(message.action)) { runOne(message); return; }
  closeStep();
  runOne(message);
  closeStep();
}

function runOne({ action, value }) {
  const state = view.state;
  switch (action) {
    case 'bold': case 'italic': case 'underline': case 'strike': toggleMark(action); break;
    case 'highlight': setHighlight(markState(state).highlight ? null : value || page.highlight); break;
    case 'recolour': if (markState(state).highlight && value) setHighlight(value); break;
    case 'link': setLink(value || null); break;
    case 'line': dispatch(lineStyle(state, value)); break;
    case 'list': dispatch(listOf(state, value)); break;
    case 'checklist': dispatch(listOf(state, 'task')); break;
    case 'tick': dispatch(tick(state)); break;
    case 'quote': dispatch(quote(state)); break;
    case 'indent': dispatch(indentLines(state, value < 0 ? -1 : 1)); break;
    case 'table': insertTable(); break;
    case 'table-convert': convertTable(); break;
    case 'table-delete': deleteTable(); break;
    case 'row-above': addRowBefore(state, view.dispatch); break;
    case 'row-below': addRowAfter(state, view.dispatch); break;
    case 'row-delete': if ((tableCount(state)?.rows ?? 0) > 1) deleteRow(state, view.dispatch); break;
    case 'column-before': addColumnBefore(state, view.dispatch); break;
    case 'column-after': addColumnAfter(state, view.dispatch); break;
    case 'column-delete': if ((tableCount(state)?.columns ?? 0) > 1) deleteColumn(state, view.dispatch); break;
    case 'undo': undo(); break;
    case 'redo': editor.commands.redo(); break;
    case 'select-all': view.dispatch(state.tr.setSelection(new AllSelection(state.doc))); break;
    // The browser's own clipboard steps, where it allows them; the Mac's web view does these in the app.
    case 'cut': case 'copy': case 'paste': document.execCommand(action); break;
    case 'find': find(value); break;
    case 'find-step': findStep(value < 0 ? -1 : 1); break;
    case 'find-close': closeFind(); break;
    case 'attach': attach(value); break;
    case 'detach': detach(value); break;
    case 'focus':
      if (value === 'new-line') {
        // The caret on an empty line at the end: one more line when the last is not an empty line of words.
        const last = view.state.doc.lastChild;
        if (!page.editable) break;
        if (!(last.type.name === 'paragraph' && last.content.size === 0)) {
          view.dispatch(view.state.tr.insert(view.state.doc.content.size, schema.nodes.paragraph.create()));
        }
      }
      startEditing(value === 'end' || value === 'new-line' || !placed ? endOf(view.state.doc) : null);
      break;
    case 'blur': startReading(); break;
    case 'keyboard':
      page.keyboard = value !== false;
      keyboardAttribute();
      if (view.hasFocus()) { view.dom.blur(); view.focus(); }
      break;
    case 'editable':
      page.editable = !!value;
      if (!page.editable) startReading();
      break;
    case 'reveal': reveal(); break;
    case 'placeholder':
      page.placeholder = value ?? '';
      view.dispatch(view.state.tr.setMeta(lookKey, { text: page.placeholder }));
      break;
    default: break;
  }
  sendState();
}

// --- The head: the date and the files above and under the words ----------------------------------------------------

const headCards = new Map();

function drawHead() {
  document.querySelector('#head .date').textContent = page.head.date ?? '';
  const fill = (element, keys) => {
    const wanted = keys ?? [];
    const kept = [];
    for (const key of wanted) {
      let card = headCards.get(key);
      if (!card) { card = document.createElement('div'); card.className = 'block'; headCards.set(key, card); }
      drawCard(card, key, page.files[key], tap);
      kept.push(card);
    }
    element.replaceChildren(...kept);
  };
  fill(document.getElementById('above'), page.head.above);
  fill(document.getElementById('below'), page.head.below);
  for (const key of [...headCards.keys()]) {
    if (!(page.head.above ?? []).includes(key) && !(page.head.below ?? []).includes(key)) headCards.delete(key);
  }
}

function drawFiles() {
  for (const fileView of fileViews) fileView.draw();
  drawHead();
}

/// [colour], a CSS colour such as #0E7A5A or rgba(…), at [alpha] of its own strength; null when it can't be read.
function seeThrough(colour, alpha) {
  const text = String(colour).trim();
  let match = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(text);
  if (match) {
    const n = Number.parseInt(match[1], 16);
    const a = match[2] ? Number.parseInt(match[2], 16) / 255 : 1;
    return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${+(a * alpha).toFixed(3)})`;
  }
  match = /^rgba?\(([^,]+),([^,]+),([^,)]+)(?:,([^)]+))?\)$/i.exec(text);
  if (match) return `rgba(${match[1].trim()}, ${match[2].trim()}, ${match[3].trim()}, ${+((match[4] ? Number(match[4]) : 1) * alpha).toFixed(3)})`;
  return null;
}

// Colours the page makes from the app's own, as WebKit before Safari 16.2 has no color-mix().
const derived = { muted: [['muted35', 0.35], ['muted15', 0.15]], card: [['card60', 0.6]], spark: [['spark35', 0.35], ['spark80', 0.8]] };

function theme(colours) {
  const root = document.documentElement;
  for (const [key, value] of Object.entries(colours ?? {})) {
    if (key === 'scheme') {
      root.style.colorScheme = value;
      root.dataset.scheme = value;
      continue;
    }
    root.style.setProperty(`--${key}`, value);
    for (const [name, alpha] of derived[key] ?? []) {
      const mixed = seeThrough(value, alpha);
      if (mixed) root.style.setProperty(`--${name}`, mixed);
    }
  }
}

function setBottom(bottom) {
  page.bottom = Math.max(0, Number(bottom) || 0);
  document.documentElement.style.setProperty('--bottom', `${page.bottom}px`);
  editorProps.scrollMargin.bottom = page.bottom + 16;
  editorProps.scrollThreshold.bottom = page.bottom + 16;
  view.setProps({ scrollMargin: editorProps.scrollMargin, scrollThreshold: editorProps.scrollThreshold });
  if (view.hasFocus()) nextFrame(reveal);
}

function load(message) {
  const started = performance.now();
  for (const key of ['editable', 'fromElsewhere', 'keys', 'mac', 'highlight', 'placeholder']) {
    if (key in message) page[key] = message[key];
  }
  page.editable = message.editable !== false;
  page.appKeys = Array.isArray(message.appKeys) ? message.appKeys : [];
  page.files = message.files ?? {};
  page.head = { date: '', above: [], below: [], ...(message.head ?? {}) };
  page.keyboard = true;
  theme(message.theme);
  setBottom(message.bottom ?? 0);
  let doc;
  try {
    doc = schema.nodeFromJSON(message.doc ?? { type: 'doc', content: [{ type: 'paragraph' }] });
    doc.check();
  } catch {
    doc = schema.node('doc', null, [schema.nodes.paragraph.create()]);
  }
  waitingPaste = 0;
  editor.setEditable(false, false);
  view.updateState(EditorState.create({ doc, plugins: view.state.plugins, selection: Selection.findFrom(doc.resolve(0), 1, true) ?? Selection.atStart(doc) }));
  const links = autoLinks(view.state);
  if (links) view.dispatch(links.setMeta('load', true));
  renumber();
  changed = false;
  changedQuiet = true;
  placed = false;
  lastState = '';
  drawHead();
  window.scrollTo(0, 0);
  if (message.focus && page.editable) {
    const first = view.state.doc.firstChild;
    startEditing(TextSelection.near(view.state.doc.resolve(first.isTextblock ? first.nodeSize - 1 : 1), -1));
  } else keyboardAttribute();
  nextFrame(() => {
    document.body.classList.add('ready');
    send({ is: 'ready', ms: Math.round(performance.now() - started) });
    sendState();
  });
}

function receive(message) {
  if (typeof message === 'string') message = JSON.parse(message);
  if (!message || typeof message !== 'object') return;
  switch (message.do) {
    case 'load': load(message); break;
    case 'run': run(message); break;
    case 'files': page.files = { ...page.files, ...(message.files ?? {}) }; drawFiles(); break;
    case 'theme': theme(message.theme); break;
    case 'bottom': setBottom(message.bottom); break;
    case 'head': page.head = { ...page.head, ...(message.head ?? {}) }; drawHead(); break;
    case 'highlight': page.highlight = message.colour ?? page.highlight; break;
    case 'appKeys': page.appKeys = Array.isArray(message.appKeys) ? message.appKeys : []; break;
    case 'paste': {
      if (message.id !== waitingPaste) break;
      waitingPaste = 0;
      const blocks = [];
      for (const json of message.blocks ?? []) {
        try { const node = schema.nodeFromJSON(json); node.check(); blocks.push(node); } catch { /* not a block of a note */ }
      }
      const tr = pasteBlocks(view.state, blocks);
      closeStep();
      if (tr) view.dispatch(tr);
      closeStep();
      quietLinks();
      break;
    }
    default: break;
  }
}

window.relayReceive = receive;
window.addEventListener('message', event => {
  if (event.source === window.parent && event.data?.relayDo) receive(event.data.relayDo);
});

send({ is: 'boot' });
