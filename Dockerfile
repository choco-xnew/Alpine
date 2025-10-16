# Use the specified Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies using apt
# Note: Since the base image is now Ubuntu, all commands starting with 'apt-get' will work as expected.
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    sudo curl ffmpeg git nano screen openssh-client openssh-server unzip wget autossh \
    python3 python3-pip \
    build-essential python3-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev \
    file libxml2-dev libxslt1-dev \
    tzdata locales ca-certificates gnupg procps net-tools && \
    rm -rf /var/lib/apt/lists/*

# Set up locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install Node.js (LTS version from NodeSource)
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get update && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir -p /run/sshd /root/.ssh && \
    # The SSH key provided in your request: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnFvGzBK9brNrUT4ebVxCAigp8dgeqjDr4eqAmefnOr choco
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnFvGzBK9brNrUT4ebVxCAigp8dgeqjDr4eqAmefnOr choco' > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    echo 'root:choco' | chpasswd && \
    ssh-keygen -A

# Create web content
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" > /var/www/index.html

# Create startup script with Serveo tunneling
# The name 'alpine' in the SSH tunnel will be kept as per your original script's output/logic,
# even though the base image is now Ubuntu.
RUN printf '#!/bin/sh\n\
export PORT=${PORT:-8000}\n\
mkdir -p /root/.ssh\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
/usr/sbin/sshd -D &\n\
SSH_PID=$!\n\
# Serveo reverse SSH tunnel with fixed alias\n\
# The "alpine" name is kept as it was in the original script's logic/output\n\
ssh -o StrictHostKeyChecking=no -R alpine:22:localhost:22 serveo.net &\n\
TUNNEL_PID=$!\n\
cat <<EOF\n\
======================================\n\
SERVICES STARTED SUCCESSFULLY!\n\
======================================\n\
HTTP Server: http://localhost:$PORT\n\
SSH Connection Details:\n\
- Connect directly to container IP:22\n\
- OR via Serveo public tunnel:\n\
  ssh -J serveo.net root@alpine\n\
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
        ssh -o StrictHostKeyChecking=no -R alpine:22:localhost:22 serveo.net &\n\
        TUNNEL_PID=$!\n\
    fi\n\
    sleep 30\n\
done' > /start && chmod 755 /start

# Create log directory
RUN mkdir -p /var/log

# Health check
HEALTHCHECK --interval=30s --timeout=10s \
    CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

# Expose ports 8000 (HTTP server) and 22 (SSH)
EXPOSE 8000 22

# Run the startup script
CMD ["/start"]
