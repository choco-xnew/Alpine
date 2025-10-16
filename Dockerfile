FROM ubantu

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install all dependencies using apt
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    sudo curl ffmpeg git nano screen openssh-server unzip wget autossh \
    python3 python3-pip python3-venv \
    build-essential python3-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev \
    libxml2-dev libxslt-dev \
    tzdata \
    # Install Node.js (from NodeSource)
    ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_21.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set up locale
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    # Set Python virtual environment path
    VENV_PATH="/opt/venv"

# Create and activate Python virtual environment
RUN python3 -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

# Configure SSH for port 22
RUN mkdir -p /run/sshd /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnFvGzBK9brNrUT4ebVxCAigp8dgeqjDr4eqAmefnOr choco' > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && \
    chmod 600 /root/.ssh/authorized_keys && \
    echo 'Port 22' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    echo 'root:choco' | chpasswd && \
    ssh-keygen -A

# Create web content
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" > /var/www/index.html

# Copy requirements.txt if it exists (create a sample one if not)
RUN echo "Flask==2.3.3\nrequests==2.31.0\npillow==10.0.0" > /tmp/requirements.txt

# Install Python packages
RUN pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt

# Create startup script with autossh tunneling
RUN printf '#!/bin/bash\n\
export PORT=${PORT:-8000}\n\
mkdir -p /root/.ssh\n\
# Activate virtual environment\n\
source ${VENV_PATH}/bin/activate\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
/usr/sbin/sshd -D &\n\
SSH_PID=$!\n\
# Autossh reverse SSH tunnel with fixed alias\n\
autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R ubantu:22:localhost:22 serveo.net &\n\
TUNNEL_PID=$!\n\
cat <<EOF\n\
======================================\n\
SERVICES STARTED SUCCESSFULLY!\n\
======================================\n\
HTTP Server: http://localhost:$PORT\n\
Python virtual environment: $VENV_PATH\n\
Node.js version: $(node -v)\n\
Python version: $(python3 --version)\n\
SSH Connection Details:\n\
- Connect directly to container IP:22\n\
- OR via Serveo public tunnel:\n\
  ssh -p 22 -J serveo.net root@ubantu\n\
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
        ssh -N \
    -o "ExitOnForwardFailure=yes" \
    -o "StrictHostKeyChecking=no" \
    -o "ServerAliveInterval=30" \
    -o "ServerAliveCountMax=3" \
    -R ubantu:22:localhost:22 \
    serveo.net &\n\
        TUNNEL_PID=$!\n\
    fi\n\
    sleep 30\n\
done' > /start && chmod 755 /start

# Create log directory
RUN mkdir -p /var/log

# Health check
HEALTHCHECK --interval=30s --timeout=10s \
    CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

EXPOSE 8000 22
CMD ["/start"]
