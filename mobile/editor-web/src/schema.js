// The note's document: one block per line, as the note's Markdown and the phone app store it. A line keeps its own
// indent (0 to 8), so every indent the Markdown holds opens unchanged, and Tab moves each picked line.
import { Node, Mark, mergeAttributes } from '@tiptap/core';
import { Table, TableRow, TableHeader, TableCell } from '@tiptap/extension-table';

export const MAX_INDENT = 8;
export const KINDS = ['bullet', 'dashed', 'numbered', 'task'];
export const COLOURS = ['purple', 'pink', 'orange', 'green', 'blue'];

const clampIndent = value => Math.max(0, Math.min(MAX_INDENT, Number.parseInt(value, 10) || 0));

// The indent of a top-level line, kept in data-indent and drawn through --indent.
const indent = {
  default: 0,
  parseHTML: element => clampIndent(element.getAttribute('data-indent')),
  renderHTML: attributes => attributes.indent ? { 'data-indent': attributes.indent, style: `--indent:${attributes.indent}` } : {},
};

export const Doc = Node.create({ name: 'doc', topNode: true, content: 'block+' });

export const Text = Node.create({ name: 'text', group: 'inline' });

export const Paragraph = Node.create({
  name: 'paragraph',
  priority: 1000,
  group: 'block',
  content: 'inline*',
  addAttributes: () => ({ indent }),
  parseHTML: () => [{ tag: 'p' }],
  renderHTML: ({ HTMLAttributes }) => ['p', HTMLAttributes, 0],
});

export const Heading = Node.create({
  name: 'heading',
  group: 'block',
  content: 'inline*',
  defining: true,
  addAttributes: () => ({
    level: { default: 1, rendered: false },
    indent,
    title: { default: false, rendered: false },
  }),
  parseHTML: () => [1, 2, 3, 4, 5, 6].map(level => ({ tag: `h${level}`, attrs: { level: Math.min(level, 3) } })),
  renderHTML: ({ node, HTMLAttributes }) => [`h${node.attrs.level}`, HTMLAttributes, 0],
});

// A quote is one line of words with a bar, not a box of lines.
export const Blockquote = Node.create({
  name: 'blockquote',
  group: 'block',
  content: 'inline*',
  defining: true,
  addAttributes: () => ({ indent }),
  parseHTML: () => [{ tag: 'blockquote' }],
  renderHTML: ({ HTMLAttributes }) => ['blockquote', HTMLAttributes, 0],
});

export const CodeBlock = Node.create({
  name: 'codeBlock',
  group: 'block',
  content: 'text*',
  marks: '',
  code: true,
  defining: true,
  parseHTML: () => [{ tag: 'pre', preserveWhitespace: 'full' }],
  renderHTML: () => ['pre', ['code', 0]],
});

// A list item: its first paragraph holds its words, each later one a line under the item.
export const Item = Node.create({
  name: 'item',
  group: 'block',
  content: 'paragraph+',
  defining: true,
  addAttributes: () => ({
    kind: {
      default: 'bullet',
      parseHTML: element => KINDS.includes(element.getAttribute('data-item')) ? element.getAttribute('data-item') : 'bullet',
      renderHTML: attributes => ({ 'data-item': attributes.kind }),
    },
    checked: {
      default: false,
      parseHTML: element => element.getAttribute('data-checked') === 'true',
      renderHTML: attributes => attributes.checked ? { 'data-checked': 'true' } : {},
    },
    indent,
  }),
  parseHTML: () => [{ tag: 'div[data-item]' }],
  renderHTML: ({ HTMLAttributes }) => ['div', HTMLAttributes, 0],
});

// A file at its place in the words. The page draws it from the files the app sends.
export const Attachment = Node.create({
  name: 'attachment',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: false,
  addAttributes: () => ({
    id: { default: '', parseHTML: element => element.getAttribute('data-attachment') ?? '', renderHTML: a => ({ 'data-attachment': a.id }) },
    name: { default: '', parseHTML: element => element.getAttribute('data-name') ?? '', renderHTML: a => ({ 'data-name': a.name }) },
  }),
  parseHTML: () => [{ tag: 'div[data-attachment]' }],
  renderHTML: ({ HTMLAttributes }) => ['div', HTMLAttributes],
});

// A table's cells each hold one plain line of words; its first row is the header.
export const NoteTable = Table.extend({
  addAttributes: () => ({ source: { default: null, rendered: false } }),
  addKeyboardShortcuts: () => ({}),
}).configure({ resizable: false, renderWrapper: true, View: null, cellMinWidth: 100 });

export const NoteTableRow = TableRow.extend({ content: '(tableHeader | tableCell)+' });
export const NoteTableHeader = TableHeader.extend({ content: 'paragraph' });
export const NoteTableCell = TableCell.extend({ content: 'paragraph' });

const simpleMark = (name, tags, render) => Mark.create({
  name,
  parseHTML: () => tags,
  renderHTML: ({ HTMLAttributes }) => [render, HTMLAttributes, 0],
});

export const Bold = simpleMark('bold', [{ tag: 'strong' }, { tag: 'b' }], 'strong');
export const Italic = simpleMark('italic', [{ tag: 'em' }, { tag: 'i' }], 'em');
export const Underline = simpleMark('underline', [{ tag: 'u' }], 'u');
export const Strike = simpleMark('strike', [{ tag: 's' }, { tag: 'del' }, { tag: 'strike' }], 's');

export const Highlight = Mark.create({
  name: 'highlight',
  addAttributes: () => ({
    colour: {
      default: 'purple',
      parseHTML: element => COLOURS.includes(element.getAttribute('data-colour')) ? element.getAttribute('data-colour') : 'purple',
      renderHTML: attributes => ({ 'data-colour': attributes.colour }),
    },
  }),
  parseHTML: () => [{ tag: 'mark' }],
  renderHTML: ({ HTMLAttributes }) => ['mark', HTMLAttributes, 0],
});

// A link on words. An auto link is a web address the page found in the words: the note writes it as the bare address.
export const Link = Mark.create({
  name: 'link',
  inclusive: false,
  addAttributes: () => ({
    href: { default: '', parseHTML: element => element.getAttribute('href') ?? '' },
    auto: {
      default: false,
      parseHTML: element => element.getAttribute('data-auto') === 'true',
      renderHTML: attributes => attributes.auto ? { 'data-auto': 'true' } : {},
    },
  }),
  parseHTML: () => [{ tag: 'a[href]' }],
  renderHTML: ({ HTMLAttributes }) => ['a', mergeAttributes(HTMLAttributes, { rel: 'noopener' }), 0],
});

export const schemaExtensions = [
  Doc, Text, Paragraph, Heading, Blockquote, CodeBlock, Item, Attachment,
  NoteTable, NoteTableRow, NoteTableHeader, NoteTableCell,
  Bold, Italic, Underline, Strike, Highlight, Link,
];

/// The kind of a top-level block as the app names line kinds.
export function kindOf(block) {
  if (!block) return null;
  switch (block.type.name) {
    case 'paragraph': return 'paragraph';
    case 'heading': return `header${block.attrs.level}`;
    case 'blockquote': return 'quote';
    case 'codeBlock': return 'code';
    case 'item': return block.attrs.kind === 'task' ? (block.attrs.checked ? 'checked' : 'unchecked') : block.attrs.kind;
    default: return null;
  }
}

export { clampIndent };
