# Relay Everything plugin for Claude Code

The Relay Everything plugin saves each Claude Code chat to your own Relay Everything server, where you find it on the Relay Everything page and your AI can search it. It also gives the AI a `save_to_relay` tool: ask *save this to Relay Everything*, and the AI writes a title and a summary of what you decided, kept beside the chat.

## Install

1. Make a connect code. In your copy of the Relay Everything repository, run:

   ```bash
   node scripts/relay-device-key.mjs create --name "Laptop" --for claude-code
   ```

   The code shows once, in your terminal and on a private page on your computer. It can only add chats: it can't read, change or delete anything on your server.
2. In Claude Code, add the plugin:

   ```text
   /plugin marketplace add matthewwong525/RelayEverything
   /plugin install relay@relay
   ```

3. When Claude Code asks for the **Relay Everything connect code**, paste the code. Claude Code keeps it in your system's secure store.

Chats from then on are saved. Chats from before the install are not sent.

To keep chats in your own account, run your own Relay Everything server and make the code there. The plugin sends only to the server in the connect code; it has no address built in.

## What is sent

After each answer, the plugin sends the chat's new messages to your Relay Everything server:

- each message you typed, and each answer the AI wrote, word for word;
- one line for each step the AI took, such as `Ran: npm test` or `Read src/app.ts`, and for each `!` command you run, never the step's output;
- the project's folder name, the chat's title and the times.

It never sends the AI's thinking, a file's contents, a command's output or a helper's own chat. Before a message leaves your computer, the plugin replaces keys and tokens, and each value of 8 characters or more in the project's `.env` and `.dev.vars`, with `[hidden]`.

## Turn saving off

- In one project: type `/relay:saving off`. Type `/relay:saving on` to save again, or `/relay:saving` to see which it is and when the project last sent a chat.
- For one run of Claude Code: start it with `RELAY_SAVE=0 claude`.

A chat you don't want on the server: open it on the Relay Everything page and click **Delete**. If the chat is still open in Claude Code, turn saving off first, or the plugin sends it again with your next message.

## Let Claude Code read your notes

Type `/relay:connect-ai https://<your-relay-server>/mcp` with the address from the **AI apps** card on your Relay Everything page. Then type `/mcp`, pick `relay`, and sign in.

## What the plugin keeps on your computer

In the plugin's data folder: each session's transcript path, project, sent count and the time of its last send, the projects with saving off, and `send.log`, the last 200 sends with only session ids, counts and statuses. A send that fails waits there, and the next Claude Code start sends it.
