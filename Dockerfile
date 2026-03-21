FROM debian:bookworm-slim AS builder

# Build whisper.cpp from source
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch v1.7.3 https://github.com/ggerganov/whisper.cpp.git /tmp/whisper.cpp \
    && cd /tmp/whisper.cpp \
    && cmake -B build -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --build build --config Release -j$(nproc) \
    && cp build/bin/main /usr/local/bin/whisper-cli

# Download whisper model
RUN mkdir -p /usr/local/share/whisper-cpp/models \
    && curl -L -o /usr/local/share/whisper-cpp/models/ggml-base.en.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

# ---

FROM debian:bookworm-slim

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates ffmpeg openssh-server cron git unzip screen \
    && rm -rf /var/lib/apt/lists/*

# Copy whisper from builder
COPY --from=builder /usr/local/bin/whisper-cli /usr/local/bin/whisper-cli
COPY --from=builder /usr/local/share/whisper-cpp /usr/local/share/whisper-cpp

# Install Bun (globally available)
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash

# Install Node.js (needed for Claude Code global install)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Create claude user with SHA-512 password hash
RUN useradd -m -s /bin/bash claude \
    && echo "claude:claude" | chpasswd -c SHA512

# SSH setup
RUN mkdir -p /run/sshd \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitUserEnvironment no/PermitUserEnvironment yes/' /etc/ssh/sshd_config \
    && sed -i 's/KbdInteractiveAuthentication no/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config

# Copy project
COPY --chown=claude:claude . /app
WORKDIR /app

# Update STT_MODEL path for Linux
RUN sed -i 's|/opt/homebrew/share/whisper-cpp/models/ggml-base.en.bin|/usr/local/share/whisper-cpp/models/ggml-base.en.bin|' .mcp.json

# Install MCP server dependencies
RUN su - claude -c "cd /app/tools/voice-tools && bun install" \
    && su - claude -c "cd /app/channels/webhook-channel && bun install"

# Install crontab for claude user
RUN crontab -u claude config/crontab

# Make entrypoint executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 8788

ENTRYPOINT ["/entrypoint.sh"]
