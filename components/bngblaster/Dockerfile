# BNG Blaster Placeholder
# For production use, build from: https://github.com/rtbrick/bngblaster
#
# This is a lightweight placeholder for demo purposes.
# It includes the configuration files but not the actual bngblaster binary.
# To use the real BNG Blaster, build it from source on the target platform.

FROM alpine:3.19

# Install basic networking tools
RUN apk add --no-cache \
    curl \
    jq \
    iproute2 \
    tcpdump

# Create config directory
RUN mkdir -p /etc/bngblaster

# Add a placeholder script
RUN echo '#!/bin/sh' > /usr/local/bin/bngblaster && \
    echo 'echo "BNG Blaster Placeholder"' >> /usr/local/bin/bngblaster && \
    echo 'echo "========================"' >> /usr/local/bin/bngblaster && \
    echo 'echo ""' >> /usr/local/bin/bngblaster && \
    echo 'echo "This is a demo placeholder. For real traffic generation:"' >> /usr/local/bin/bngblaster && \
    echo 'echo "1. Build BNG Blaster from source: https://github.com/rtbrick/bngblaster"' >> /usr/local/bin/bngblaster && \
    echo 'echo "2. Install on a machine with direct network access to BNG"' >> /usr/local/bin/bngblaster && \
    echo 'echo ""' >> /usr/local/bin/bngblaster && \
    echo 'echo "Available test configurations in /etc/bngblaster:"' >> /usr/local/bin/bngblaster && \
    echo 'ls -la /etc/bngblaster/' >> /usr/local/bin/bngblaster && \
    echo 'echo ""' >> /usr/local/bin/bngblaster && \
    echo 'if [ -n "$1" ]; then' >> /usr/local/bin/bngblaster && \
    echo '  echo "Config file contents ($1):"' >> /usr/local/bin/bngblaster && \
    echo '  cat "$1" 2>/dev/null || echo "File not found: $1"' >> /usr/local/bin/bngblaster && \
    echo 'fi' >> /usr/local/bin/bngblaster && \
    chmod +x /usr/local/bin/bngblaster

# Default command - keep container running for interactive use
CMD ["sleep", "infinity"]
