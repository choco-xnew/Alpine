# Use Ubuntu 22.04 (Jammy Jellyfish) as the base image as requested
FROM ubuntu:22.04

# Set environment variables for non-interactive installation and locale
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install all dependencies using apt in a single layer for efficiency
# We include the dependencies from both your original and updated lists.
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    sudo curl ffmpeg git nano screen \
    openssh-client openssh-server autossh \
    unzip wget python3 python3-pip \
    build-essential python3-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev \
    file libxml2-dev libxslt1-dev \
    tzdata locales ca-certificates gnupg procps net-tools && \
    # Clean up the package lists
    rm -rf /var/lib/apt/lists/*

# Set up locale using the cleaner method
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# Install Node.js (LTS version from NodeSource for stability)
# This replaces your old setup_21.x command with the current best practice.
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    # Clean up the package lists after installation
    rm -rf /var/lib/apt/lists/*

# -------------------------------------------
# Server Configuration (SSH, Web Content)
# -------------------------------------------

# Configure SSH
RUN mkdir -p /run/sshd /root/.ssh && \
    # The SSH key for 'choco' user access
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnFvGzBK9brNrUT4ebVxCAigp8dgeqjDr4eqAmefnOr choco' > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    # Enable root login and password authentication
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    # Set root password to 'choco'
    echo 'root:choco' | chpasswd && \
    # Generate host keys
    ssh-keygen -A

# Create web content for the Python server
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" > /var/www/index.html

# -------------------------------------------
# Startup Script (Multi-Service and Self-Healing)
# -------------------------------------------

# Create startup script with Serveo tunneling and process monitoring
RUN printf '#!/bin/sh\n\
export PORT=${PORT:-8000}\n\
mkdir -p /root/.ssh\n\
# Start Python HTTP Server\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
# Start SSH Daemon\n\
/usr/sbin/sshd -D &\n\
SSH_PID=$!\n\
# Serveo reverse SSH tunnel (fixed alias "alpine")\n\
ssh -o StrictHostKeyChecking=no -R render:22:localhost:22 serveo.net &\n\
TUNNEL_PID=$!\n\
cat <<EOF\n\
======================================\n\
SERVICES STARTED SUCCESSFULLY!\n\
======================================\n\
HTTP Server: http://localhost:$PORT\n\
SSH Connection Details:\n\
- Connect directly to container IP:22\n\
- OR via Serveo public tunnel:\n\
  ssh -J serveo.net root@render\n\
- Username: root\n\
- Password: choco\n\
- SSH Key: Termius key installed\n\
======================================\n\
EOF\n\
cleanup() {\n\
    kill $HTTP_PID $SSH_PID $TUNNEL_PID 2>/dev/null\n\
    exit 0\n\
}\n\
trap cleanup SIGINT SIGTERM\n\
# Self-healing loop\n\
while true; do\n\
    if ! kill -0 $HTTP_PID 2>/dev/null; then\n\
        echo "HTTP server died, restarting..."\n\
        cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
        HTTP_PID=$!\n\
    fi\n\
    if ! kill -0 $SSH_PID 2>/dev/null; then\n\
        echo "SSH server died, restarting..."\n\
        /usr/sbin/sshd -D &\n\
        SSH_PID=$!\n\
    fi\n\
    if ! kill -0 $TUNNEL_PID 2>/dev/null; then\n\
        echo "Serveo tunnel died, restarting..."\n\
        ssh -o StrictHostKeyChecking=no -R render:22:localhost:22 serveo.net &\n\
        TUNNEL_PID=$!\n\
    fi\n\
    sleep 30\n\
done' > /start && chmod 755 /start

# Create log directory
RUN mkdir -p /var/log

# Health check to ensure the main service is running
HEALTHCHECK --interval=30s --timeout=10s \
    CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

# Expose ports 8000 (HTTP server) and 22 (SSH)
EXPOSE 8000 22

# Run the startup script as the container's entrypoint
CMD ["/start"]
