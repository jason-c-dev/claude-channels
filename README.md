# claude-channels

**OpenClaw in ~250 lines of code.**

[OpenClaw](https://github.com/openclaw/openclaw) is a 328K-star personal AI assistant with 20,000+ commits, 79 directories, and adapters for 20+ messaging platforms. It's impressive engineering.

This repo does the same core job — an always-on AI assistant you talk to via Telegram, with voice transcription, scheduled briefings, and webhook triggers — in 254 lines of TypeScript and a 67-line behavior file. No gateway, no routing layer, no adapter framework.

The trick? **Claude Code channels.**

## What are channels?

Regular MCP servers are passive — Claude calls them when it needs a tool. Channels flip this: they actively **push events into** a running Claude Code session.

This is the key architectural difference. OpenClaw needs thousands of lines of gateway and routing code to orchestrate message flow between platforms and the AI. With channels, Claude Code *is* the gateway. A channel just pushes an event and Claude handles it.

This repo demonstrates both patterns:

| Component | Type | Lines | What it does |
|-----------|------|-------|--------------|
| `voice-tools` | MCP tool server | 81 | Transcribes voice messages via whisper.cpp. Claude calls it on demand. |
| `webhook-channel` | Channel server | 93 | HTTP listener that pushes webhooks into the session. Enables cron and external triggers. |
| `CLAUDE.md` | Behavior layer | 67 | Instructions that give Claude its personality, Telegram etiquette, and task routing. |
| `config/crontab` | Scheduler | 13 | Cron jobs that curl the webhook channel to trigger scheduled tasks. |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                 Claude Code Session              │
│                                                  │
│  CLAUDE.md defines behavior:                     │
│  - How to respond on Telegram                    │
│  - How to handle voice messages                  │
│  - What to do for each webhook route             │
│                                                  │
├──────────┬──────────┬───────────┬────────────────┤
│ Telegram │  voice-  │  webhook- │  Gmail/GCal    │
│ Plugin   │  tools   │  channel  │  (claude.ai)   │
│ (channel)│  (tool)  │ (channel) │  (connectors)  │
└────┬─────┴────┬─────┴─────┬─────┴────────────────┘
     │          │           │
     ▼          ▼           ▼
  Telegram   whisper.cpp   HTTP :8788
  Bot API                  ◄── cron / curl / webhooks
```

**Push vs Pull:**
- Telegram plugin and webhook-channel are **channels** — they push messages/events into the session
- voice-tools is a regular **MCP server** — Claude calls it when it needs to transcribe audio
- Gmail/GCal are claude.ai connectors — Claude calls them for email and calendar data

## Project structure

```
claude-channels/
├── CLAUDE.md                        # Agent behavior instructions
├── .mcp.json                        # MCP server configuration
├── tools/
│   └── voice-tools/
│       ├── package.json
│       └── src/
│           └── index.ts             # voice_transcribe tool (81 lines)
├── channels/
│   └── webhook-channel/
│       ├── package.json
│       └── src/
│           └── index.ts             # HTTP → channel events (93 lines)
└── config/
    └── crontab                      # Scheduled task definitions
```

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with channels support
- [Bun](https://bun.sh) runtime
- [ffmpeg](https://ffmpeg.org) for audio conversion
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for voice transcription
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))

## Setup

### 1. Clone and install

```bash
git clone https://github.com/youruser/claude-channels.git
cd claude-channels

cd tools/voice-tools && bun install && cd ../..
cd channels/webhook-channel && bun install && cd ../..
```

### 2. Install whisper model

```bash
# macOS (Homebrew)
brew install whisper-cpp ffmpeg

# Download the English base model
mkdir -p /opt/homebrew/share/whisper-cpp/models
curl -L -o /opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

### 3. Configure .mcp.json

Update the `STT_MODEL` path in `.mcp.json` to point to your whisper model:

```json
{
  "mcpServers": {
    "voice-tools": {
      "command": "bun",
      "args": ["run", "tools/voice-tools/src/index.ts"],
      "env": {
        "STT_MODEL": "/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin"
      }
    },
    "webhook-channel": {
      "command": "bun",
      "args": ["run", "channels/webhook-channel/src/index.ts"],
      "env": {
        "WEBHOOK_PORT": "8788"
      }
    }
  }
}
```

### 4. Install the Telegram plugin

Inside any Claude Code session:

```
/plugin install telegram
```

Follow the prompts to enter your bot token and configure access.

### 5. Launch

```bash
claude \
  --dangerously-skip-permissions \
  --dangerously-load-development-channels server:webhook-channel \
  --channels plugin:telegram@claude-plugins-official
```

That's it. Claude is now:
- Listening for Telegram messages (text, voice, photos, documents)
- Transcribing voice messages via whisper.cpp
- Accepting webhooks on `http://127.0.0.1:8788`
- Ready for cron-scheduled tasks

## Testing

### Voice messages

Send a voice memo in your Telegram chat with the bot. Claude will:
1. Download the audio file
2. Call `voice_transcribe` to run whisper.cpp
3. Process the transcribed text and reply

### Webhooks

From another terminal:

```bash
# Health check
curl http://127.0.0.1:8788/health

# Trigger a daily briefing
curl -X POST http://127.0.0.1:8788/briefing \
  -H 'Content-Type: application/json' \
  -d '{"task":"daily_briefing"}'

# Trigger a check-in
curl -X POST http://127.0.0.1:8788/reconcile \
  -H 'Content-Type: application/json' \
  -d '{"task":"reconcile"}'
```

The webhook-channel pushes these as channel events. Claude reads the `meta.path` and follows the routing instructions in CLAUDE.md.

## Scheduled tasks

Install the crontab to enable scheduled triggers:

```bash
crontab config/crontab
```

Default schedule:
| Time | Route | Action |
|------|-------|--------|
| 7:00 AM, 5:00 PM | `/weather` | Weather check (alerts only if actionable) |
| 7:30 AM | `/briefing` | Daily briefing (email + calendar summary) |
| Every 6 hours | `/reconcile` | Check in with the user |
| 11:00 PM | `/eod` | End-of-day summary |

## How CLAUDE.md works

The `CLAUDE.md` file is the behavior layer. It's loaded into every Claude Code session in this directory and tells Claude:

- **Telegram etiquette**: Always react with 👀, send progress updates, final results as new messages (not edits, so the phone buzzes)
- **Voice handling**: The step-by-step flow for transcribing and responding to voice messages
- **Webhook routing**: What to do for each webhook path (`/briefing`, `/reconcile`, `/weather`, `/eod`)

This is where you customize the assistant's personality and capabilities. Want Claude to handle a new webhook route? Add a bullet point. Want different Telegram behavior? Edit the instructions. No code changes needed.

## Extending

### Add a new webhook route

1. Add a route description to the `## Webhook Events` section in `CLAUDE.md`:
   ```
   - `/my-route` — Description of what Claude should do when this fires.
   ```

2. Trigger it:
   ```bash
   curl -X POST http://127.0.0.1:8788/my-route \
     -H 'Content-Type: application/json' \
     -d '{"your":"data"}'
   ```

That's it. No code changes — Claude reads the CLAUDE.md instructions and handles the new route.

### Add a new MCP tool

1. Create a new server in `tools/your-tool/`
2. Register it in `.mcp.json`
3. Add usage instructions to `CLAUDE.md`

### Add another channel

1. Create a new channel server in `channels/your-channel/` (declare `claude/channel` capability)
2. Register in `.mcp.json`
3. Add to the launch command: `--dangerously-load-development-channels server:your-channel`

## The 250-line breakdown

```
 81  tools/voice-tools/src/index.ts       # MCP tool: audio → whisper.cpp → text
 93  channels/webhook-channel/src/index.ts # Channel: HTTP POST → session event
 67  CLAUDE.md                             # Behavior: personality + routing
 13  config/crontab                        # Scheduler: cron → curl → webhook
───
254  total
```

Compare with OpenClaw's 20,000+ commits across 79 directories. Channels are a powerful abstraction.

## License

MIT
