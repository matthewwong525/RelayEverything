# Spec Delta

## Purpose

Move the data in a D1 database or R2 bucket to a newly named one when Cloudflare can't rename it, keeping every row and file and keeping private data inside the Cloudflare account.

## ADDED Requirements

### Requirement: The copy stays inside the Cloudflare account

A data move SHALL copy rows and files from store to store inside the owner's Cloudflare account. No row or file content SHALL pass through the computer that runs the move, be printed, or be written to a file. The move SHALL report only table names, file prefixes and counts.

#### Scenario: Health rows move
- **WHEN** the move copies `relay_health` and `relay_locations`
- **THEN** the output shows only their row counts on each side, and no file on the computer holds their rows

### Requirement: A move passes only when the counts match

After a copy, the move SHALL count each table's rows and each bucket's files and bytes on both sides, and SHALL pass only when every count matches. A mismatch SHALL name the table or bucket and both counts. Running the copy again SHALL add what is missing and SHALL NOT double a row or a file.

#### Scenario: A note arrives after the first copy
- **WHEN** a note is kept in the old database after the first copy, and the copy runs again
- **THEN** the new database holds that note once, and the counts match

#### Scenario: A file failed to copy
- **WHEN** one recording is in the old bucket but not the new one
- **THEN** the move fails, naming the bucket and both counts

### Requirement: An old store goes only on the owner's yes

An old database, bucket, Worker or repository SHALL be deleted only after its move passed and the owner said yes to that deletion. A deletion can't be undone.

#### Scenario: The counts match but nobody said yes
- **WHEN** a move passes and the owner has not answered
- **THEN** the old store stays
