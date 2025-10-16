FROM ubuntu:22.04

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    VENV_PATH="/opt/venv"

# Install dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        sudo curl ffmpeg git nano screen openssh-server unzip wget autossh \
        python3 python3-pip python3-venv \
        build-essential python3-dev libffi-dev libssl-dev zlib1g-dev libjpeg-dev \
        libxml2-dev libxslt-dev \
        tzdata ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_21.x $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Setup Python venv
RUN python3 -m venv $VENV_PATH
ENV PATH="$VENV_PATH/bin:$PATH"

# Configure SSH
RUN mkdir -p /run/sshd /root/.ssh && \
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGnFvGzBK9brNrUT4ebVxCAigp8dgeqjDr4eqAmefnOr choco' \
        > /root/.ssh/authorized_keys && \
    chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && \
    echo 'Port 22' >> /etc/ssh/sshd_config && \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    echo 'PidFile /run/sshd.pid' >> /etc/ssh/sshd_config && \
    echo 'root:choco' | chpasswd && \
    ssh-keygen -A

# Web content
RUN mkdir -p /var/www && \
    echo "<html><body><h1>Python HTTP Server Working!</h1><p>Direct SSH access available</p></body></html>" \
    > /var/www/index.html

# Python packages
RUN echo -e "Flask==2.3.3\nrequests==2.31.0\npillow==10.0.0" > /tmp/requirements.txt && \
    pip install --upgrade pip && \
    pip install -r /tmp/requirements.txt

# Startup script
RUN printf '#!/bin/bash\n\
export PORT=${PORT:-8000}\n\
source ${VENV_PATH}/bin/activate\n\
cd /var/www && python3 -m http.server $PORT --bind 0.0.0.0 &\n\
HTTP_PID=$!\n\
/usr/sbin/sshd -D &\n\
SSH_PID=$!\n\
autossh -M 0 -o "StrictHostKeyChecking=no" -o "ServerAliveInterval=30" -o "ServerAliveCountMax=3" -R ubantu:22:localhost:22 serveo.net &\n\
TUNNEL_PID=$!\n\
trap "kill $HTTP_PID $SSH_PID $TUNNEL_PID 2>/dev/null; exit 0" SIGINT SIGTERM\n\
while true; do\n\
    sleep 30\n\
done' > /start && chmod 755 /start

# Logs and healthcheck
RUN mkdir -p /var/log
HEALTHCHECK --interval=30s --timeout=10s CMD curl -fs http://localhost:${PORT:-8000}/ || exit 1

EXPOSE 8000 22
CMD ["/start"]     
