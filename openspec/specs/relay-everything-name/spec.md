# relay-everything-name Specification

## Purpose
The product has one name, *Relay Everything*, in every place a person reads it, while the hidden names that installs and links depend on keep `relay`.

## Requirements

### Requirement: People read the name Relay Everything
Every place a person reads the product's name SHALL say *Relay Everything*, never *Relay* alone: the phone app (its icon label, screens, messages and permission prompts), the public website and its docs, the server's page, the AI connector's sign-in screen and its name in AI apps, the Claude Code plugin's description and messages, the ring docs, and the repository's guides and wiki.

#### Scenario: The phone app shows the new name
- **WHEN** a person opens the phone app, or the phone asks for a permission on its behalf
- **THEN** the icon label, the timeline title and every message name the product *Relay Everything*

#### Scenario: A later change brings back the old name
- **WHEN** a change adds text a person reads that names the product *Relay* alone
- **THEN** the checks fail and name the file and line

### Requirement: Hidden names keep relay
The rename SHALL NOT change any name a person does not read in use: page addresses such as `/apps/relay/`, database tables, store IDs, code names, file names, the Claude Code plugin's and MCP server's `relay` names, and the `/relay:` commands. An existing install SHALL keep working after the update with no new install, key or setting.

#### Scenario: The phone app updates in place
- **WHEN** a person installs the update over the earlier phone app
- **THEN** it opens with their notes, key and settings as before

#### Scenario: Old links still open
- **WHEN** a person opens a saved link to their server's page or a docs page
- **THEN** it opens the same page as before
