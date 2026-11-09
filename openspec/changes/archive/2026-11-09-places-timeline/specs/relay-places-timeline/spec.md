## Purpose

Turn a person's location points into stays at named places and trips between them on their own phone, like Google Maps Timeline, and give them to their AI, their page, the API and their webhooks.

## ADDED Requirements

### Requirement: The phone turns points into stays and trips

While sending and *Location history* are on, the phone SHALL turn its location points into stays and trips. A stay SHALL be a time of 5 minutes or more inside about 100 m, or a point followed by 30 minutes or more with no new point. A silence at the same place, however long, SHALL be one stay. Two stays at the same place less than 15 minutes apart SHALL be one stay. The time between two stays SHALL be one trip. The phone SHALL keep only the points and motion of the stay or trip in progress, and none once sending or *Location history* is off.

#### Scenario: A drive is one trip
- **WHEN** a person is at home for two hours, drives 6 km for 15 minutes with a point every 100 m, and stays at a café for an hour
- **THEN** the phone sends a stay at home, one trip, and a stay at the café, not one row per street

#### Scenario: Sending turned off
- **WHEN** the person turns sending off during a stay
- **THEN** the phone keeps none of that stay's points or motion

### Requirement: Each trip has a mode, a distance and a time

Each trip SHALL have its time in minutes, its distance in km, never longer than the steps between its points, and a mode: walking, running, cycling or driving from the phone's motion sensors when allowed, else from speed, flying over 250 km/h, and unknown for a trip over 60 minutes with no point inside. The phone SHALL ask for motion when *Location history* turns on, on iPhone and Android, and SHALL work from speed when motion is refused.

#### Scenario: A bus ride with motion allowed
- **WHEN** the phone's motion says *in a vehicle* for a 20-minute trip at 18 km/h
- **THEN** the trip says driving, not cycling

#### Scenario: Motion refused
- **WHEN** motion is refused and a person walks 1.4 km in 20 minutes
- **THEN** the trip says walking, 1.4 km, 20 minutes

### Requirement: A stay gets the best name the phone can find

Once per stay, while sending is on, the phone SHALL name it from, in order: a calendar event that overlaps it whose place is within 150 m, while *Calendar* is on; on iPhone, Apple Maps' nearest place within 50 m, asked only when the phone's fix is within 50 m; the street; the coordinates. A stay named from the calendar or the map SHALL also give its street. The phone SHALL never name a stay after a place farther than 50 m.

#### Scenario: A dentist in the calendar
- **WHEN** a person stays near 14 Elm Road during their calendar's *Dentist* event at *Smile Dental, 14 Elm Road*
- **THEN** the stay is named Smile Dental, with the event and the street

#### Scenario: A stop on a road
- **WHEN** the iPhone stops where no place is within 50 m, or its fix is worse than 50 m
- **THEN** the stay is named after the street, never a nearby shop

### Requirement: The person chooses what to send

The Location folder SHALL offer *Stays, trips and points* (the default), *Only stays and trips*, and *Only points*, on iPhone and Android, wherever the phone sends. With *Only stays and trips* the phone SHALL send no location point, and SHALL drop the points waiting on it when the person picks it. With *Only points* the phone SHALL send points as before, make no stay or trip, and ask for no motion.

#### Scenario: Only stays and trips
- **WHEN** the person picks *Only stays and trips* and drives to a café
- **THEN** Relay Everything gets the trip and the stay, and no point along the way

#### Scenario: Only points
- **WHEN** the person picks *Only points*
- **THEN** the phone sends each point with its street, as before, and no stay or trip

### Requirement: Stays and trips go where the points go

The phone SHALL send stays and trips to the place its points go: Relay Everything, or the person's own webhook. Relay Everything SHALL keep each stay and trip once per phone and start, SHALL change it only when it differs, and SHALL send it to each webhook ticked for *Location history*. While the person stays, the stay's end SHALL move on as they stay. When stays stop with sending on, the stay in progress SHALL go as ended; a stay the phone has not sent for 6 hours SHALL read as ended. In *Save battery*, an iPhone stay SHALL keep both the time the person arrived and the time they left.

#### Scenario: The stay you are at now
- **WHEN** a person has been at a café for 10 minutes, and later leaves
- **THEN** Relay Everything has the stay as ongoing, its end growing, then with its end, and a ticked webhook gets each change once

#### Scenario: Own webhook
- **WHEN** the phone sends to the person's own webhook instead of Relay Everything
- **THEN** the webhook gets the stays and trips, and Relay Everything gets nothing

### Requirement: The AI and the API read stays and trips

The AI connector's places answer and day summary, and the API routes behind them, SHALL give the range's stays, each with its name, street, place, arrive and leave times, and its trips, each with its mode, distance, time and the stays at each end. Times with points that no stay or trip covers, such as days before the update or a phone on *Only points*, SHALL answer as before. They SHALL keep every field they gave before. The connector SHALL stay read-only.

#### Scenario: A question about a day
- **WHEN** the AI asks for Saturday's summary
- **THEN** it gets the day's stays in order and the trips between them

#### Scenario: A day with points only
- **WHEN** the AI asks for a day sent before the phone made stays, or by a phone on *Only points*
- **THEN** it gets that day's places as it did before
