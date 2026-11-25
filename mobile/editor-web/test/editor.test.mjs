// The note editor page, built, in Chromium: what the app sends it, what it sends back, and what a person's taps and
// keys do. Run `npm run build` first; `npm test` runs these.
import { test, before, after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  built, code, dark, doc, file, h, item, launch, light, link, openPage, p, sample, t, table,
} from './helpers.mjs';

let browser;
before(async () => { browser = await launch(); });
after(async () => { await browser?.close(); });

/// Runs [body] with a fresh page, and fails on any error the page throws.
function withPage(body, options) {
  return async () => {
    const editor = await openPage(browser, options);
    try {
      await body(editor);
      assert.deepEqual(editor.errors.map(String), []);
    } finally {
      await editor.close();
    }
  };
}

const frame = editor => editor.page.evaluate(() => new Promise(r => requestAnimationFrame(() => setTimeout(r, 0))));
const wait = (editor, ms) => editor.page.waitForTimeout(ms);
const changes = editor => editor.page.evaluate(() => window.__sent.filter(m => m.is === 'changed'));
const files = { pic1: { kind: 'picture', name: 'hall.png', src: '' } };

describe('load and changes', () => {
  test('a load sends ready and no change; a typed letter sends one change', withPage(async editor => {
    await editor.load(sample, { files });
    await wait(editor, 250);
    assert.equal((await changes(editor)).length, 0, 'the load is no change');
    const ready = (await editor.sent()).find(m => m.is === 'ready');
    assert.ok(ready.ms < 300, `ready in ${ready.ms} ms`);
    // The web address in the words is a link from the load, and the load still sends no change.
    const json = await editor.json();
    const auto = json.content[1].content.find(n => n.text === 'www.relay.example/hall');
    assert.deepEqual(auto?.marks, [{ type: 'link', attrs: { href: 'www.relay.example/hall', auto: true } }]);

    await editor.caret('To pack');
    await editor.page.keyboard.type('!');
    const change = await editor.changed();
    assert.equal(change.quiet, undefined);
    assert.equal(change.doc.content[4].content[0].text, 'To pack!');
    assert.equal((await changes(editor)).length, 1);

    // The changed note, loaded again, is the same note.
    await editor.load(change.doc, { files });
    assert.deepEqual(await editor.json(), change.doc);
    await wait(editor, 150);
    assert.equal((await changes(editor)).length, 0);
  }));

  test('Undo stops at the loaded note', withPage(async editor => {
    await editor.load(doc(p('First note')));
    await editor.caret('First note');
    await editor.page.keyboard.type(' more');
    await editor.changed();
    assert.equal((await editor.state()).canUndo, true);
    await editor.load(doc(p('Second note')));
    await editor.run('undo');
    await editor.run('undo');
    assert.deepEqual(await editor.texts(), ['paragraph|Second note']);
    assert.equal((await editor.state()).canUndo, false);
    await editor.caret('Second note');
    await editor.page.keyboard.press('Control+z');
    assert.deepEqual(await editor.texts(), ['paragraph|Second note']);
  }));

  // The whole document goes over the bridge, with no smaller step for a large note: this measures that it stays fast
  // enough. The limits are generous, for a busy test computer; a phone's own time shows in the iPhone check.
  test('a doc over 200 KB loads and sends a change back in good time', withPage(async editor => {
    const words = 'Pack the van with the chairs, the tables and the blue folder before nine. ';
    const lines = [];
    for (let i = 0; i < 2400; i++) {
      lines.push(i % 10 === 0 ? h(2, `Part ${i}`) : i % 3 ? p(words + i) : item(i % 2 ? 'bullet' : 'numbered', words + i));
    }
    const big = doc(...lines);
    assert.ok(JSON.stringify(big).length > 200_000);
    await editor.load(big);
    const ready = (await editor.sent()).find(m => m.is === 'ready');
    console.log(`# a ${Math.round(JSON.stringify(big).length / 1024)} KB note: ready in ${ready.ms} ms`);
    assert.ok(ready.ms < 3000, `ready in ${ready.ms} ms`);
    const started = Date.now();
    await editor.caret('Part 1200', 0);
    await editor.page.keyboard.type('x');
    const change = await editor.changed();
    const roundTrip = Date.now() - started;
    console.log(`# a letter typed and sent back in ${roundTrip} ms`);
    assert.ok(JSON.stringify(change.doc).includes('xPart 1200'));
    assert.ok(roundTrip < 3000, `a change sent back in ${roundTrip} ms`);
  }));
});

describe('the format tools', () => {
  test('marks, highlight and link light the state', withPage(async editor => {
    await editor.load(doc(p('Call the hall today')));
    await editor.caret('the hall', 0, 8);
    for (const name of ['bold', 'italic', 'underline', 'strike']) {
      await editor.run(name);
      assert.ok((await editor.state()).marks.includes(name), name);
    }
    await editor.run('bold');
    assert.ok(!(await editor.state()).marks.includes('bold'));
    await editor.run('highlight', 'pink');
    assert.equal((await editor.state()).highlight, 'pink');
    await editor.run('recolour', 'blue');
    assert.equal((await editor.state()).highlight, 'blue');
    await editor.run('highlight');
    assert.equal((await editor.state()).highlight, null);
    await editor.run('link', 'https://example.com/hall');
    assert.equal((await editor.state()).link, 'https://example.com/hall');
    const words = (await editor.json()).content[0].content;
    assert.deepEqual(words[1].marks.map(m => m.type).sort(), ['italic', 'link', 'strike', 'underline']);
    await editor.run('link', '');
    assert.equal((await editor.state()).link, null);
    // At a caret, a mark is for the next letters.
    await editor.caret('today');
    await editor.run('bold');
    await editor.page.keyboard.type(' now');
    const last = (await editor.json()).content[0].content.at(-1);
    assert.deepEqual(last, { type: 'text', text: ' now', marks: [{ type: 'bold' }] });
  }));

  test('line styles, lists, ticks, quotes and indents', withPage(async editor => {
    await editor.load(doc(p('One'), p('Two'), p('Three')));
    await editor.caret('One');
    const kindAfter = async (action, value) => { await editor.run(action, value); return (await editor.state()).kind; };
    assert.equal(await kindAfter('line', 'title'), 'header1');
    assert.equal(await kindAfter('line', 'heading'), 'header2');
    assert.equal(await kindAfter('line', 'subheading'), 'header3');
    assert.equal(await kindAfter('line', 'monostyled'), 'code');
    assert.equal(await kindAfter('line', 'body'), 'paragraph');
    assert.equal(await kindAfter('list', 'bullet'), 'bullet');
    assert.equal(await kindAfter('list', 'dashed'), 'dashed');
    assert.equal(await kindAfter('list', 'numbered'), 'numbered');
    assert.equal(await kindAfter('checklist'), 'unchecked');
    assert.equal(await kindAfter('tick'), 'checked');
    assert.equal(await kindAfter('tick'), 'unchecked');
    assert.equal(await kindAfter('checklist'), 'paragraph');
    assert.equal(await kindAfter('quote'), 'quote');
    assert.equal(await kindAfter('quote'), 'paragraph');
    await editor.run('indent', 1);
    await editor.run('indent', 1);
    assert.deepEqual((await editor.texts())[0], 'paragraph@2|One');
    await editor.run('indent', -1);
    assert.deepEqual((await editor.texts())[0], 'paragraph@1|One');
    // Undo and Redo, and their lights.
    await editor.run('undo');
    assert.deepEqual((await editor.texts())[0], 'paragraph@2|One');
    assert.equal((await editor.state()).canRedo, true);
    await editor.run('redo');
    assert.deepEqual((await editor.texts())[0], 'paragraph@1|One');
    // Select all, then a list for every line.
    await editor.run('select-all');
    await editor.run('list', 'bullet');
    assert.deepEqual(await editor.texts(), ['item:bullet@1|One', 'item:bullet|Two', 'item:bullet|Three']);
    await editor.run('blur');
    const state = await editor.state();
    assert.equal(state.editing, false);
    assert.equal(state.focus, false);
  }));

  test('tables: make, add rows and columns, delete and make lines', withPage(async editor => {
    await editor.load(doc(p('Before'), p('After')));
    await editor.caret('Before');
    await editor.run('table');
    let state = await editor.state();
    assert.equal(state.inTable, true);
    await editor.page.keyboard.type('Who');
    await editor.run('row-below');
    await editor.run('column-after');
    const json = await editor.json();
    const grid = json.content[1].content.map(row => row.content.map(cell => cell.type));
    assert.deepEqual(grid, [['tableHeader', 'tableHeader', 'tableHeader'], ['tableCell', 'tableCell', 'tableCell'],
      ['tableCell', 'tableCell', 'tableCell']]);
    // In a cell, the marks do nothing.
    await editor.run('bold');
    await editor.page.keyboard.type('!');
    assert.ok(!JSON.stringify((await editor.json()).content[1]).includes('bold'));
    await editor.run('table-convert');
    assert.deepEqual(await editor.texts(), ['paragraph|Before', 'paragraph|Who!\t\t', 'paragraph|\t\t', 'paragraph|\t\t',
      'paragraph|After']);
    await editor.run('undo');
    state = await editor.state();
    await editor.caret('Who!');
    await editor.run('table-delete');
    assert.deepEqual(await editor.texts(), ['paragraph|Before', 'paragraph|After']);
  }));
});

describe('typing', () => {
  test('marks typed at the start of a line make its style, and Undo gives the marks back', withPage(async editor => {
    const cases = [
      ['# ', 'heading|'], ['## ', 'heading|'], ['- ', 'item:dashed|'], ['* ', 'item:bullet|'],
      ['1. ', 'item:numbered|'], ['[] ', 'item:task|'], ['[ ] ', 'item:task|'], ['> ', 'blockquote|'],
    ];
    for (const [typed, made] of cases) {
      await editor.load(doc(p('')));
      await editor.run('focus');
      await editor.page.keyboard.type(typed);
      assert.deepEqual(await editor.texts(), [made], typed);
      if (typed === '## ') assert.equal((await editor.json()).content[0].attrs.level, 2);
      await editor.page.keyboard.press('Control+z');
      assert.deepEqual(await editor.texts(), [`paragraph|${typed}`], `Undo after ${typed}`);
      await editor.page.keyboard.type('Go');
      assert.deepEqual(await editor.texts(), [`paragraph|${typed}Go`], typed);
    }
    // The style stays for the words after it.
    await editor.load(doc(p('')));
    await editor.run('focus');
    await editor.page.keyboard.type('[] Go');
    assert.deepEqual(await editor.texts(), ['item:task|Go']);
    // Not in a line's middle.
    await editor.load(doc(p('Words')));
    await editor.caret('Words');
    await editor.page.keyboard.type(' - ');
    assert.deepEqual(await editor.texts(), ['paragraph|Words - ']);
  }));

  test('Enter and Backspace in lists', withPage(async editor => {
    await editor.load(doc(item('task', 'Milk', { checked: true })));
    await editor.caret('Milk');
    await editor.page.keyboard.press('Enter');
    await editor.page.keyboard.type('Eggs');
    let json = await editor.json();
    assert.deepEqual(json.content.map(n => [n.attrs.kind, n.attrs.checked, n.content[0].content[0].text]),
      [['task', true, 'Milk'], ['task', false, 'Eggs']]);
    await editor.page.keyboard.press('Shift+Enter');
    await editor.page.keyboard.type('six');
    assert.deepEqual(await editor.texts(), ['item:task|Milk', 'item:task|Eggssix']);
    await editor.page.keyboard.press('Enter');
    await editor.page.keyboard.press('Enter');
    assert.deepEqual(await editor.texts(), ['item:task|Milk', 'item:task|Eggssix', 'paragraph|']);
    await editor.page.keyboard.type('Done');
    await editor.page.keyboard.press('Home');
    await editor.page.keyboard.press('Backspace');
    json = await editor.json();
    assert.equal(json.content.length, 2);
    assert.deepEqual(json.content[1].content.map(line => line.content?.[0]?.text), ['Eggs', 'sixDone']);
  }));

  test('Tab and Shift+Tab move every picked item', withPage(async editor => {
    await editor.load(doc(item('bullet', 'One'), item('bullet', 'Two'), item('bullet', 'Three'), p('After')));
    await editor.page.evaluate(() => {
      window.relayReceive({ do: 'run', action: 'focus' });
      const { state } = window.editor;
      let from = 0, to = 0;
      state.doc.descendants((node, pos) => {
        if (node.isText && node.text === 'One') from = pos + 1;
        if (node.isText && node.text === 'Three') to = pos + 2;
      });
      window.editor.commands.setTextSelection({ from, to });
    });
    await editor.page.keyboard.press('Tab');
    assert.deepEqual(await editor.texts(), ['item:bullet@1|One', 'item:bullet@1|Two', 'item:bullet@1|Three', 'paragraph|After']);
    await editor.page.keyboard.press('Tab');
    await editor.page.keyboard.press('Shift+Tab');
    await editor.page.keyboard.press('Shift+Tab');
    await editor.page.keyboard.press('Shift+Tab');
    assert.deepEqual(await editor.texts(), ['item:bullet|One', 'item:bullet|Two', 'item:bullet|Three', 'paragraph|After']);
    // The selection stays.
    const selected = await editor.page.evaluate(() => window.getSelection().toString());
    assert.match(selected, /ne[\s\S]*Two[\s\S]*Th/);
  }));

  test('Enter and Tab in table cells', withPage(async editor => {
    await editor.load(doc(table([['Who', 'What'], ['Ana', 'Chairs']]), p('After')));
    await editor.caret('Who');
    await editor.page.keyboard.press('Tab');
    await editor.page.keyboard.type('!');
    await editor.page.keyboard.press('Enter');
    await editor.page.keyboard.type('?');
    await editor.page.keyboard.press('Enter');
    await editor.page.keyboard.type('new');
    await editor.page.keyboard.press('Shift+Tab');
    await editor.page.keyboard.type('left');
    const rows = (await editor.json()).content[0].content.map(row => row.content.map(cell => cell.content[0].content?.[0]?.text ?? ''));
    assert.deepEqual(rows, [['Who', 'What!'], ['Ana', 'Chairs?'], ['left', 'new']]);
    // Tab in the last cell adds a row.
    await editor.caret('new');
    await editor.page.keyboard.press('Tab');
    assert.equal((await editor.json()).content[0].content.length, 4);
    assert.equal((await editor.state()).inTable, true);
  }));

  test('a note from elsewhere keeps its files', withPage(async editor => {
    const note = doc(p('Look'), file('pic1', 'hall.png'), p('Under'));
    await editor.load(note, { fromElsewhere: true, files });
    await editor.run('focus');
    await editor.run('select-all');
    await editor.page.keyboard.press('Backspace');
    assert.ok((await editor.texts()).includes('attachment|'));
    await editor.caret('Under', 0);
    await editor.page.keyboard.press('Backspace');
    await editor.page.keyboard.press('Backspace');
    assert.ok((await editor.texts()).includes('attachment|'));
    // A note of this phone lets them go.
    await editor.load(note, { files });
    await editor.run('focus');
    await editor.run('select-all');
    await editor.page.keyboard.press('Backspace');
    assert.ok(!(await editor.texts()).includes('attachment|'));
  }));

  test('the page\'s keys: off with keys false; app keys only when listed', withPage(async editor => {
    const note = doc(p('Bold words'));
    for (const mac of [true, false]) {
      const mod = mac ? 'Meta' : 'Control';
      await editor.load(note, { keys: false, mac });
      await editor.caret('Bold', 0, 4);
      await editor.clearSent();
      for (const key of ['B', 'I', 'U', 'Shift+H', 'Shift+X', 'Shift+E', 'Shift+L', 'Shift+7', 'Alt+1', ']', 'K', 'Alt+T', 'Shift+B']) {
        await editor.page.keyboard.press(`${mod}+${key}`);
      }
      assert.deepEqual(await editor.texts(), ['paragraph|Bold words'], `${mod}: no style`);
      assert.deepEqual((await editor.json()).content[0].content.length, 1, `${mod}: no mark`);
      assert.deepEqual((await editor.sent()).filter(m => m.is === 'keys' || m.is === 'changed'), []);

      await editor.load(note, { keys: true, mac });
      await editor.caret('Bold', 0, 4);
      await editor.page.keyboard.press(`${mod}+B`);
      await editor.page.keyboard.press(`${mod}+Shift+H`);
      await editor.clearSent();
      await editor.page.keyboard.press(`${mod}+K`);
      await editor.page.keyboard.press(`${mod}+Alt+T`);
      const json = await editor.json();
      assert.equal(json.content[0].type, 'heading', `${mod}+Shift+H`);
      assert.deepEqual(json.content[0].content[0].marks, [{ type: 'bold' }], `${mod}+B`);
      assert.deepEqual((await editor.sent()).filter(m => m.is === 'keys'),
        [{ is: 'keys', shortcut: 'link' }, { is: 'keys', shortcut: 'table' }]);
    }
    // App keys: only those listed.
    await editor.load(note, { keys: false, mac: true, appKeys: ['delete-note'] });
    await editor.caret('Bold');
    await editor.clearSent();
    await editor.page.keyboard.press('Meta+Alt+N');
    await editor.page.keyboard.press('Meta+F');
    await editor.page.keyboard.press('Meta+Shift+Backspace');
    assert.deepEqual((await editor.sent()).filter(m => m.is === 'keys'), [{ is: 'keys', shortcut: 'delete-note' }]);
    assert.deepEqual(await editor.texts(), ['paragraph|Bold words']);
    await editor.load(note, { keys: true, mac: false, appKeys: ['new-note', 'find', 'delete-note'] });
    await editor.caret('Bold');
    await editor.clearSent();
    await editor.page.keyboard.press('Control+Alt+N');
    await editor.page.keyboard.press('Control+F');
    await editor.page.keyboard.press('Control+Shift+Backspace');
    assert.deepEqual((await editor.sent()).filter(m => m.is === 'keys').map(m => m.shortcut), ['new-note', 'find', 'delete-note']);
    assert.deepEqual(await editor.texts(), ['paragraph|Bold words']);
    // The browser's narrow layout leaves find to the browser: the page lets Ctrl+F through.
    await editor.send({ do: 'appKeys', appKeys: ['new-note', 'delete-note'] });
    await editor.page.evaluate(() => {
      window.__find = [];
      window.addEventListener('keydown', event => { if (event.code === 'KeyF') window.__find.push(event.defaultPrevented); });
    });
    await editor.clearSent();
    await editor.page.keyboard.press('Control+F');
    await editor.page.keyboard.press('Control+Alt+N');
    assert.deepEqual((await editor.sent()).filter(m => m.is === 'keys').map(m => m.shortcut), ['new-note']);
    assert.deepEqual(await editor.page.evaluate(() => window.__find), [false]);
  }));
});

describe('paste', () => {
  /// Pastes [html] and [text] at the caret; the app answers with [blocks].
  async function paste(editor, { html = '', text = '' }, blocks) {
    await editor.clearSent();
    await editor.page.evaluate(([h, x]) => {
      const data = new DataTransfer();
      if (h) data.setData('text/html', h);
      if (x) data.setData('text/plain', x);
      window.editor.view.dom.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
    }, [html, text]);
    const asked = (await editor.sent()).find(m => m.is === 'paste');
    assert.ok(asked, 'the page asks the app to read the paste');
    assert.equal(asked.text, text);
    await editor.send({ do: 'paste', id: asked.id, blocks });
  }

  test('one plain line joins the line at the caret', withPage(async editor => {
    await editor.load(doc(item('bullet', 'Buy milk')));
    await editor.caret('Buy ', 4);
    await paste(editor, { text: 'oat ' }, [p('oat ')]);
    assert.deepEqual(await editor.texts(), ['item:bullet|Buy oat milk']);
    await editor.page.keyboard.type('x');
    assert.deepEqual(await editor.texts(), ['item:bullet|Buy oat xmilk']);
    await editor.run('undo');
    await editor.run('undo');
    assert.deepEqual(await editor.texts(), ['item:bullet|Buy milk']);
  }));

  test('several lines: the words before keep their style, a styled last line stays its own', withPage(async editor => {
    const note = () => doc(item('task', 'Buy milk'), p('Call Sam'));
    await editor.load(note());
    await editor.caret('Buy ', 4);
    await paste(editor, { text: 'oat\n* x' }, [p('oat'), item('bullet', 'x')]);
    assert.deepEqual(await editor.texts(), ['item:task|Buy oat', 'item:bullet|x', 'item:task|milk', 'paragraph|Call Sam']);
    await editor.page.keyboard.type('!');
    assert.deepEqual((await editor.texts())[2], 'item:task|!milk');

    // Over picked words.
    await editor.load(note());
    await editor.caret('Call Sam', 0, 8);
    await paste(editor, { html: '<h2>Plan</h2><ul><li>a</li></ul>', text: 'Plan\na' }, [h(2, 'Plan'), item('bullet', 'a')]);
    assert.deepEqual(await editor.texts(), ['item:task|Buy milk', 'heading|Plan', 'item:bullet|a']);
    await editor.page.keyboard.type('!');
    assert.deepEqual((await editor.texts()).at(-1), 'item:bullet|a!');

    // A heading first joins the words before the caret, as the app did.
    await editor.load(doc(p('Start end')));
    await editor.caret('Start ', 6);
    await paste(editor, { html: '<h2>Plan</h2><ul><li>One</li><li>Two</li></ul>', text: 'Plan\nOne\nTwo' },
      [h(2, 'Plan'), item('bullet', 'One'), item('bullet', 'Two')]);
    assert.deepEqual(await editor.texts(), ['heading|Start Plan', 'item:bullet|One', 'item:bullet|Two', 'paragraph|end']);
    await editor.run('undo');
    assert.deepEqual(await editor.texts(), ['paragraph|Start end'], 'one Undo takes the paste back');
  }));

  test('lines pasted into a new note\'s empty Title line: the last one is not a Title', withPage(async editor => {
    const title = { type: 'heading', attrs: { level: 1, indent: 0, title: true } };
    await editor.load(doc(title));
    await editor.run('focus');
    await paste(editor, { text: 'Para one\nPara two' }, [p('Para one'), p('Para two')]);
    assert.deepEqual(await editor.texts(), ['paragraph|Para one', 'paragraph|Para two']);
    await editor.load(doc(title));
    await editor.run('focus');
    await paste(editor, { text: 'Only' }, [p('Only')]);
    assert.deepEqual(await editor.texts(), ['heading|Only']);
  }));

  test('a table goes on lines of its own', withPage(async editor => {
    await editor.load(doc(p('Before after')));
    await editor.caret('Before ', 7);
    await paste(editor, { html: '<table><tr><td>A</td><td>B</td></tr></table>', text: 'A\tB' },
      [table([['A', 'B'], ['', '']])]);
    assert.deepEqual(await editor.texts(), ['paragraph|Before ', 'table|AB', 'paragraph|after']);
  }));

  test('a paste in a cell is one line of words, and an old answer does nothing', withPage(async editor => {
    await editor.load(doc(table([['Who', 'What']]), p('')));
    await editor.caret('Who');
    await editor.page.evaluate(() => {
      const data = new DataTransfer();
      data.setData('text/plain', ' one\ntwo ');
      window.editor.view.dom.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
    });
    assert.deepEqual((await editor.texts())[0], 'table|Whoone twoWhat');
    await editor.send({ do: 'paste', id: 999, blocks: [p('late')] });
    assert.ok(!(await editor.texts()).join().includes('late'));
  }));
});

describe('taps', () => {
  test('a tap on a link while reading opens it and leaves the keyboard down', withPage(async editor => {
    await editor.load(doc(p([t('See '), t('the menu', link('https://example.com/menu'))])));
    await editor.clearSent();
    await editor.page.locator('.note a').tap();
    const sent = await editor.sent();
    assert.deepEqual(sent.filter(m => m.is === 'open'), [{ is: 'open', address: 'https://example.com/menu' }]);
    const state = await editor.state();
    assert.equal(state?.editing ?? false, false);
    assert.equal(await editor.page.evaluate(() => window.editor.view.hasFocus()), false);
    // A tap on the words starts editing there.
    await editor.page.locator('.note p').tap({ position: { x: 5, y: 5 } });
    assert.equal((await editor.state()).editing, true);
    assert.equal((await editor.state()).focus, true);
  }));

  test("the words lose the focus when the page does, as when a field of the app takes the keyboard", withPage(async editor => {
    await editor.load(doc(p('Find me')));
    await editor.caret('Find me');
    assert.equal((await editor.state()).focus, true);
    // WebKit keeps the words as the active element while the app's own find field has the keyboard; only the page's
    // window loses the focus.
    await editor.page.evaluate(() => {
      Object.defineProperty(document, 'hasFocus', { value: () => false, configurable: true });
      window.dispatchEvent(new FocusEvent('blur'));
    });
    assert.equal(await editor.page.evaluate(() => window.editor.view.hasFocus()), true);
    assert.equal((await editor.state()).focus, false);
    await editor.page.evaluate(() => {
      delete document.hasFocus;
      window.dispatchEvent(new FocusEvent('focus'));
    });
    assert.equal((await editor.state()).focus, true);
  }));

  test('a note that cannot change sends a tap on its words', withPage(async editor => {
    await editor.load(doc(p('Read only')), { editable: false });
    await editor.clearSent();
    await editor.page.locator('.note p').tap();
    assert.deepEqual((await editor.sent()).filter(m => m.is === 'tap'), [{ is: 'tap', action: 'words' }]);
    await editor.run('focus');
    assert.equal(await editor.page.evaluate(() => window.editor.isEditable), false);
  }));

  test('a tap on a circle ticks it', withPage(async editor => {
    await editor.load(doc(item('task', 'Milk'), item('task', 'Eggs', { checked: true })));
    await editor.page.locator('.item .circle').first().tap();
    let json = await editor.json();
    assert.deepEqual(json.content.map(n => n.attrs.checked), [true, true]);
    assert.equal(await editor.page.evaluate(() => window.editor.view.hasFocus()), false, 'reading stays reading');
    await editor.changed();
    await editor.page.locator('.item .circle').nth(1).tap();
    json = await editor.json();
    assert.deepEqual(json.content.map(n => n.attrs.checked), [true, false]);
    assert.equal(await editor.page.locator('.item .circle').nth(0).getAttribute('aria-checked'), 'true');
  }));

  test('triple-click picks one line: an item\'s line, and the line under it', withPage(async editor => {
    await editor.load(doc(item('bullet', ['Item words here', 'Second line']), p('Under the item'), p('Last')));
    await editor.run('focus');
    await editor.page.locator('.item .words p').first().click({ clickCount: 3 });
    assert.equal(await editor.page.evaluate(() => window.getSelection().toString()), 'Item words here');
    await editor.page.locator('.note > p').first().click({ clickCount: 3 });
    assert.equal(await editor.page.evaluate(() => window.getSelection().toString()), 'Under the item');
    await editor.page.keyboard.type('New');
    assert.deepEqual(await editor.texts(), ['item:bullet|Item words hereSecond line', 'paragraph|New', 'paragraph|Last']);
  }, { desktop: true }));

  test('file cards send their taps with their keys', withPage(async editor => {
    const views = {
      rec: { kind: 'recording', ready: true, length: 42000, levels: [0.2, 0.8, 0.5, 0.1], status: 'words' },
      'head:0': { kind: 'file', name: 'plan.pdf', size: '20 KB', ready: false },
    };
    await editor.load(doc(file('rec', 'voice.m4a'), p('')), { files: views, head: { date: 'Today', above: ['head:0'], below: [] } });
    await editor.clearSent();
    await editor.page.locator('[data-action="play"]').tap();
    await editor.page.locator('[data-action="transcript"]').tap();
    await editor.page.locator('#above [data-action="open"]').tap();
    const taps = (await editor.sent()).filter(m => m.is === 'tap');
    assert.deepEqual(taps, [{ is: 'tap', id: 'rec', action: 'play' }, { is: 'tap', id: 'rec', action: 'transcript' },
      { is: 'tap', id: 'head:0', action: 'open' }]);
    assert.equal(await editor.page.locator('.recording .time').textContent(), '0:42');
    await editor.send({ do: 'files', files: { rec: { ...views.rec, playing: true, position: 21000 } } });
    assert.equal(await editor.page.locator('.recording .time').textContent(), '0:21 / 0:42');
    assert.equal(await editor.page.locator('.recording [data-action="pause"]').count(), 1);
    assert.equal(await editor.page.evaluate(() => window.editor.isEditable), false, 'a card tap does not edit');
  }));
});

describe('find', () => {
  test('counts and steps through the matches', withPage(async editor => {
    await editor.load(doc(p('The van and the hall'), item('bullet', 'THE blue folder'), p('Nothing')));
    await editor.run('find', 'the');
    assert.deepEqual((await editor.state()).found, { count: 3, index: 0 });
    assert.equal(await editor.page.locator('.found').count(), 3);
    assert.equal(await editor.page.locator('.found.now').count(), 1);
    await editor.run('find-step', 1);
    assert.deepEqual((await editor.state()).found, { count: 3, index: 1 });
    await editor.run('find-step', 1);
    await editor.run('find-step', 1);
    assert.deepEqual((await editor.state()).found, { count: 3, index: 0 });
    await editor.run('find-step', -1);
    assert.deepEqual((await editor.state()).found, { count: 3, index: 2 });
    await editor.run('find', 'zebra');
    assert.deepEqual((await editor.state()).found, { count: 0, index: -1 });
    await editor.run('find-close');
    const state = await editor.state();
    assert.equal(state.found, null);
    assert.equal(state.editing, false);
    assert.equal(await editor.page.locator('.found').count(), 0);
  }));
});

describe('files', () => {
  test('attach at the caret and at the end', withPage(async editor => {
    await editor.load(doc(p('One'), p('Two')));
    await editor.caret('One', 1);
    await editor.run('attach', { files: [{ id: 'f1', name: 'a.pdf' }], at: 'cursor' });
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'attachment|', 'paragraph|Two']);
    await editor.page.keyboard.type('>');
    assert.deepEqual((await editor.texts())[2], 'paragraph|>Two', 'the caret goes to the line after the file');
    await editor.run('attach', { files: [{ id: 'f2', name: 'b.pdf' }], at: 'end' });
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'attachment|', 'paragraph|>Two', 'attachment|', 'paragraph|']);
    // An empty last line takes the file in its place, and stays under it.
    await editor.run('attach', { files: [{ id: 'f3', name: 'c.pdf' }], at: 'end', quiet: true });
    assert.deepEqual((await editor.texts()).slice(-3), ['attachment|', 'attachment|', 'paragraph|']);
    await editor.run('detach', { ids: ['f2', 'f3'] });
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'attachment|', 'paragraph|>Two', 'paragraph|']);
  }));

  test('a quiet attach is a quiet change, and Undo skips it', withPage(async editor => {
    await editor.load(doc(p('Words')));
    await editor.run('attach', { files: [{ id: 'f1', name: 'a.png' }], at: 'end', quiet: true });
    const change = await editor.changed();
    assert.equal(change.quiet, true);
    assert.equal((await editor.state()).canUndo, false);
  }));
});

describe('how a note looks', () => {
  test('numbers count by level', withPage(async editor => {
    await editor.load(doc(
      item('numbered', 'One'), item('numbered', 'Two'), item('numbered', 'Two a', { indent: 1 }),
      item('numbered', 'Two b', { indent: 1 }), item('bullet', 'Dot', { indent: 2 }), item('numbered', 'Three'),
      p('Break'), item('numbered', 'Again one'), code('x'), item('numbered', 'After code'),
    ));
    const marks = await editor.page.locator('.item[data-kind="numbered"] > .mark').allTextContents();
    assert.deepEqual(marks, ['1.', '2.', '1.', '2.', '3.', '1.', '1.']);
    // A new item renumbers the rest.
    await editor.caret('One');
    await editor.page.keyboard.press('Enter');
    const after = await editor.page.locator('.item[data-kind="numbered"] > .mark').allTextContents();
    assert.deepEqual(after.slice(0, 3), ['1.', '2.', '3.']);
    assert.equal(after[5], '4.');
  }));

  test('the placeholder shows under a voice note\'s card, and changes', withPage(async editor => {
    const views = { rec: { kind: 'recording', ready: false, length: 3000, status: 'writing' } };
    await editor.load(doc(file('rec', 'voice.m4a'), p('')), { files: views, placeholder: 'Add notes…' });
    const shown = editor.page.locator('.is-empty');
    assert.equal(await shown.count(), 1);
    assert.equal(await shown.getAttribute('data-placeholder'), 'Add notes…');
    assert.equal(await editor.page.evaluate(() => document.querySelector('.is-empty').previousElementSibling?.className), 'attachment');
    await editor.run('placeholder', 'Write here');
    assert.equal(await shown.getAttribute('data-placeholder'), 'Write here');
    await editor.run('focus');
    await editor.page.keyboard.type('a');
    assert.equal(await editor.page.locator('.is-empty').count(), 0);
    // An empty note shows it in its first line.
    await editor.load(doc(p(''), p('')), { placeholder: 'Start writing' });
    assert.equal(await editor.page.evaluate(() => document.querySelector('.is-empty') === document.querySelector('.note > p')), true);
  }));

  test('focus new-line: the caret on an empty last line, and one Undo takes the line away', withPage(async editor => {
    await editor.load(doc(p('One')));
    await editor.run('focus', 'new-line');
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'paragraph|']);
    await editor.run('checklist');
    await editor.page.keyboard.type('Milk');
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'item:task|Milk']);
    const state = await editor.state();
    assert.equal(state.editing, true);
    assert.equal(state.focus, true);
    await editor.load(doc(p('One'), p('')));
    await editor.run('focus', 'new-line');
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'paragraph|']);
    await editor.page.keyboard.type('x');
    assert.deepEqual(await editor.texts(), ['paragraph|One', 'paragraph|x']);
    await editor.load(doc(p('One')));
    await editor.run('focus', 'new-line');
    await editor.run('undo');
    assert.deepEqual(await editor.texts(), ['paragraph|One']);
  }));

  test('the theme sets the colours, and a picture shows its src', withPage(async editor => {
    const src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkaPhfDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await editor.load(sample, { theme: dark, files: { pic1: { kind: 'picture', name: 'hall.png', src } } });
    const look = await editor.page.evaluate(() => {
      const style = getComputedStyle(document.documentElement);
      return { paper: style.getPropertyValue('--paper'), muted35: style.getPropertyValue('--muted35'),
        body: getComputedStyle(document.body).backgroundColor };
    });
    assert.equal(look.paper, '#0C110F');
    assert.equal(look.muted35, 'rgba(154, 168, 160, 0.35)');
    assert.equal(look.body, 'rgb(12, 17, 15)');
    await editor.page.waitForFunction(() => document.querySelector('.picture img')?.complete);
    assert.equal(await editor.page.locator('.picture img').getAttribute('alt'), 'hall.png');
  }));

  test('pictures of the page, light and dark', { skip: !process.env.SHOTS }, async () => {
    const folder = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '.scratch', 'editor-shots');
    mkdirSync(folder, { recursive: true });
    for (const [name, colours] of [['light', light], ['dark', dark]]) {
      const editor = await openPage(browser);
      const views = {
        pic1: { kind: 'file', name: 'hall-plan.pdf', size: '1.2 MB' },
        rec: { kind: 'recording', ready: true, length: 42000, position: 14000, levels: [0.1, 0.4, 0.8, 0.6, 0.3, 0.9, 0.5, 0.2, 0.7, 0.4, 0.2, 0.6], status: 'words' },
      };
      const note = { ...sample, content: [...sample.content.slice(0, -2), file('rec'), file('pic1', 'hall-plan.pdf'), p('')] };
      await editor.load(note, { theme: colours, files: views, head: { date: 'Tuesday 24 November 2026 at 09:12', above: [], below: [] } });
      await editor.run('find', 'the');
      await editor.page.screenshot({ path: join(folder, `${name}.png`), fullPage: true });
      await editor.close();
    }
  });
});

describe('the built page', () => {
  test('holds no web address', () => {
    for (const name of readdirSync(built)) {
      if (name.endsWith('.ttf')) continue;
      const text = readFileSync(join(built, name), 'utf8');
      const addresses = text.match(/https?:\/\/[^\s"'`)]+/g) ?? [];
      // The SVG and XML names are names, not places the page goes.
      const outside = addresses.filter(address => !/^http:\/\/www\.w3\.org\//.test(address));
      assert.deepEqual(outside, [], name);
    }
  });
});

