#!/bin/bash

set -e

cd /home/runner/actions-runner

# Configure the runner
./config.sh --url https://github.com/${GITHUB_REPOSITORY} --token ${GITHUB_TOKEN} --name $(hostname) --work _work --labels self-hosted,linux,x64,docker --unattended

# Start the runner
./run.sh