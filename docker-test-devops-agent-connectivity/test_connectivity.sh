#!/bin/bash

# Get the Azure DevOps URLs and port from environment variables
AZURE_DEVOPS_ORG=${AZURE_DEVOPS_ORG:-myorg}
AZURE_DEVOPS_PORT=${AZURE_DEVOPS_PORT:-443}
AGENT_DOWNLOAD_URL=${AGENT_DOWNLOAD_URL:-https://vstsagentpackage.azureedge.net/agent/3.246.0/vsts-agent-win-x64-3.246.0.zip}

# reference: https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/windows-agent?view=azure-devops#im-running-a-firewall-and-my-code-is-in-azure-repos-what-urls-does-the-agent-need-to-communicate-with

# Function to print separator
print_separator() {
    echo "----------------------------------------"
}

# Function to test IP connectivity
test_ip() {
    local ip=$1
    local description=$2
    local is_optional=$3
    print_separator
    echo "Testing IP: $ip ($description)"
    print_separator

    # Test ping with timeout (optional)
    echo "1. Testing ping (optional)..."
    if timeout 5 ping -c 1 "$ip" > /dev/null 2>&1; then
        echo "✅ Ping successful"
    else
        echo "⚠️ Ping failed (this is normal for some Azure IPs)"
    fi

    # Test TCP connection
    echo "2. Testing TCP connection..."
    if timeout 5 nc -zv "$ip" "$AZURE_DEVOPS_PORT" > /dev/null 2>&1; then
        echo "✅ TCP connection to $ip:$AZURE_DEVOPS_PORT successful"
        print_separator
        return 0
    else
        echo "❌ TCP connection to $ip:$AZURE_DEVOPS_PORT failed"
        if [ "$is_optional" = "true" ]; then
            echo "⚠️ Note: This is an optional IPv6 test and may not be required"
        fi
        print_separator
        return 1
    fi
}

# Function to test connectivity to a URL
test_url() {
  local url=$1
  print_separator
  echo "Testing URL: $url"
  print_separator

  # Test DNS resolution
  echo "1. Testing DNS resolution..."
  if ! host "$url" > /dev/null 2>&1; then
    echo "❌ DNS resolution failed for $url"
    print_separator
    return 1
  else
    echo "✅ DNS resolution successful"
  fi

  # Test TCP connection with timeout
  echo "2. Testing TCP connection..."
  if timeout 5 nc -zv "$url" "$AZURE_DEVOPS_PORT" > /dev/null 2>&1; then
    echo "✅ TCP connection to $url:$AZURE_DEVOPS_PORT successful"

    # Test HTTPS connection with detailed error reporting
    echo "3. Testing HTTPS connection..."
    if curl -v --max-time 10 --connect-timeout 5 \
        --tlsv1.2 \
        --cacert /etc/ssl/certs/ca-certificates.crt \
        --fail --show-error \
        "https://$url" > /dev/null 2>&1; then
      echo "✅ HTTPS connection to $url:$AZURE_DEVOPS_PORT successful"
      print_separator
      return 0
    else
      echo "❌ HTTPS connection to $url:$AZURE_DEVOPS_PORT failed"
      # Try without certificate verification as fallback
      echo "4. Retrying HTTPS connection (insecure mode)..."
      if curl -v --max-time 10 --connect-timeout 5 \
          --tlsv1.2 \
          -k \
          --fail --show-error \
          "https://$url" > /dev/null 2>&1; then
        echo "✅ HTTPS connection successful with TLS 1.2 (insecure mode)"
        print_separator
        return 0
      else
        echo "❌ HTTPS connection failed with TLS 1.2 (insecure mode)"
        print_separator
        return 1
      fi
    fi
  else
    echo "❌ TCP connection to $url:$AZURE_DEVOPS_PORT failed"
    print_separator
    return 1
  fi
}

# Define URLs to test based on organization name
URLS="dev.azure.com \
      ${AZURE_DEVOPS_ORG}.pkgs.visualstudio.com \
      ${AZURE_DEVOPS_ORG}.visualstudio.com \
      ${AZURE_DEVOPS_ORG}.vsblob.visualstudio.com \
      ${AZURE_DEVOPS_ORG}.vsrm.visualstudio.com \
      ${AZURE_DEVOPS_ORG}.vssps.visualstudio.com \
      ${AZURE_DEVOPS_ORG}.vstmr.visualstudio.com \
      app.vssps.visualstudio.com \
      login.microsoftonline.com \
      management.core.windows.net \
      vstsagentpackage.azureedge.net"

# Define IP ranges to test with specific host addresses
# Using different IPs from the ranges that are known to be active
IPV4_TESTS="13.107.6.183 13.107.9.183 13.107.42.1 13.107.43.1"
IPV6_TESTS="2620:1ec:4::1 2620:1ec:a92::1 2620:1ec:21::1 2620:1ec:22::1"

# Print header
echo "Starting Azure DevOps Connectivity Tests"
echo "Organization: $AZURE_DEVOPS_ORG"
print_separator

# Test IPv4 addresses
echo "Testing IPv4 Addresses"
print_separator
failed_ip_tests=0
for ip in $IPV4_TESTS; do
    if ! test_ip "$ip" "Azure DevOps IPv4 address" "false"; then
        failed_ip_tests=$((failed_ip_tests + 1))
    fi
done

# Test IPv6 addresses (optional)
echo "Testing IPv6 Addresses (Optional)"
print_separator
failed_ipv6_tests=0
for ip in $IPV6_TESTS; do
    if ! test_ip "$ip" "Azure DevOps IPv6 address" "true"; then
        failed_ipv6_tests=$((failed_ipv6_tests + 1))
    fi
done

# Test URLs
echo "Testing URLs"
print_separator
failed_url_tests=0
for url in $URLS; do
  if ! test_url "$url"; then
    failed_url_tests=$((failed_url_tests + 1))
  fi
done

# Test agent download with timeout
print_separator
echo "Testing Agent Download"
print_separator
echo "URL: $AGENT_DOWNLOAD_URL"

if curl -v --max-time 30 --connect-timeout 10 \
    --tlsv1.2 \
    --cacert /etc/ssl/certs/ca-certificates.crt \
    --fail --show-error \
    "$AGENT_DOWNLOAD_URL" > /dev/null 2>&1; then
  echo "✅ Agent download successful"
else
  echo "❌ Agent download failed"
  failed_url_tests=$((failed_url_tests + 1))
fi

print_separator
echo "Test Summary:"
echo "IPv4 Tests Failed: $failed_ip_tests"
echo "IPv6 Tests Failed: $failed_ipv6_tests (Optional)"
echo "URL Tests Failed: $failed_url_tests"
print_separator

if [ $failed_ip_tests -eq 0 ] && [ $failed_url_tests -eq 0 ]; then
  echo "🎉 All required connectivity tests successful!"
  echo "Note: IPv6 tests are optional and may not be required for your environment"
  exit 0
else
  echo "❌ Some tests failed:"
  [ $failed_ip_tests -gt 0 ] && echo "- $failed_ip_tests IPv4 tests failed"
  [ $failed_ipv6_tests -gt 0 ] && echo "- $failed_ipv6_tests IPv6 tests failed (Optional)"
  [ $failed_url_tests -gt 0 ] && echo "- $failed_url_tests URL tests failed"
  exit 1
fi