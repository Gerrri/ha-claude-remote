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

# rtk (Apache-2.0 edition): shortens command output for Claude, see run.sh.
ARG RTK_VERSION=1.2.0
ARG RTK_SHA256_X86_64=a28407dc13038bdc9c2a1f5a047b0c636e0c1d495b15523576e2adb992a06a17
ARG RTK_SHA256_AARCH64=9786c61dbbea704e1468ee7060930d3b45b67f79ba2babfb73463e85340628d9
RUN arch="$(uname -m)" \
    && if [ "$arch" = aarch64 ]; then sha="$RTK_SHA256_AARCH64"; else sha="$RTK_SHA256_X86_64"; fi \
    && wget -qO /tmp/rtk.tar.gz \
        "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/rtk-oss-${arch}-unknown-linux-musl.tar.gz" \
    && echo "${sha}  /tmp/rtk.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/rtk.tar.gz -C /usr/local/bin rtk \
    && /usr/local/bin/rtk --version

FROM ${BASE_IMAGE}
RUN apk add --no-cache libgcc libstdc++ ripgrep python3 tmux ttyd nginx
COPY --from=builder /usr/local/bin/claude /usr/local/bin/rtk /usr/local/bin/
COPY --from=builder /opt/ha-mcp /opt/ha-mcp
COPY rootfs /

ENV HOME=/data \
    CLAUDE_CONFIG_DIR=/data/claude \
    DISABLE_AUTOUPDATER=1 \
    USE_BUILTIN_RIPGREP=0 \
    HOMEASSISTANT_URL=http://supervisor/core \
    PATH=/opt/ha-mcp/bin:$PATH

CMD ["/usr/local/bin/run.sh"]
