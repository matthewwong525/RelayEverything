## MODIFIED Requirements

### Requirement: Topics grow from use
The default rules SHALL have one kind of page in the web, a topic, with no set folders for people, projects or places. A topic page SHALL be made when the first fact tags it, and SHALL NOT be made before. The default rules SHALL keep topic pages side by side in `topics/`: a topic that grows big SHALL split into smaller pages that link each other, not into a folder, and the pages SHALL link the topics they connect to, so the web is a graph of linked pages. A folder or a topic name with `/` that a web already has MAY stay. A chat SHALL NOT get a page in the web; its facts SHALL link to it.

#### Scenario: The first fact about Sam
- **WHEN** the first fact tagged `#sam` is added, and the plugin next writes pages
- **THEN** `topics/sam.md` is made and sums up that fact, and no other folder is made

#### Scenario: A topic splits
- **WHEN** the `bike` page grows too big under the default rules
- **THEN** pages such as `topics/bike-battery.md` sit beside `topics/bike.md`, which links them, and no `topics/bike/` folder is made
