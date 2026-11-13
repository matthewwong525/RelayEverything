# Spec Delta

## REMOVED Requirements

### Requirement: One plugin installs in Claude Code and Codex

**Reason**: Relay Everything now installs as a copy in each project, not as a plugin.
**Migration**: The requirement *One copy serves Claude Code and Codex* replaces it; the move is in `relay-project-copy`.

## ADDED Requirements

### Requirement: One copy serves Claude Code and Codex

A project's copy SHALL come from the public Relay Everything repository, with no other repository, and SHALL do the same things in Claude Code and in Codex. It SHALL start no MCP server of its own.

#### Scenario: The copy in Codex

- **WHEN** a project has the copy and the person trusts its hooks in Codex
- **THEN** Codex lists Relay Everything's skills and saves the chat, and no MCP server starts

## MODIFIED Requirements

### Requirement: Saving can be turned off per project
Saving SHALL be on in every project that has the copy until the person turns it off there, and a project with neither the copy nor the plugin SHALL send nothing. While the 0.7.0 plugin is installed, it SHALL keep saving a project with no copy until the person removes it. With saving off, nothing from that project SHALL be sent, and the save skill SHALL say how to turn it on. The person SHALL be able to see whether saving is on and when the project last sent. A git worktree SHALL count as its main repository: a chat in any worktree SHALL carry the main repository's name, and saving off or on SHALL hold in every worktree of it, made before or after.

#### Scenario: Saving is off
- **WHEN** the person turns saving off in a project and then chats there
- **THEN** nothing from that project reaches Relay Everything

#### Scenario: A new workspace copy
- **WHEN** the person turned saving off in a repository, and later starts a chat in a new worktree of it
- **THEN** nothing from that chat reaches Relay Everything

#### Scenario: A chat in a workspace copy is named
- **WHEN** a chat runs in a worktree named `rural-horse` of the `WongOS` repository, with saving on
- **THEN** Relay Everything shows the chat under the project `WongOS`

#### Scenario: A project with no copy
- **WHEN** the person chats in a project that does not have the copy, on a computer with no Relay Everything plugin
- **THEN** nothing from that chat reaches Relay Everything

#### Scenario: A project with no copy, before the plugin is removed
- **WHEN** the person chats in a project that does not have the copy, on a computer that still has the plugin
- **THEN** the plugin saves the chat, once, until the person removes the plugin

### Requirement: The plugin holds no key and no private address
The copy's files SHALL hold no key, email or private address; they MAY name Relay Everything's public address. The computer's key SHALL be kept only in one file readable only by the person's own login, outside every project, and SHALL NOT be written to a log, a project file or a chat.

#### Scenario: A key or private address is added to the plugin
- **WHEN** a file in the copy's source holds text shaped like a key, an email, or a workers.dev address
- **THEN** the checks fail before it can be published
