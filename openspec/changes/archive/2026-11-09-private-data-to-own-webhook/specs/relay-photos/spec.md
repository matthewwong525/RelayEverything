## MODIFIED Requirements

### Requirement: Photos go only while the person has them on

The phone app SHALL read the photo library and send photos only while *Photos* is on and the phone sends, to Relay Everything or straight to the person's own webhook. Photos SHALL go where the phone sends its private data: where it sends its notes, or, when a signed-in person picks *Only my own webhook*, only to that webhook. *Photos* SHALL be off by default and SHALL ask for photo access only when turned on. Turning *Photos* or sending off SHALL stop reading the library and delete the photos still waiting on the phone.

#### Scenario: Photos never turned on
- **WHEN** a person sends notes, health and location but never turns *Photos* on
- **THEN** the app asks for no photo access and no photo leaves the phone

#### Scenario: The phone sends to its own webhook
- **WHEN** a person who sends to their own webhook turns *Photos* on and takes a photo
- **THEN** the webhook gets the photo, and nothing goes to a Relay Everything server

#### Scenario: Photos turned off with uploads waiting
- **WHEN** the person turns *Photos* off while photos are still waiting to go
- **THEN** the app deletes the waiting copies, sends no more photos, and leaves the photos already sent on the server

#### Scenario: Signed in with private data to the webhook
- **WHEN** a signed-in person with *Only my own webhook* on takes a photo with *Photos* on
- **THEN** the webhook gets one `photo.created` message, and the photo never reaches Relay Everything
