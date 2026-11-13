# Spec Delta

## Purpose

Relay Everything installed as the person's own copy inside a project: set up by a pasted prompt, every file the person's to change and keep in git, and updated only when the person asks, with their edits kept.

## ADDED Requirements

### Requirement: A pasted prompt installs the copy in the current project

The website SHALL give one prompt that, pasted into Claude Code or Codex in a project, makes the AI copy the newest Relay Everything release into that project, set it up so both apps run its hooks and list its skills, and start the sign-in link when the computer is not connected yet. The install SHALL keep every other hook, skill and setting in the project. A second install in a project that has the copy SHALL change nothing and point to the update.

#### Scenario: Install in a new project

- **WHEN** the person pastes the prompt in a project with no copy, on a computer not yet connected
- **THEN** the project has the copy, its skills show in Claude Code and Codex, the person's other hooks are still there, and the AI shows the sign-in link

#### Scenario: A second project on a connected computer

- **WHEN** the person installs in a second project on a computer that is already connected
- **THEN** that project saves its chats with no second sign-in

### Requirement: The person owns every file of the copy

Every file of the copy SHALL be a plain file in the project that the person may change, commit and push. Nothing in Relay Everything SHALL overwrite a file of the copy except an update the person agreed to. The copy SHALL hold no key, email, private address or chat state.

#### Scenario: An edited skill

- **WHEN** the person changes a skill in the copy and keeps chatting
- **THEN** the AI follows the changed skill, and nothing puts the old text back

#### Scenario: The copy is pushed

- **WHEN** the person pushes the project with the copy to their own GitHub after connecting
- **THEN** no key or chat state is in what they pushed

### Requirement: An update merges a new release with the person's edits

`/relay-update` SHALL get the newest release, show what it changes, and, only after the person agrees, merge it into the copy: a file only the release changed takes the release's text, a file only the person changed keeps theirs, and lines both changed SHALL be shown to the person to choose. After an update the copy SHALL know which release it came from, so the next update merges from there.

#### Scenario: An update with no clash

- **WHEN** the person edited one skill, and the new release changed only other files
- **THEN** after the update the edited skill keeps the person's text and the other files are the release's

#### Scenario: A clash

- **WHEN** the person and the new release changed the same lines of a file
- **THEN** the AI shows both and writes nothing to that file until the person chooses

### Requirement: The plugin moves a person to the copy once

The last plugin version SHALL tell the person once that Relay Everything moved, and on their ask SHALL install the copy in the current project, keeping the computer's connection. It SHALL remove the plugin from Claude Code and Codex only after the person says so. In a project that has the copy, the plugin SHALL send nothing, so no chat is sent twice.

#### Scenario: A project with both

- **WHEN** a project has the copy and the plugin is still installed
- **THEN** each chat there reaches Relay Everything once
