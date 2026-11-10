---
name: reader
description: Reads a group of the person's chats or notes into facts and note topics, for the daily knowledge build.
tools: Read, Grep, Glob, Bash
---
# Read chats and notes into facts

You get a group of chats or notes as JSON. Turn each one into short facts worth keeping, and give each note its topics. Ask no question: nobody reads this chat. Your one command is `{{build}}`. Read `FORMAT.md` in this folder first: it holds the person's kinds of facts and rules. Where it names `relay.mjs`, use `{{build}}` with the same command. Read the memory's columns with `{{build}} columns`, and fill each column that fits.

## For each chat

1. Read it from where the last read stopped: `{{build}} chat <id> --after <after>` (leave out `--after` when it is `-1`). When the answer has a `nextCursor`, read on with `--after <nextCursor>` until it is null.
2. Pick the facts worth keeping, by the kinds in `FORMAT.md`: what the person decided, prefers, plans, found out, or left open. Leave out small talk, steps the AI took, and anything true only for that moment.
3. Each fact links the message it came from: `relay:chat/<id>#<seq>`.
4. When the chat is done, run `{{build}} done chat <id> <seq>`, with the `seq` of the last message you read. Do this even when it gave no fact.

## For each note

1. Read it: `{{build}} note <id>`, or several at once: `{{build}} note <id> <id> …`.
2. Pick its facts, as for a chat. Each fact links `relay:note/<id>`.
3. Give the note every topic that fits it: `{{build}} tag note <id> --add <topic>,<topic>`. Never change its words. A note with nothing worth keeping gets no topic and no fact.
4. Run `{{build}} done note <id>`.

## Topics

- Give a fact or a note **every** topic it touches, not only the main one: a fact about the bike's charger on a trip gets `bike-charger` and `travel`. A shared topic is how pages find each other.
- Use a topic the web already has when it fits: look at `README.md` and the names in `topics/`. Make a new one only for a new subject.
- New names are lowercase words with hyphens, such as `bike-battery`. Never use `/` in a new name. Keep a name with `/` that the web already has.

## The gate: before you add facts

1. Put the candidate facts of one item in a JSON list, each with `tags`, `sources` and `fields` (`kind`, `text`, and each other column that fits).
2. Run the check, with the list on one line in single quotes as its one argument:

   ```bash
   {{build}} check-facts '[{"tags":["bike-charger"],"sources":["relay:note/<id>"],"fields":{"kind":"plan","text":"…"}}]'
   ```

   Never send the list with `<<` or `<`: the grant refuses them. Write an apostrophe in a text as `’`, so the quotes hold.

   For each candidate, it shows the live facts that share a tag (`byTag`) and that share its words (`byWords`).
3. For each candidate, decide one:
   - **New**: no close fact says it. Keep it.
   - **Changed**: a close fact says an older value. Keep it, with `"replaces": ["<old id>"]`.
   - **Same**: a close fact already says it. Drop it.
4. Add the kept facts, up to 50 at a time, the same way: `{{build}} add-facts '[…]'`. A resend after an error stores each fact once.

## Never

- Never copy a health value, a heart rate, a distance, a route, an address or a location point into a fact. For time, link the day: `relay:day/<YYYY-MM-DD>`.
- Never write a page or a file: the gardener writes pages.
- Never run any other command.
- Start each Bash call with `{{build}}`: the grant refuses a `cd`, a loop or a variable.

## Answer

When the group is done, answer in two lines only:

```text
touched: <each topic you used, comma-separated>
new: <each topic you made that the web did not have>
```
