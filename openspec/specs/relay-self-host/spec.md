# relay-self-host Specification

## Purpose

A person runs Relay in their own Cloudflare account: the server, the Relay page behind their own login, device keys and the AI connector, and none of WongStack.

## Requirements

### Requirement: One request installs Relay in the person's own account

A person SHALL be able to install Relay into their own Cloudflare account by giving their coding AI one request that names the public repository and its setup guide. The install SHALL make the Relay server, its database and recording storage, the Relay page behind a login for the person's own email, and the AI connector, and SHALL report the server's address. It SHALL ask before it makes anything, and SHALL make nothing from WongStack: no skills, wiki, memory store, check runner or previews.

#### Scenario: A first install
- **WHEN** a person pastes the install request and gives a Cloudflare key with the listed permissions
- **THEN** their account holds a working Relay server, page and AI connector under their own login, and the AI reports the address and how to make each device's key

#### Scenario: A key without enough permissions
- **WHEN** the Cloudflare key lacks a permission the install needs
- **THEN** the install names the missing permission and makes nothing

### Requirement: An install runs on Cloudflare's free plan

An install SHALL work on Cloudflare's free plan. When a part needs a paid plan, the guide SHALL say which part and what it costs before the install makes anything.

#### Scenario: A free account
- **WHEN** a person installs into an account with no paid plan
- **THEN** the install finishes, and every Relay route, the page and the AI connector work

### Requirement: An install carries every part of Relay's server

An install SHALL deploy the same Relay server code as Matthew's server, with every route, table and binding that Relay's server has on `main`. A Relay change that adds a binding SHALL fail its checks until the install's settings hold it too.

#### Scenario: A change adds a queue
- **WHEN** a change gives Relay's server a new queue in Matthew's settings only
- **THEN** the checks fail and name the binding the install lacks

#### Scenario: The Claude Code plugin sends to an install
- **WHEN** a connect code made on an install is pasted into the Relay plugin
- **THEN** the plugin's chats arrive on that install, with no change to the plugin

### Requirement: An update keeps the person's data

Asking the AI to update an install SHALL bring in the latest Relay code, apply its database changes, and put the new server live, and SHALL keep every note, recording, sample, point, chat and device key in the person's space. A database change that fails SHALL leave the old server live. An install from before spaces SHALL get no move of its old data: its update removes the old shared tables.

#### Scenario: An update with a new table
- **WHEN** a person updates an install and the new code adds a table
- **THEN** the table is made, the new server goes live, and every earlier note and key still works

#### Scenario: A failed database change
- **WHEN** a database change fails during an update
- **THEN** the old server stays live and the AI reports the failure

### Requirement: Relay's company has no way into an install

An install SHALL hold no key, login or address of Matthew's or Relay's, and SHALL send nothing to them. Only the person's own login and the device keys they make SHALL reach it.

#### Scenario: After an install
- **WHEN** an install finishes
- **THEN** its login lets in only the email the person gave, and its Worker settings hold none of Matthew's IDs, addresses or keys
