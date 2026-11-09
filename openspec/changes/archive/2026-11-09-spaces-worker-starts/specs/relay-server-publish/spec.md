## ADDED Requirements

### Requirement: The spaces Worker loads only what a plain Worker can run

The spaces Worker SHALL load no route code and no code that only the web app's build can make, such as `import.meta.glob`, because Cloudflare bundles it alone and refuses a Worker that fails at its start. The repository's checks SHALL fail, and name the file chain, when a change makes the spaces Worker load such code.

#### Scenario: A webhook message needs a list a route also uses

- **WHEN** a webhook message and a route both need the same list of values
- **THEN** the list lives in a file that loads no route, both read it there, and the spaces Worker deploys and starts

#### Scenario: A change makes the spaces Worker load route code

- **WHEN** a file the spaces Worker loads starts to import a route file or the route contract
- **THEN** the spaces Worker test fails and names the chain of files from the spaces Worker to that code
