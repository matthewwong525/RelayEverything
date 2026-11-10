## ADDED Requirements

### Requirement: Each stay and trip the AI reads has an id

The AI connector's places answer and day summary, and the API routes behind them, SHALL give each stay and each trip from the phone's stays and trips an id. The id SHALL stay the same while the phone updates that stay or trip. A place made from points that no stay or trip covers SHALL have no id. Every field these answers gave before SHALL stay.

#### Scenario: A day's trip has an id
- **WHEN** the AI asks for Saturday's places
- **THEN** each stay and each trip in the answer has an id, beside its name, times, mode and distance

#### Scenario: An ongoing stay keeps its id
- **WHEN** the AI reads a stay while the person is still there, and reads it again after the phone sent it again
- **THEN** both answers give the same id

### Requirement: The AI and the API read a stay's or a trip's points

The AI connector and the web API SHALL give, for the id of one stay or trip, the location points that the phone which made it sent from its start to its end, and no other phone's points. A stay or trip still going on SHALL read to now. They SHALL also give, for a time range of at most 7 days, the points of all the person's phones in that range. Each point SHALL have its time, latitude, longitude and accuracy, and its street when it has one. One answer SHALL hold at most 500 points: when there are more, the points SHALL be spread evenly over the time and SHALL include the first and the last, and the answer SHALL say how many points there were in all. The read SHALL hold no device name or device id, and SHALL change nothing.

#### Scenario: The route of a trip
- **WHEN** the AI asks for the points of a trip's id, and the trip has 380 points
- **THEN** it gets all 380 points of that trip, oldest first, and a total of 380

#### Scenario: A long trip
- **WHEN** the AI asks for the points of a trip with 3,120 points
- **THEN** it gets 500 points spread over the trip, the first and last among them, and a total of 3,120

#### Scenario: Two phones at once
- **WHEN** two phones sent points during a stay that one of them made, and the AI asks for that stay's points
- **THEN** it gets only that phone's points

#### Scenario: An unknown id or a long range
- **WHEN** the AI asks for an id that no stay or trip has, or for a range longer than 7 days
- **THEN** it gets a refusal that says why, and no points

#### Scenario: Only stays and trips
- **WHEN** the person picked *Only stays and trips*, and the AI asks for a stay's points
- **THEN** it gets no points and a total of 0
