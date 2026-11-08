# Spec Delta

## Purpose

Give Relay Everything's shared server its terms of use, privacy policy and health data policy on the public website, and a way for people to reach its owner, while no gap in them can reach the menu.

## ADDED Requirements

### Requirement: The website holds the terms, the privacy policy and the health data policy

The website SHALL have a terms of use page, a privacy policy page and a health data policy page, each at its own address. The privacy policy SHALL link to the *Privacy* page for what is kept and where, and SHALL NOT copy that table. The pages SHALL say that they cover only the shared server, and that a server a person runs themselves is that person's own. The privacy policy and the health data policy SHALL say that data is used only to run the service for the person, never sold, never used for ads and never used to train AI. The health data policy SHALL count location history as health data.

#### Scenario: A reader opens the privacy policy
- **WHEN** a reader opens the privacy policy
- **THEN** it names who runs the shared server and how to reach them, the services that handle data for it, how long data is kept, the reader's rights, the age limit and how the policy changes, and it links to the *Privacy* page for what is kept where

#### Scenario: A reader runs their own server
- **WHEN** a person who runs their own server reads the terms
- **THEN** the terms say they cover only the shared server, and the code is under the MIT license

### Requirement: A page with a gap stays a draft

A gap in a legal page SHALL be marked `[LEGAL-TODO: …]`. A page that holds a gap SHALL open with a box that says it is a draft and not in force. No page in the website's menu, and no page that the home page links to, SHALL hold a gap. The website's tests SHALL fail when either rule is broken.

#### Scenario: A gap reaches the menu
- **WHEN** a page in the menu holds `[LEGAL-TODO`
- **THEN** the website's tests fail and name the page

#### Scenario: A draft has no draft box
- **WHEN** a page holds a gap but has no draft box
- **THEN** the website's tests fail and name the page

### Requirement: The shared server shows its contact address

When a server has a contact address set, its sign-in screen and the signed-in account card SHALL show it as a line for questions and privacy requests. A server with no address set SHALL show no such line. The website SHALL still show no email address.

#### Scenario: A stranger looks for a contact
- **WHEN** a person who is not signed in opens the shared server's page
- **THEN** the sign-in screen shows privacy@relayeverything.com for questions and privacy requests

#### Scenario: A person runs their own server
- **WHEN** a server has no contact address set
- **THEN** its sign-in screen and account card show no contact line
