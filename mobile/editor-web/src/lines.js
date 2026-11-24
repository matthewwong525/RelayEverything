// What the format tools do to the lines a selection touches: a line kind, a list, a checklist, a tick, a quote, an
// indent. A line is one top-level block; an item with its lines under it is one line, as in the note's Markdown.
import { TextSelection } from '@tiptap/pm/state';
import { MAX_INDENT, kindOf } from './schema.js';

/// The top-level blocks the selection touches, each with its position, first to last.
export function pickedBlocks(state) {
  const { from, to, empty } = state.selection;
  const blocks = [];
  state.doc.forEach((node, offset) => {
    const end = offset + node.nodeSize;
    if (empty ? offset < from && end > from : offset < to && end > from) blocks.push({ node, pos: offset });
  });
  if (!blocks.length && empty) {
    // A cursor between blocks, such as next to a file: the block after it, else before it.
    const $at = state.doc.resolve(from);
    const index = Math.min($at.index(0), state.doc.childCount - 1);
    let pos = 0;
    for (let i = 0; i < index; i++) pos += state.doc.child(i).nodeSize;
    blocks.push({ node: state.doc.child(index), pos });
  }
  return blocks;
}

/// The top-level block at the selection's head.
export function headBlock(state) {
  const $head = state.selection.$head;
  if ($head.depth === 0) {
    const node = state.selection.node ?? $head.nodeAfter ?? $head.nodeBefore;
    return node ? { node, pos: state.selection.node ? state.selection.from : $head.pos - ($head.nodeAfter ? 0 : node.nodeSize) } : null;
  }
  return { node: $head.node(1), pos: $head.before(1) };
}

/// The kind of the line at the selection's head, as the app names line kinds.
export function headKind(state) {
  const block = headBlock(state);
  return block ? kindOf(block.node) : null;
}

const isLine = node => node.isTextblock || node.type.name === 'item';

/// Splits a code block at [pos] into lines of the same kind at each line break, in place.
function splitAtBreaks(tr, pos) {
  const node = tr.doc.nodeAt(pos);
  const text = node.textContent;
  for (let at = text.lastIndexOf('\n'); at >= 0; at = at === 0 ? -1 : text.lastIndexOf('\n', at - 1)) {
    const where = pos + 1 + at;
    tr.delete(where, where + 1);
    tr.split(where);
  }
}

/// Makes the textblock at [pos] the textblock [type] with [attrs]; a code block's line breaks become lines.
/// Returns the number of blocks it became.
function toTextblock(tr, pos, type, attrs) {
  const node = tr.doc.nodeAt(pos);
  const wasCode = node.type.name === 'codeBlock';
  if (!node.hasMarkup(type, attrs)) tr.setBlockType(pos, pos + node.nodeSize, type, attrs);
  if (wasCode && type.name !== 'codeBlock' && node.textContent.includes('\n')) {
    splitAtBreaks(tr, pos);
    let count = node.textContent.split('\n').length;
    // Each new line takes the same kind and indent.
    let at = pos;
    for (let i = 0; i < count; i++) {
      const line = tr.doc.nodeAt(at);
      if (!line.hasMarkup(type, attrs)) tr.setNodeMarkup(at, type, attrs);
      at += tr.doc.nodeAt(at).nodeSize;
    }
    return count;
  }
  return 1;
}

/// Takes the item at [pos] out of its list: its lines become paragraphs at its indent. Returns their positions' end.
export function unwrapItem(tr, pos) {
  const item = tr.doc.nodeAt(pos);
  const { indent } = item.attrs;
  const $start = tr.doc.resolve(pos + 1);
  const $end = tr.doc.resolve(pos + item.nodeSize - 1);
  tr.lift($start.blockRange($end), 0);
  let at = pos;
  for (let i = 0; i < item.childCount; i++) {
    const line = tr.doc.nodeAt(at);
    tr.setNodeMarkup(at, null, { ...line.attrs, indent });
    at += line.nodeSize;
  }
  return at;
}

/// Sets the block at [pos] to [kind], a line kind name, keeping its words and indent.
export function setLineKind(tr, pos, kind) {
  const schema = tr.doc.type.schema;
  const node = tr.doc.nodeAt(pos);
  if (!node || !isLine(node)) return;
  const indent = node.attrs.indent ?? 0;
  const item = { bullet: 'bullet', dashed: 'dashed', numbered: 'numbered', unchecked: 'task', checked: 'task' }[kind];
  if (item) {
    const attrs = { kind: item, checked: kind === 'checked', indent };
    if (node.type.name === 'item') {
      if (node.attrs.kind !== attrs.kind || node.attrs.checked !== attrs.checked) tr.setNodeMarkup(pos, null, attrs);
      return;
    }
    const count = toTextblock(tr, pos, schema.nodes.paragraph, { indent: 0 });
    let end = pos;
    for (let i = 0; i < count; i++) end += tr.doc.nodeAt(end).nodeSize;
    const range = tr.doc.resolve(pos + 1).blockRange(tr.doc.resolve(end - 1));
    tr.wrap(range, [{ type: schema.nodes.item, attrs }]);
    return;
  }
  const [type, attrs] = {
    paragraph: [schema.nodes.paragraph, { indent }],
    header1: [schema.nodes.heading, { level: 1, indent, title: false }],
    header2: [schema.nodes.heading, { level: 2, indent, title: false }],
    header3: [schema.nodes.heading, { level: 3, indent, title: false }],
    quote: [schema.nodes.blockquote, { indent }],
    code: [schema.nodes.codeBlock, {}],
  }[kind];
  if (node.type.name === 'item') {
    if (type.name === 'codeBlock') {
      const text = [];
      node.forEach(line => text.push(line.textContent));
      const code = schema.nodes.codeBlock.create(null, text.join('\n') ? schema.text(text.join('\n')) : null);
      tr.replaceWith(pos, pos + node.nodeSize, code);
      return;
    }
    const end = unwrapItem(tr, pos);
    for (let at = pos; at < end;) {
      toTextblock(tr, at, type, attrs);
      at += tr.doc.nodeAt(at).nodeSize;
    }
    return;
  }
  if (node.type.name === 'heading' && type.name === 'heading' && node.attrs.level === attrs.level) return;
  toTextblock(tr, pos, type, attrs);
}

/// Each picked line becomes [kind], last first, so the positions above stay true.
export function setKinds(state, kind) {
  const tr = state.tr;
  const blocks = pickedBlocks(state).filter(block => isLine(block.node));
  for (const { pos } of blocks.reverse()) setLineKind(tr, tr.mapping.map(pos), kind);
  return tr;
}

/// Each picked line one indent level in ([step] 1) or out (-1), from 0 to 8.
export function indentLines(state, step) {
  const tr = state.tr;
  for (const { node, pos } of pickedBlocks(state)) {
    if (!('indent' in node.attrs)) continue;
    const level = Math.max(0, Math.min(MAX_INDENT, node.attrs.indent + step));
    if (level !== node.attrs.indent) tr.setNodeMarkup(pos, null, { ...node.attrs, indent: level });
  }
  return tr;
}

/// A line style from the format tools: title, heading, subheading, body, or monostyled, which a second time is body.
export function lineStyle(state, style) {
  if (style === 'monostyled') return setKinds(state, headKind(state) === 'code' ? 'paragraph' : 'code');
  return setKinds(state, { title: 'header1', heading: 'header2', subheading: 'header3' }[style] ?? 'paragraph');
}

/// A list kind on the picked lines; a second time on the same kind takes it off.
export function listOf(state, kind) {
  const now = headKind(state);
  if (kind === 'task') return setKinds(state, now === 'checked' || now === 'unchecked' ? 'paragraph' : 'unchecked');
  return setKinds(state, now === kind ? 'paragraph' : kind);
}

/// *Mark as Ticked*: on a checklist line, each picked line ticked or not, the other way from the head's line.
export function tick(state) {
  const now = headKind(state);
  if (now === 'unchecked') return setKinds(state, 'checked');
  if (now === 'checked') return setKinds(state, 'unchecked');
  return null;
}

export function quote(state) {
  return setKinds(state, headKind(state) === 'quote' ? 'paragraph' : 'quote');
}

/// Puts the caret at [pos] or the nearest place for it.
export function caretAt(tr, pos, bias = 1) {
  const clamped = Math.max(0, Math.min(pos, tr.doc.content.size));
  return tr.setSelection(TextSelection.near(tr.doc.resolve(clamped), bias));
}
