FROM alpine:latest

# Install all dependencies using apk
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    sudo curl ffmpeg git nano screen openssh openssh-server unzip wget autossh \
    python3 py3-pip \
    build-base python3-dev libffi-dev openssl-dev zlib-dev jpeg-dev \
    musl-dev file-dev libxml2-dev libxslt-dev \
    tzdata \
    # Install Node.js and npm
    nodejs npm && \
    rm -rf /var/cache/apk/*

# Set up locale
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Configure SSH for port 2222
RUN mkdir -p /run/sshd /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzL3NsXdtsrwCtKU3anh+qKynaC3wRDg3oeVaHybWk8 admin@chocox911' > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    echo 'Port 2222' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    echo 'root:choco' | chpasswd && \
    ssh-keygen -A

# Create web content
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" > /var/www/index.html

# Create startup script with autossh tunneling
RUN printf '#!/bin/sh\n\
export PORT=${PORT:-8000}\n\
mkdir -p /root/.ssh\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
/usr/sbin/sshd -D &\n\
SSH_PID=$!\n\
# Autossh reverse SSH tunnel with fixed alias\n\
autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R render:2222:localhost:2222 serveo.net &\n\
TUNNEL_PID=$!\n\
cat <<EOF\n\
======================================\n\
SERVICES STARTED SUCCESSFULLY!\n\
======================================\n\
HTTP Server: http://localhost:$PORT\n\
SSH Connection Details:\n\
- Connect directly to container IP:2222\n\
- OR via Serveo public tunnel:\n\
  ssh -p 2222 -J serveo.net root@render\n\
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
        echo "Autossh tunnel died, restarting..."\n\
        autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R render:2222:localhost:2222 serveo.net &\n\
        TUNNEL_PID=$!\n\
    fi\n\
    sleep 30\n\
done' > /start && chmod 755 /start

# Create log directory
RUN mkdir -p /var/log

# Health check
HEALTHCHECK --interval=30s --timeout=10s \
    CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

EXPOSE 8000 2222
CMD ["/start"]
