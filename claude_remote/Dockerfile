ARG BASE_IMAGE=ghcr.io/hassio-addons/base:21.0.10

# Builder: fetch the Claude Code native binary and build the ha-mcp venv,
# so Node.js and compilers never reach the final image.
FROM ${BASE_IMAGE} AS builder
ARG CLAUDE_CODE_VERSION=2.1.319
COPY requirements.txt /tmp/requirements.txt
RUN apk add --no-cache nodejs npm python3 build-base python3-dev libffi-dev \
    && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && cp -L "$(npm root -g)/@anthropic-ai/claude-code/bin/claude.exe" /usr/local/bin/claude \
    && /usr/local/bin/claude --version \
    && python3 -m venv /opt/ha-mcp \
    && /opt/ha-mcp/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && find /opt/ha-mcp -name '__pycache__' -prune -exec rm -rf {} +

FROM ${BASE_IMAGE}
RUN apk add --no-cache libgcc libstdc++ ripgrep python3 tmux ttyd nginx
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude
COPY --from=builder /opt/ha-mcp /opt/ha-mcp
COPY rootfs /

ENV HOME=/data \
    CLAUDE_CONFIG_DIR=/data/claude \
    DISABLE_AUTOUPDATER=1 \
    USE_BUILTIN_RIPGREP=0 \
    HOMEASSISTANT_URL=http://supervisor/core \
    PATH=/opt/ha-mcp/bin:$PATH

CMD ["/usr/local/bin/run.sh"]
