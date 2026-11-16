## ADDED Requirements

### Requirement: The phone shows a day's health totals from the cloud

While the person is signed in to Relay Everything, *Health* is on, and health goes to Relay Everything, the Health page SHALL open a *Health data* page. It SHALL show one day's health totals as the person's space has them, the same totals the AI reads, starting on today, with a way to go to each earlier day and back. It SHALL show each type the day has, and say when the day has none. The phone SHALL keep no copy of what the page shows.

#### Scenario: A day with a watch

- **WHEN** the person opens *Health data* on a day their space has 8,412 steps and heart rates from 58 to 141 bpm
- **THEN** the page shows Steps 8,412 and Heart rate 58 to 141 bpm, the same as the AI's day summary

#### Scenario: Health sent to the person's own webhook

- **WHEN** the person sends health only to their own webhook
- **THEN** the Health page offers no *Health data* page, and the phone asks Relay Everything for no health

### Requirement: The phone shows a day's stays and trips from the cloud

While the person is signed in to Relay Everything, *Location history* is on, and places go to Relay Everything, the Location page SHALL open a *Places data* page. It SHALL list one day's stays and trips in order, as the person's space has them, starting on today, with a way to go to each earlier day and back: a stay with its name and its times, and a trip with its mode, distance and time. The stay in progress SHALL say *Now*. The page SHALL show no map, and the phone SHALL keep no copy of what it shows.

#### Scenario: A morning out

- **WHEN** the space has the person's stay at home, a 1.2 km walk to a café, the café, a drive, and work, where they are now
- **THEN** *Places data* lists Home, the walk, the café, the drive and Work in order, with Work *Now*

#### Scenario: Signed out

- **WHEN** the person is signed out
- **THEN** the Location page offers no *Places data* page

### Requirement: The pages say what has not reached the cloud yet

Each page SHALL show when that data last went and how many uploads still wait on the phone, and SHALL say that it shows only what Relay Everything has. When Relay Everything cannot be reached, the page SHALL say so and offer to try again, and SHALL show no old answer.

#### Scenario: Uploads waiting

- **WHEN** 2 places uploads wait on the phone
- **THEN** *Places data* says 2 wait, and lists only the stays and trips the space has

#### Scenario: No signal

- **WHEN** the phone has no network and the person opens *Health data*
- **THEN** the page says Relay Everything can't be reached, with *Try again*
