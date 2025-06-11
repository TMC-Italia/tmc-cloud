FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    build-essential \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Create runner user
RUN useradd -m -s /bin/bash runner
USER runner
WORKDIR /home/runner

# Download and install GitHub Actions runner
RUN mkdir actions-runner && cd actions-runner \
    && curl -o actions-runner-linux-x64-2.311.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.311.0/actions-runner-linux-x64-2.311.0.tar.gz \
    && tar xzf ./actions-runner-linux-x64-2.311.0.tar.gz \
    && rm actions-runner-linux-x64-2.311.0.tar.gz

# Copy entrypoint script
COPY entrypoint.sh /home/runner/entrypoint.sh
USER root
RUN chmod +x /home/runner/entrypoint.sh
USER runner

ENTRYPOINT ["/home/runner/entrypoint.sh"]