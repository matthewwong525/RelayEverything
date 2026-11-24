// A paste from outside the note, put in by the rules of the app's old pasteInto: test/editor.test.mjs shows each one.
// The app reads the paste into the note's lines; one Undo takes it back.
import { NodeSelection, TextSelection } from '@tiptap/pm/state';

const BR = 'BR';

/// A line's style: its kind name and indent.
function styleOf(node) {
  switch (node.type.name) {
    case 'paragraph': return { kind: 'paragraph', indent: node.attrs.indent };
    case 'heading': return { kind: `header${node.attrs.level}`, indent: node.attrs.indent };
    case 'blockquote': return { kind: 'quote', indent: node.attrs.indent };
    case 'codeBlock': return { kind: 'code', indent: 0 };
    case 'item': return {
      kind: node.attrs.kind === 'task' ? (node.attrs.checked ? 'checked' : 'unchecked') : node.attrs.kind,
      indent: node.attrs.indent,
    };
    default: return null;
  }
}

const plain = style => style && style.kind === 'paragraph' && style.indent === 0;

/// A block as a line: its style and its pieces, words and line breaks. Null for a table or a file.
function lineOf(node) {
  const style = styleOf(node);
  if (!style) return null;
  const parts = [];
  const words = block => block.forEach(child => {
    if (child.isText && node.type.name === 'codeBlock') {
      child.text.split('\n').forEach((text, i) => {
        if (i) parts.push(BR);
        if (text) parts.push(child.type.schema.text(text));
      });
    } else parts.push(child);
  });
  if (node.type.name === 'item') node.forEach((line, _, i) => { if (i) parts.push(BR); words(line); });
  else words(node);
  return { style, parts };
}

const sizeOf = parts => parts.reduce((sum, part) => sum + (part === BR ? 1 : part.nodeSize), 0);

/// The pieces of [parts] from [from] to [to].
function cut(parts, from, to = Infinity) {
  const out = [];
  let at = 0;
  for (const part of parts) {
    const size = part === BR ? 1 : part.nodeSize;
    const start = Math.max(from, at), end = Math.min(to, at + size);
    if (start < end) out.push(part === BR ? BR : start === at && end === at + size ? part : part.cut(start - at, end - at));
    at += size;
  }
  return out;
}

/// The blocks of a line: an item holds its lines; another kind makes a block for each line; code joins them.
function blocksOf(schema, { style, parts }) {
  const lines = [[]];
  for (const part of parts) part === BR ? lines.push([]) : lines.at(-1).push(part);
  const { kind, indent } = style;
  const nodes = schema.nodes;
  const join = line => line.filter(part => part.text).map(part => part.text).join('');
  if (kind === 'code') {
    const text = lines.map(join).join('\n');
    return [nodes.codeBlock.create(null, text ? schema.text(text) : null)];
  }
  const item = { bullet: 'bullet', dashed: 'dashed', numbered: 'numbered', unchecked: 'task', checked: 'task' }[kind];
  if (item) {
    return [nodes.item.create({ kind: item, checked: kind === 'checked', indent },
      lines.map(line => nodes.paragraph.create({ indent: 0 }, line)))];
  }
  const [type, attrs] = {
    paragraph: [nodes.paragraph, { indent }],
    header1: [nodes.heading, { level: 1, indent }],
    header2: [nodes.heading, { level: 2, indent }],
    header3: [nodes.heading, { level: 3, indent }],
    quote: [nodes.blockquote, { indent }],
  }[kind];
  return lines.map(line => type.create(attrs, line));
}

/// The position [offset] letters into [blocks], placed from [start]; a line break between lines counts one.
function positionIn(blocks, start, offset) {
  let pos = start;
  let left = offset;
  for (const block of blocks) {
    const lines = [];
    if (block.type.name === 'item') {
      let at = pos + 1;
      block.forEach(line => { lines.push({ start: at + 1, size: line.content.size }); at += line.nodeSize; });
    } else if (block.isTextblock) lines.push({ start: pos + 1, size: block.content.size });
    for (const line of lines) {
      if (left <= line.size) return line.start + left;
      left -= line.size + 1;
    }
    pos += block.nodeSize;
  }
  return pos;
}

/// A transaction that puts [pasted], the app's top-level blocks, over the selection of [state]; null for none.
export function pasteBlocks(state, pasted) {
  const schema = state.schema;
  const tr = state.tr;
  if (!state.selection.empty) tr.deleteSelection();
  if (!pasted.length) return tr.docChanged ? tr : null;
  const selection = tr.selection;
  const $from = selection.$from;
  if (selection instanceof NodeSelection || $from.depth === 0 || !$from.parent.isTextblock) {
    // At a table or a file: the paste goes on lines of its own after it.
    const after = selection instanceof NodeSelection ? selection.to
      : $from.depth === 0 ? $from.pos : $from.after(1);
    tr.insert(after, pasted);
    const end = after + pasted.reduce((sum, node) => sum + node.nodeSize, 0);
    const last = pasted.at(-1);
    tr.setSelection(last.isTextblock || last.type.name === 'item'
      ? TextSelection.near(tr.doc.resolve(end - (last.type.name === 'item' ? 2 : 1)), -1)
      : TextSelection.near(tr.doc.resolve(end)));
    return tr.scrollIntoView();
  }
  const blockPos = $from.before(1);
  const block = $from.node(1);
  const line = lineOf(block);
  // How far into the line the cursor is: an item's earlier lines count, each with its line break.
  let offset = $from.parentOffset;
  if (block.type.name === 'item') {
    for (let i = 0; i < $from.index(1); i++) offset += block.child(i).content.size + 1;
  }
  const before = cut(line.parts, 0, offset), rest = cut(line.parts, offset);
  const cursorStyle = line.style;
  const wordsBefore = offset > 0;
  const nothingAfter = sizeOf(rest) === 0;
  const pastedLines = pasted.map(node => ({ node, line: lineOf(node) }));
  const lastLine = pastedLines.at(-1).line;
  const lastBlock = lastLine === null;
  const lastStyle = lastLine?.style;
  // Whether the last pasted line ends where the cursor's line ends. A table takes a line of its own, so it never joins
  // the words after the cursor.
  const joinsLast = lastBlock ? nothingAfter : nothingAfter || plain(lastStyle);
  const out = [];
  const emit = (parts, style) => { const blocks = blocksOf(schema, { style, parts }); out.push(...blocks); return blocks; };
  let current = before;
  for (let k = 0; k < pastedLines.length; k++) {
    const { node, line: piece } = pastedLines[k];
    if (!piece) {
      // Nor does a table join the words before the cursor.
      if (k === 0 && wordsBefore) emit(current, cursorStyle);
      current = [];
      out.push(node);
      continue;
    }
    current = [...current, ...piece.parts];
    if (k === pastedLines.length - 1 && joinsLast) break;
    // The words before the cursor stay in their line's style when the first pasted line has none.
    emit(current, k === 0 && wordsBefore && plain(piece.style) ? cursorStyle : piece.style);
    current = [];
  }
  const size = nodes => nodes.reduce((sum, node) => sum + node.nodeSize, 0);
  if (lastBlock && joinsLast) {
    const next = blockPos + block.nodeSize;
    const hasNext = next < tr.doc.content.size;
    if (!hasNext) out.push(schema.nodes.paragraph.create());
    tr.replaceWith(blockPos, next, out);
    const caret = hasNext ? blockPos + size(out) : blockPos + size(out) - 1;
    tr.setSelection(TextSelection.near(tr.doc.resolve(Math.min(caret, tr.doc.content.size)), 1));
    return tr.scrollIntoView();
  }
  const singleJoin = pastedLines.length === 1 && plain(lastStyle) && !lastBlock;
  const caretOffset = joinsLast ? sizeOf(current) : 0;
  const lastStart = size(out);
  const last = emit([...current, ...rest], joinsLast && nothingAfter && !singleJoin ? lastStyle : cursorStyle);
  tr.replaceWith(blockPos, blockPos + block.nodeSize, out);
  tr.setSelection(TextSelection.create(tr.doc, positionIn(last, blockPos + lastStart, caretOffset)));
  return tr.scrollIntoView();
}
