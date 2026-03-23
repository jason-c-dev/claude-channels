# I Rebuilt OpenClaw in 250 Lines of Code on the Same Day Anthropic Shipped Channels

*How Claude Code's brand new channel feature turns a Saturday morning, some coffee, and a CLAUDE.md file into a voice-controlled AI assistant on your phone*

---

Yesterday (literally yesterday, March 20, 2026) Anthropic shipped Claude Code Channels as a research preview. By Saturday morning I had a working personal AI assistant on Telegram that transcribes voice messages, summarizes my email, reads PDFs, analyzes images, sends me scheduled briefings via cron, and checks in with dad jokes every six hours.

Total custom code: 254 lines of TypeScript and a 67-line behavior file.

For context, OpenClaw (the open-source project that inspired this feature) has 328K GitHub stars, 20,000+ commits across 79 directories, and adapters for 20+ messaging platforms. It's impressive engineering that proved the demand for "talk to your AI from your phone." Anthropic's response was to build the same capability into the platform so that the rest of us don't have to build it ourselves.

The repo is here: [github.com/jason-c-dev/claude-channels](https://github.com/jason-c-dev/claude-channels)

Let me walk you through what I built, how it works, and the parts that surprised me.

---

## What are channels, exactly?

If you've used MCP servers with Claude Code, you know the pattern: Claude calls a tool when it needs something. Search a database, read a file, hit an API. The MCP server sits passively until Claude invokes it.

Channels flip this. A channel is an MCP server that actively **pushes events into** a running Claude Code session. Something happens in the outside world (a Telegram message, a webhook, a cron job) and Claude reacts to it without anyone typing at a terminal.

That's it. That's the whole innovation. But the implications are significant, because it means a Claude Code session can go from "thing I interact with in my terminal" to "always-on agent that responds to external events."

Anthropic ships two official channel plugins: Telegram and Discord. You install them, pair your account, and start sending messages from your phone. But you can also build your own channels, which is where things get interesting.

---

## The architecture in 30 seconds

My setup has four components. Two are channels (push events in), two are tools (Claude calls out):

| Component | Type | Lines | What it does |
|-----------|------|-------|-------------|
| Telegram plugin | Channel (official) | 0 (Anthropic's) | Chat bridge: forwards messages from my phone |
| `webhook-channel` | Channel (custom) | 93 | HTTP listener: cron and external systems push events |
| `voice-tools` | MCP tool server | 81 | Transcribes voice messages via whisper.cpp |
| `CLAUDE.md` | Behavior file | 67 | Personality, Telegram etiquette, task routing |

Plus a 13-line crontab. That's the whole system.

Claude Code runs as a persistent interactive session. Channels push events in. Claude reasons about what to do, calls whatever tools it needs (Gmail, Google Calendar, voice transcription, web search), and replies through the Telegram plugin. No custom gateway. No routing layer. No adapter framework.

---

## Getting it running: the Saturday morning speedrun

### Step 1: Telegram plugin (5 minutes)

Inside Claude Code:

```
/plugin install telegram@claude-plugins-official
/telegram:configure YOUR_BOT_TOKEN
```

Launch with channels enabled:

```bash
claude \
  --channels plugin:telegram@claude-plugins-official \
  --dangerously-skip-permissions
```

DM your bot on Telegram. It sends a pairing code. Approve it in Claude Code. Send "hi" and Claude replies on Telegram. Done.

At this point you already have a working Telegram AI assistant. Text messages, images, documents: the official plugin handles all of it. I sent it a pixel art drawing I made and asked for a rating.

![Claude analyzing a pixel art drawing sent via Telegram, giving it an 8/10 score with personality](text-msg-image-attachment.png)

8/10. Docked points for stumpy legs and no eyebrows. Fair.

### Step 2: Make it talk back (voice transcription)

The Telegram plugin handles voice messages at the transport level. It receives the audio file and passes the metadata to Claude. But Claude can't listen to audio. It needs a transcription tool.

This is where the MCP architecture shines. I didn't modify the Telegram plugin. I built a separate MCP tool server (81 lines of TypeScript) that accepts a file path and runs whisper.cpp on it. Claude orchestrates the two:

1. Telegram plugin delivers voice memo metadata
2. Claude calls the plugin's `download_attachment` tool to fetch the audio file
3. Claude calls my `voice_transcribe` tool to run whisper.cpp
4. Claude processes the transcribed text and replies via Telegram

Three MCP servers collaborating through Claude as the orchestrator. Each one does one thing.

I sent a voice memo asking for the weather in Palm Springs:

![Voice memo transcription followed by weather report](stt-check-weather.png)

Voice memo → transcription → web search → weather report → Telegram reply. Spoken request, typed response.

### Step 3: The webhook channel (scheduled tasks)

This is where I wrote my only custom channel. 93 lines. It's an HTTP listener on localhost that takes any POST and pushes it into the Claude session as a channel event:

```bash
curl -X POST http://127.0.0.1:8788/briefing \
  -H 'Content-Type: application/json' \
  -d '{"task":"daily_briefing"}'
```

Claude receives this as a channel event, checks the route path (`/briefing`), and follows the instructions in CLAUDE.md for what to do. For a briefing, that means: check Gmail, check Google Calendar, compile a summary, send it to me on Telegram.

The scheduling is just cron:

```bash
# Daily briefing at 7:30am
30 7 * * * curl -s -X POST http://127.0.0.1:8788/briefing -d '{"task":"daily_briefing"}'

# Check-in every 6 hours
0 */6 * * * curl -s -X POST http://127.0.0.1:8788/reconcile -d '{"task":"reconcile"}'
```

Cron fires curl. Curl hits localhost. The webhook channel pushes the event. Claude wakes up and does the work. The most boring, reliable scheduling technology on earth, connected to the most capable AI reasoning engine available. They don't know about each other and don't need to.

The reconcile check-in was my favorite discovery. I told CLAUDE.md to "keep it bright and breezy with a dad joke and corresponding emojis." Every six hours, my phone buzzes with this:

![Scheduled check-in with a dad joke about a scarecrow winning an award](crontab-reconcile-dadjoke.png)

Why did the scarecrow win an award? Because he was outstanding in his field. Thanks, Claude. I didn't ask for this. Cron did.

---

## The behavior layer: 67 lines that do all the heavy lifting

Here's the thing that surprised me most. The entire personality, task routing, and UX pattern of the assistant is defined in CLAUDE.md. A plain text file. No code.

The progress feedback pattern was the most impactful discovery. Without any instructions, Claude would receive a Telegram message, do work silently for 30–60 seconds, then send a reply. From the user's perspective, you're staring at a blank chat wondering if something broke.

The fix was a paragraph of instructions:

```markdown
### Progress Feedback — ALWAYS

Every Telegram message gets this response pattern, no exceptions:

1. React with 👀 immediately.
2. Send a status message BEFORE your first tool call: "☕ Working on it..."
3. After every 2-3 tool calls, edit that message with what you actually did
4. When complete, send a NEW reply with the final result.
   Edits don't push-notify — only a new message buzzes their phone.
```

The Telegram plugin exposes `reply`, `edit_message`, and `react` tools. Claude uses all three to create a real-time progress experience. Not because I wrote progress-tracking code, but because I told it how humans experience waiting.

The document processing flow shows this perfectly. I dropped a 440KB PDF into the chat:

![PDF document attachment being processed with progress updates](text-msg-doc-attachment.png)

The 👀 react appears instantly. The status message appears before any processing. The final summary arrives as a new message so my phone buzzes. All from CLAUDE.md instructions, all using the official Telegram plugin's existing tools.

---

## What I learned (the honest parts)

**Non-deterministic systems don't always follow instructions.** My CLAUDE.md says "send a status message BEFORE your first tool call. NO EXCEPTIONS." Claude follows this about 90% of the time. For quick single-tool tasks, it sometimes decides the instruction doesn't apply and just reacts + replies. The UX is fine when it happens. The disobedience isn't.

This is what I've been calling the AI trust paradox in my other writing: the outcome is acceptable but the process is unreliable. In a 67-line behavior file, that's a curiosity. In a production system with compliance requirements, it's a real problem. CLAUDE.md instructions are suggestions, not contracts.

**Cron over AI scheduling.** Claude Code has a `/loop` feature for scheduling recurring tasks within a session. I chose cron instead. `/loop` is session-scoped (dies when you exit), has a 3-day auto-expiry, and requires the AI to interpret natural language schedules. Cron has been reliably firing scheduled tasks for 50 years. I let the deterministic system handle *when* things happen, and let the AI handle *what* to do when they happen. Clean boundary.

**The launch flags are fiddly.** Getting a custom channel recognized during the research preview required some trial and error. The key: `--dangerously-load-development-channels server:webhook-channel` is separate from `--channels`. You don't add your custom channel to both. The dev flag replaces `--channels` for non-allowlisted servers. The official docs mention this but it's easy to miss.

**Restart after CLAUDE.md changes.** I initially assumed CLAUDE.md would be re-read on every turn. It mostly is, but behavioral patterns (like the multi-step progress feedback) seem to stick better when loaded at session start. If you update CLAUDE.md and don't see the changes, restart the session.

---

## Update: When prompt engineering hits its ceiling, use code

Two days after publishing this post, I was studying for the Claude Certified Architect -- Foundations exam when a concept from the study guide stopped me mid-sentence:

> "The distinction between using hooks for deterministic guarantees versus relying on prompt instructions for probabilistic compliance."

That's Task Statement 1.5 in the exam guide: "Apply Agent SDK hooks for tool call interception and data normalization." And Task Statement 1.4 goes further:

> "When deterministic compliance is required (e.g., identity verification before financial operations), prompt instructions alone have a non-zero failure rate."

I'd been living this exact problem for 48 hours.

### The prompt engineering spiral

Remember the progress feedback pattern I was so proud of? The one where CLAUDE.md says to react with eyes and send a status message before doing any work? In practice, Claude followed it about 90% of the time. So I tightened the language. Added "NO EXCEPTIONS." Added "NEVER make a tool call without a status message." Added bold, caps, and numbered rules.

It went from 90% to maybe 95%. Still not 100%. And I was planning to switch to Haiku (a cheaper, faster model) which would likely make compliance worse, not better.

Sending emoji reactions and progress updates isn't mission-critical in any traditional sense. But from the user's perspective, staring at a silent Telegram chat wondering if your message was received *feels* broken. Visual confirmation that Claude is working on your request is the difference between "this is useful" and "this is unreliable." So I treated it as mission-critical.

Here's the thing the certification guide crystallized for me: I was treating a deterministic problem with a non-deterministic tool. No matter how precisely I worded my CLAUDE.md instructions, they remained *suggestions* processed by a language model. The model would weigh them against context, token probabilities, and its own judgment about what "no exceptions" really means. Sometimes it decided the instruction didn't apply. The outcome was usually fine. The process was never guaranteed.

This is what the exam guide calls the difference between "programmatic enforcement" and "prompt-based guidance." Prompts are probabilistic. Code is deterministic. Knowing which to use when is, apparently, a core competency for building production systems with Claude.

### The solution: a 90-line Python hook

Claude Code has a hook system. Hooks are scripts that fire on lifecycle events -- before a tool runs (`PreToolUse`), when a user submits a prompt (`UserPromptSubmit`), when the agent stops, and more. They receive JSON on stdin describing what's about to happen, and they can allow it, block it, or modify it.

The architecture is simple. Two hooks, one state file:

1. **UserPromptSubmit hook**: When a Telegram message arrives, write a file that says "gate: closed"
2. **PreToolUse hook**: Before every tool call, check the gate. If Claude is trying to call Gmail, WebSearch, or anything that isn't a Telegram communication tool -- and the gate is closed -- block it with exit code 2 and an error message explaining what to do instead

That's it. Claude physically *cannot* search my email, read a file, or hit a web API until it has first called `react` or `reply` on Telegram. The hook doesn't care about prompt wording, model capability, or how the LLM interprets "no exceptions." It's a Python `if` statement. It either passes or it doesn't.

```python
# Telegram communication tools open the gate
if tool_name in TELEGRAM_COMM_TOOLS:
    write_state({"gate": "open", ...})
    sys.exit(0)

# Gate open -- allow everything
if gate == "open":
    sys.exit(0)

# Gate closed -- block with actionable error
print("BLOCKED: Send a Telegram react and status message first.", file=sys.stderr)
sys.exit(2)
```

When Claude gets blocked, it receives the error message as context. Even Haiku can follow "you were blocked, call these two tools first, then retry." The hook enforces the *what*; the model handles the *how*.

### The unexpected design insight

Here's what surprised me. Once the hook existed, the CLAUDE.md instructions got *simpler*, not more complex. I deleted the shouty all-caps rules, the "NO EXCEPTIONS" warnings, the detailed parallel-batch instructions. The new version:

```markdown
### Progress Feedback

A hook blocks all non-Telegram tools until you acknowledge the message.
When you receive a Telegram message:

1. React with eyes and send a brief status message. The hook will
   not let you proceed until you do this.
2. As you work, edit your status message every 2-3 tool calls with
   specific progress.
3. When complete, send a NEW reply with the final result.
```

Six lines instead of twelve. No shouting. The mechanical enforcement moved to code; the prompt now focuses on *quality* guidance that benefits from the model's judgment -- what to say in status messages, how often to update, why final replies should be new messages instead of edits.

This maps directly to what the certification guide describes in Task Statement 1.4: use deterministic systems for workflow ordering (hooks, prerequisite gates), and reserve prompt-based guidance for decisions that benefit from model reasoning. Clean separation of concerns.

### The certification connection

Studying for the exam didn't just give me vocabulary. It reframed how I thought about the problem. I'd been stuck in a prompt engineering loop -- if the model isn't following instructions, write better instructions. The exam guide's domain structure pushed me to think in systems terms:

- **Domain 1** (Agentic Architecture) taught me that hooks are a first-class enforcement mechanism, not a niche feature. The guide explicitly tests whether candidates know when to choose hooks over prompts for compliance.
- **Domain 3** (Claude Code Configuration) covers the hook system's lifecycle events, matchers, and output formats -- the exact primitives I needed to build the gate.
- **Domain 4** (Prompt Engineering) was where I started, but the guide itself distinguishes between prompts for quality guidance and code for guaranteed compliance. The answer to "my prompt isn't working reliably" isn't always "write a better prompt."
- **Domain 5** (Context Management & Reliability) covers escalation and reliability decisions. The hook's circuit breaker (force the gate open after 3 consecutive blocks to prevent infinite loops) is exactly the kind of reliability pattern this domain tests.

The irony is that I was building a weekend project, not a production system. But the architectural thinking transfers. If you're building a customer support agent that must verify identity before processing refunds, the certification guide's answer is the same one I discovered empirically: don't put "ALWAYS verify identity first" in the system prompt and hope for the best. Put a `PreToolUse` hook on `process_refund` that blocks until `get_customer` has returned a verified ID.

Prompts are for guidance. Hooks are for guarantees. The exam guide taught me the principle. The Telegram gate taught me the practice.

---

## A word on the "dangerously" flags

Let's talk about the two flags with "dangerously" in their name, because Anthropic chose that word deliberately.

`--dangerously-skip-permissions` bypasses all permission checks. Claude can read, write, delete files, and execute arbitrary commands without asking. I'm running this on a personal Mac Mini for a personal assistant. The blast radius is my own files. In any shared, production, or internet-facing environment, this flag is exactly as dangerous as it sounds.

`--dangerously-load-development-channels` bypasses the channel allowlist. During the research preview, only Anthropic-curated plugins (Telegram, Discord, Fakechat) are on the approved list. My custom webhook channel isn't reviewed or approved by anyone. I'm telling Claude Code to trust it anyway.

And then there's **prompt injection**. Claude Code's own startup message warns you: *"inbound messages will be pushed into this session, this carries prompt injection risks."* Anyone who can send a message to your Telegram bot, or POST to your webhook endpoint, is injecting text into an AI session that has file system access and command execution capabilities. The pairing allowlist and localhost-only webhook binding are mitigations, not guarantees.

**This is not production.** This is the art of the possible. A Saturday morning exploration of a feature that shipped yesterday. The code is MIT-licensed and published because I think the patterns are interesting and the channel architecture is worth understanding. But if you're thinking about deploying something like this for real users, real data, or real infrastructure, you need proper sandboxing, audit logging, input validation, and a thoughtful security review that goes well beyond what a weekend project provides.

The "dangerously" flags are training wheels for development. They're not an architecture.

---

## The 250-line breakdown

```
 81  tools/voice-tools/src/index.ts       # Audio → whisper.cpp → text
 93  channels/webhook-channel/src/index.ts # HTTP POST → channel event
 67  CLAUDE.md                             # Personality + routing
 13  config/crontab                        # Cron → curl → webhook
───
254  total
```

Everything else (Telegram transport, message delivery, file handling, image analysis, email integration, calendar integration, web search) is handled by Claude Code and its existing MCP ecosystem. Channels just gave me the last missing piece: a way to push external events into the session.

---

## Try it yourself

The repo: **[github.com/jason-c-dev/claude-channels](https://github.com/jason-c-dev/claude-channels)**

Requirements: Claude Code v2.1.80+ with a Claude Max (or Pro/Team/Enterprise) plan, Bun, ffmpeg, whisper.cpp. Setup takes about 15 minutes if you're comfortable with Claude Code and Telegram bots.

The CLAUDE.md file is where the personality lives. Make it yours. Want a sarcastic assistant? Change the instructions. Want it to handle a new webhook route? Add a bullet point. Want different progress behavior? Edit the paragraph. No code required.

Channels launched yesterday. This entire project was built in a single morning. The feature is in research preview, so expect the flag syntax and protocol to evolve, read the security caveats above, and treat this as what it is: a working proof of concept that demonstrates a genuinely new capability. The core idea (pushing events into a running Claude Code session) is here and it works. I'm excited to see what everyone else builds with it.

---

*Jason Croucher works at AWS helping customers build in the cloud using agentic solutions. He writes regularly about the practical realities of building AI agents on [Medium](https://medium.com/@jasoncroucher). The views expressed here are his own and do not necessarily represent those of his employer, Amazon or its customers.*