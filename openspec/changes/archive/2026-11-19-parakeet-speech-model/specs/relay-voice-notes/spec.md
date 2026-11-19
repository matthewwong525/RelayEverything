# Spec Delta

## MODIFIED Requirements

### Requirement: The speech model is fetched only with the person's yes

The phone app SHALL get the speech model only after the person agrees to it, the first time they use voice notes, and SHALL say its download size when it asks. It SHALL refuse a model whose download or any of whose files does not match its known checksum, and SHALL let the person remove it. When an update changes the speech model, the app SHALL delete the old model from the phone, SHALL keep every note's recordings and words, and SHALL ask again before it gets the new model.

#### Scenario: First voice note
- **WHEN** the person holds *New note* for half a second with no speech model on the phone
- **THEN** the app asks before it gets the model and its size, and gets nothing on *Not now*

#### Scenario: A damaged download
- **WHEN** the downloaded model, or any file in it, does not match its known checksum
- **THEN** the app deletes it, keeps voice notes off, and offers to try again

#### Scenario: An update with a new speech model
- **WHEN** the phone has the old speech model and a voice note with words, and the app opens for the first time after an update that changes the model
- **THEN** the old model is gone from the phone, the voice note keeps its recording and words, and the next voice note asks before it gets the new model
