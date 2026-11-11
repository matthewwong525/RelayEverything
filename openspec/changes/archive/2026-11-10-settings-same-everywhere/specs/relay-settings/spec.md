# Spec Delta

## Purpose

One Settings shape on the Relay Everything phone app and web app: the account, then Appearance, with the developer options at the bottom of the Account page, and a simple sign-in.

## ADDED Requirements

### Requirement: Settings shows the same rows on the phone and the web

Settings SHALL show, in this order, the account card and *Appearance*, on the phone and in the browser, with the same names. The phone SHALL also show *Notes* (*Pin notes to where I am*) and *Voice notes* (the speech model) after *Appearance*, and the app's version and build at the bottom; the browser SHALL NOT show them. Settings SHALL have no *Advanced* row, and SHALL NOT hold health, places, the calendar, photos, AI apps, email notes or webhooks. A signed-out phone SHALL make no network request when it opens Settings.

#### Scenario: The phone, signed in
- **WHEN** a person signed in as you@example.com opens Settings on the phone
- **THEN** it shows the account card with you@example.com, *Appearance*, *Notes*, *Voice notes* and the version, in that order

#### Scenario: The browser
- **WHEN** the same person opens Settings in the browser
- **THEN** its list shows *Account* and *Appearance*, in that order, and nothing else

### Requirement: The account card says where notes go, in few words

Signed in, the account card SHALL show the account's email and *Signed in*, and nothing more. Sending to the person's own webhook with no account, it SHALL say *My own webhook* and show the webhook's address. Signed out, it SHALL say *Sign in to Relay Everything* and that notes stay on the phone until the person signs in. A tap SHALL open the sign-in when signed out, else the Account page.

#### Scenario: Private data to the webhook
- **WHEN** a signed-in person sends health, places, calendar and photos only to their own webhook, and opens Settings
- **THEN** the account card shows their email and *Signed in*, and no other line

#### Scenario: Signed out
- **WHEN** a person opens Settings on a new install
- **THEN** the account card says *Sign in to Relay Everything*, and no request leaves the phone

### Requirement: Account holds the person, their phones and the developer options

Signed in, the Account page SHALL show, in this order, on the phone and in the browser: the account's email and *Signed in* with *Sign out* beside them; *Phones*, each of the person's phones by name, the phone it is opened on marked *This phone*, and each other phone with *Sign out*; *Advanced*, with *Webhooks*, and in the browser *API keys*; and *Delete my account*, alone and last. It SHALL NOT ask where data goes, list computers, or offer to sign out every device at once. *Sign out* beside the email SHALL ask first, then sign out the device it is tapped on; on a phone it SHALL remove the phone's key and stop sending, and the notes written on the phone SHALL stay on it. *Sign out* on another phone SHALL ask first, then stop that phone at its next request and leave the others working. On the phone, *Delete my account* SHALL open the person's Relay Everything page. With sending to the person's own webhook and no account, the Account page SHALL show the webhook's address, *Send a test*, *Sign in to Relay Everything* and *Stop sending*.

#### Scenario: A lost phone
- **WHEN** a person who lost their Pixel opens Account on their iPhone, taps *Sign out* beside the Pixel, and confirms
- **THEN** the Pixel stops sending at its next request, and the iPhone and their computers keep working

#### Scenario: Sign out of this phone
- **WHEN** the person taps *Sign out* beside their email and confirms
- **THEN** the phone forgets its key, sending stops, the notes written on this phone stay, and the account card says *Sign in to Relay Everything*

### Requirement: Sign in has one button and one link

The phone's sign-in SHALL show one primary *Sign in* button, which signs in to Relay Everything, and one quiet link, *Don't want an account? Use your own webhook*, which opens the webhook's setup. It SHALL NOT offer a QR code, a pasted key or another server. The setup SHALL ask for the address, give a secret to copy, offer *Send a test*, and save; once saved, the phone SHALL send to the webhook with no account and never ask the person to sign in. A phone that keeps a key SHALL offer it in one tap. Leaving the sign-in or the setup SHALL change nothing. A phone already signed in to another server SHALL keep sending there.

#### Scenario: Sign in in one tap
- **WHEN** a signed-out person opens the sign-in
- **THEN** it shows one *Sign in* button and *Don't want an account? Use your own webhook*, and no other field or button

#### Scenario: A webhook with no account
- **WHEN** a person with no account taps *Don't want an account? Use your own webhook*, pastes an https address, copies the secret, and saves
- **THEN** the phone sends new notes to the webhook, the account card says *My own webhook*, and the phone never asks them to sign in

### Requirement: Advanced on the Account page holds the developer options

*Advanced* on the Account page SHALL hold *Webhooks*, and in the browser *API keys*, each a row that opens its page and says in one line what it is for. On the phone, *Webhooks* SHALL say a person does not need it to use Relay Everything, list the webhooks by name, open the person's Relay Everything page to add or change one, and hold *Only to my own webhook* for health, places, calendar and photos, shown only while signed in. In the browser, *Webhooks* SHALL add, change and remove webhooks as before. *API keys* SHALL list the person's API keys, each with *Turn off*, and *Add an API key*, which shows the new key once. No page but *API keys* SHALL show a key. *Only to my own webhook* SHALL be off by default and SHALL work as the earlier private-data choice did. A person who never opens *Advanced* SHALL send everything they turn on to Relay Everything.

#### Scenario: The default
- **WHEN** a person signs in, never opens *Webhooks*, and turns on Health
- **THEN** their health readings go to Relay Everything

#### Scenario: Private data to the webhook
- **WHEN** a signed-in person with no webhook on the phone turns on *Only to my own webhook* in *Webhooks*, sets the webhook and saves
- **THEN** health, places, calendar and photos go only to the webhook, notes still go to Relay Everything, and leaving the setup unsaved changes nothing

### Requirement: Gray buttons show their words in the app's font

Every gray (quiet) button on the phone and the web SHALL draw its words in the app's own font, and SHALL NOT draw them as boxes when no system font is loaded.

#### Scenario: Copy on a fresh web page
- **WHEN** a person opens *Email notes* in the browser before any other font has loaded
- **THEN** the *Copy* button shows the word *Copy*, in the app's font
