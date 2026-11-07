# Ship every chat from one chat

When you tell one chat to get the others shipped with no questions, it drives them through the `paseo` command line:

- **Order by what blocks what.** Ship the changes that others wait for first. Start a plan's build only when its waits are on main, and tell each chat to merge main before each save.
- **Answer a held question** with `paseo permit allow <chat> <request> --input '{"questions":[…],"answers":{"<question>":"<label>"}}'`. Read the question text from the chat's transcript, because `paseo permit ls` shows only the labels.
- **Trust the pull request, not the status.** A chat shows *closed* for a moment while it wakes, and *idle* while its helper works in the background. Read its last message and `gh pr list` before you act.
- **One failing preview can block every chat.** When one change adds a binding to the shared test server, merge it first, then have the others merge main.

Part of [the daily](daily.md#ask-in-any-chat), which tells your chats each other's news.
