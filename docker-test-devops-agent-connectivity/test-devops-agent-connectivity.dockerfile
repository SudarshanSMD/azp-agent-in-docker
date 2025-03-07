# Use a lightweight base image with necessary tools
FROM alpine:latest

# Install necessary tools with error handling
RUN apk update && \
    apk add --no-cache \
    curl \
    openssl \
    bash \
    netcat-openbsd \
    bind-tools \
    iputils \
    ca-certificates \
    ipcalc

# Accept build arguments
ARG AZURE_DEVOPS_ORG=myorg

# Set the Azure DevOps URLs and ports
ENV AZURE_DEVOPS_ORG=${AZURE_DEVOPS_ORG}
ENV AZURE_DEVOPS_PORT=443
ENV AGENT_DOWNLOAD_URL=https://vstsagentpackage.azureedge.net/agent/3.246.0/vsts-agent-win-x64-3.246.0.zip

# Create a script to test connectivity
COPY test_connectivity.sh /test_connectivity.sh
RUN chmod +x /test_connectivity.sh

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Run the entrypoint script when the container starts
CMD ["/entrypoint.sh"]