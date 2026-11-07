## ADDED Requirements

### Requirement: Health reaches the space while the iPhone app is closed

While sending and *Health* are on, the iPhone app SHALL send new Apple Health readings to the person's space without the app being opened, within a few hours of Apple Health holding them, whenever the iPhone has a network and is unlocked at some time in that window. Each reading SHALL be kept once, however often it is sent. With sending or *Health* off, the app SHALL read nothing in the background and SHALL ask Apple Health for no wake-ups.

#### Scenario: A walk with the app closed
- **WHEN** the person closes the app, walks 3,000 steps, and unlocks the phone later that hour
- **THEN** those steps show on their Relay Everything page within a few hours, with the app never opened

#### Scenario: The phone stays locked
- **WHEN** Apple Health wakes the app while the phone is locked and Health can't be read
- **THEN** the app keeps nothing wrong and reads the same readings again at a later wake-up

### Requirement: Places reach the space while the iPhone app is closed

While sending and *Location history* are on, the iPhone app SHALL keep location points after the app is closed and after the phone restarts, in the mode the person chose, and SHALL send the points it keeps:

- *Save battery*, the default: a point at each move of about 500 m, at most each 5 minutes, and at each arrival at and departure from a place.
- *Every 100 m*: a point each 100 m moved, or each 5 minutes while still.

With sending or *Location history* off, the app SHALL ask the iPhone for no location wake-ups and SHALL keep no point.

#### Scenario: A trip after a restart
- **WHEN** the phone restarts and the person drives 5 km in *Save battery* without opening the app
- **THEN** their page shows points along the trip, about one each 500 m, and the arrival

#### Scenario: History turned off
- **WHEN** the person turns *Location history* off and later travels
- **THEN** the iPhone does not wake the app for location, and no point is kept

### Requirement: Settings shows when health and places last went

While sending is on, Settings SHALL show, for *Health* and for *Location history*, when each last reached the person's space and how many of each wait to send.

#### Scenario: Sending stalls
- **WHEN** the phone has had no network since morning
- **THEN** Settings shows the morning time and the number of points and readings waiting
