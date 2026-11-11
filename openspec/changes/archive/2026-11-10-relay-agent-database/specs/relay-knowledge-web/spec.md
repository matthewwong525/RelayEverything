## MODIFIED Requirements

### Requirement: Plugins change the memory table's columns and reach no other table
A computer key SHALL be able to read the memory table's columns, and to add a column, change a column's note or whether it is required, and remove a column. A column's type SHALL NOT change, and a removed column's values SHALL stay in the old facts that hold them. Each fact's values SHALL be checked against the columns when it is added. Relay Everything SHALL keep each column change with its time and device. No caller SHALL make another table in the person's space, send a database command to the space, or change the columns Relay Everything keeps; a plugin that wants its own tables SHALL use the person's agents' database. An API key and the AI connector SHALL be able to read the columns and SHALL NOT change them. A phone key SHALL NOT reach `/v1/`.

#### Scenario: A plugin adds a column
- **WHEN** a mood plugin on Ana's computer adds the column `mood`, a short text, and then adds a fact with a mood
- **THEN** the fact is stored with its mood, Ana's other plugins see the new column, and her older facts read as before

#### Scenario: A plugin tries another table
- **WHEN** a plugin asks to make its own table in the space, or sends a database command to the space
- **THEN** it is refused, and nothing in the person's space changes

#### Scenario: A value of the wrong type
- **WHEN** a computer adds a fact with a word in a number column
- **THEN** it is refused, and nothing is stored
