## MODIFIED Requirements

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float close above it, about 6 points over its top, as wide as the screen less a margin. It SHALL show *Text styles*, *Checklist*, *Table* and *Attach* first, and a sideways swipe SHALL show *Bulleted list*, *Numbered list*, *Link*, *Indent less*, *Indent more* and *Hide keyboard*; part of the next button SHALL show at the edge while more are out of view. While words are selected, the bar SHALL show bold, italic, underline, strikethrough, *Highlight*, *Link* and *Lists* in its place, each lit when the selected words have it, and SHALL change back when the selection goes. The bar SHALL show no drawing and no AI tools. The top SHALL show back, share, ⋯ and a done button that closes the keyboard. The page SHALL keep the cursor in view above the floating tool bar, never under it and never under the top edge, when the person taps into the note, as they type, and when the cursor moves, such as by Undo. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach* and a compose button that opens a new note. The ⋯ menu SHALL offer *Pin Note* or *Unpin Note*, *Find in Note* on a phone, *Copy*, and *Delete*. It SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with the compose button shows

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

#### Scenario: Typing at the end of a long note
- **WHEN** the person taps at the end of a note longer than the screen and types a line
- **THEN** the page scrolls so the line with the cursor shows above the floating tool bar

#### Scenario: Swipe the bar for more tools
- **WHEN** the person swipes the bar over the keyboard to the left
- **THEN** *Numbered list*, *Link* and *Indent more* come into view, and the keyboard stays up

#### Scenario: Select words
- **WHEN** the person selects a bold word
- **THEN** the bar shows the style tools with bold lit, and when the person taps elsewhere in the note the bar shows *Text styles* first again

### Requirement: Text styles, lists and checklists

*Text styles* SHALL open a Format sheet in the keyboard's place with Title, Heading, Subheading, Body and Monostyled for a line, each shown in its own look and the current one filled; bold, italic, underline and strikethrough for selected words; a highlight pen and a colour choice of purple, pink, orange, green and blue; bulleted, dashed and numbered lists; indent in and out; and block quote. A checklist line SHALL show a circle that one tap ticks or unticks, also while the keyboard is down. Return on an empty list or checklist line SHALL end the list. At the start of a line, typing `# `, `## `, `### `, `- `, `* `, `1. `, `[] ` or `> ` SHALL give that line a Title, Heading, Subheading, dashed list, bulleted list, numbered list, checklist or quote, with the marks taken away, and one Undo SHALL give back the marks. The page SHALL show each style as it looks, never its marks.

#### Scenario: Tick an item while reading
- **WHEN** the keyboard is down and the person taps the circle of a checklist line
- **THEN** the line shows ticked, the keyboard stays down, and the change is kept

#### Scenario: A heading
- **WHEN** the person puts the cursor on a line and picks *Heading*
- **THEN** that whole line shows larger and bold, and the other lines keep their style

#### Scenario: Highlight in pink
- **WHEN** the person selects words, picks pink from the colour dot, and taps the pen
- **THEN** the words show with a pink highlight, and a second tap on the pen takes the highlight away

#### Scenario: Type a checklist
- **WHEN** the person types `[] ` at the start of an empty line
- **THEN** the line becomes an open checklist item with no `[]` in it

### Requirement: Styles stay readable as plain text

A note's styles SHALL be kept inside its words as Markdown, so the server, the AI connector, the API and webhooks get readable text with no new field. Underline, which Markdown lacks, SHALL be kept as `<u>…</u>`, and a highlight as `<mark class="<colour>">…</mark>`. A link on words SHALL be kept as `[words](address)`, and a table as a Markdown table. A note written before this change, with no marks, SHALL open with the same words and its first line as a title. Text that holds Markdown-like marks SHALL keep them when the person changes nothing.

#### Scenario: A checklist sent to a webhook
- **WHEN** a note with a ticked line *Milk* and an open line *Eggs* is sent
- **THEN** its words in the `note.created` message read `- [x] Milk` and `- [ ] Eggs`

#### Scenario: Opening an old note
- **WHEN** the person opens a note saved before editing existed and leaves without changing it
- **THEN** its words stay exactly as they were, and it is not sent again

#### Scenario: A highlight and a link sent to a webhook
- **WHEN** a note with *hall* highlighted in pink and *menu* linked to `https://example.com/menu` is sent
- **THEN** its words read `<mark class="pink">hall</mark>` and `[menu](https://example.com/menu)`, and the note opens again with the same highlight and link

### Requirement: Links in a note open in the browser

A web address in a note's words SHALL show as a link in the accent color, also when it was typed or pasted as plain text. The person SHALL be able to select words and give them a link with *Link*, which asks for the address and fills it in from a copied address; *Link* on a link SHALL change its address or take the link away. While the person reads the note, a tap on a link SHALL open it in the phone's browser; while they edit, a tap SHALL put the cursor in it. Showing a typed or pasted address as a link SHALL NOT change the note's stored words or send it again.

#### Scenario: Open a pasted address

- **WHEN** a note holds `https://id.onfido.com/XX6L46TU` as plain text and the person taps it with the keyboard down
- **THEN** the phone's browser opens that address, and the note is not marked to send again

#### Scenario: Edit a link's words

- **WHEN** the person is editing and taps the address
- **THEN** the cursor goes into the address and no browser opens

#### Scenario: Link selected words

- **WHEN** the person has copied `https://example.com/menu`, selects *the menu*, and taps *Link*
- **THEN** the address box shows `https://example.com/menu`, and after *Done* the words *the menu* show as a link to it

### Requirement: A paste keeps its formatting

A paste into a note SHALL keep each style the note can show: headings (a level past 3 becomes level 3), bullet, dashed, numbered and checklist items with their indent, quotes, code blocks, links on words, tables, and bold, italic, underlined and struck-through words. It SHALL drop colors, fonts, sizes, backgrounds, alignment, pictures and other styles the note can't show, so the pasted words take the note's own look. Pasted plain text SHALL be read as Markdown, as a note's own words are read, so `## Plan` pastes as a heading and `**now**` as bold. A link whose words differ from its address SHALL paste as its words, linked to its address. Runs of empty lines SHALL become one, and empty lines at the start and end SHALL go. A paste of one line with no line style SHALL join the line at the cursor. The pasted note SHALL be stored as the Markdown the page shows, so it opens the same again. This SHALL hold for the iPhone's own *Paste*, the app's own menu, a keyboard's paste keys, and the Relay Everything web page. A copy from inside a note SHALL paste back with its styles. One *Undo* SHALL take back the whole paste.

#### Scenario: Paste a list from a web page

- **WHEN** the person copies a heading, a sentence with a bold word, and a bullet list from a web page, and pastes them into a note
- **THEN** the note shows the heading, the bold word, and the bullet items, in the note's own font and colors

#### Scenario: Paste Markdown from a chat

- **WHEN** the person copies `## Plan`, `- [ ] Call the bank` and `- Buy **oat** milk` as plain text and pastes them
- **THEN** the note shows the heading *Plan*, an open checklist item *Call the bank*, and a dashed item *Buy oat milk* with *oat* in bold

#### Scenario: Paste a link with its own words

- **WHEN** the person pastes a link whose words are `the menu` and whose address is `https://example.com/menu`
- **THEN** the note shows `the menu` as a link to `https://example.com/menu`, and keeps it as `[the menu](https://example.com/menu)`

#### Scenario: Paste a few words into a line

- **WHEN** the person pastes `oat` in the middle of the line `Buy milk`
- **THEN** the line reads `Buy oat milk` and keeps its own style

#### Scenario: Undo a paste

- **WHEN** the person pastes a formatted list and taps *Undo*
- **THEN** the whole pasted list goes in one step
