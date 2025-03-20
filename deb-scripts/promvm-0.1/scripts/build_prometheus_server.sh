#!/bin/bash

#set -x  # Uncomment for debugging
set -e  # Exit on first error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}INFO: $1${NC}"
}

log_error() {
  echo -e "${RED}ERROR: $1${NC}"
}

# Function to validate input
check_input() {
  local prompt="$1"
  local varname="$2"
  local regex="$3"
  local input

  while true; do
    read -r -p "$prompt" input
    if [[ "$input" =~ $regex ]]; then
      eval "$varname=\"\$input\""
      break
    else
      log_error "Invalid input. Please try again."
    fi
  done
}

# Installing prometheus, alertmanager and node-exporter (checking for existence or installing)
log_info "Installing prometheus, alertmanager and node-exporter..."

# Checking for prometheus
log_info "Checking for prometheus..."
if command -v prometheus &> /dev/null; then
	log_info "Prometheus is already installed."
else
	log_info "Prometheus is not installed."
	log_info "Installing pormetheus..."
	sudo apt update
	sudo apt install prometheus -y
	log_info "Promehteus is installed."
fi

# Checking for prometheus-alertmanager
log_info "Checking for prometheusp-alertmanager..."
if command -v prometheus-alertmanager &> /dev/null; then
        log_info "Prometheus-alertmanager is already installed."
else
        log_info "Prometheus-alertmanager is not installed."
        log_info "Installing pormetheus-alertmanager..."
        sudo apt update
        sudo apt install prometheus-alertmanager -y
        log_info "Promehteus-alertmanager is installed."
fi

# Checking for prometheus-node-exporter
log_info "Checking for prometheus-node-exporter..."
if command -v prometheus-node-exporter &> /dev/null; then
        log_info "Prometheus-node-exporter is already installed."
else
        log_info "Prometheus-node-exporter is not installed."
        log_info "Installing pormetheus-node-exporter..."
        sudo apt update
        sudo apt install prometheus-node-exporter -y
        log_info "Promehteus-node-exporter is installed."
fi

# Editing prometheus config
log_info "Editing prometheus config..."
if [ -f /etc/prometheus/prometheus.yml ]; then
	sudo rm /etc/prometheus/prometheus.yml
fi
touch prometheus.yml
check_input "Enter ip-address of your main machine: " ip_main '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
check_input "Enter ip-address of your certification server: " ip_ca '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
check_input "Enter ip-address of your OpenVPN server: " ip_vpn '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
echo "global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
  - static_configs:
    - targets: ['localhost:9093']

rule_files:
  - rules.yml

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
    - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
    - targets: ['localhost:9100', '$ip_main:9100', '$ip_vpn:9100', '$ip_ca:9100']
  - job_name: 'openvpn'
    static_configs:
    - targets: ['$ip_vpn:9176']
  - job_name: 'ping'
    static_configs:
    - targets: ['$ip_vpn:9427']" > prometheus.yml
sudo mv prometheus.yml /etc/prometheus/

# Editing alertmanager config
log_info "Editing alertmanager config..."
if [ -f /etc/prometheus/alertmanager.yml ]; then
	sudo rm /etc/prometheus/alertmanager.yml
fi
touch alertmanager.yml
check_input "Enter smtp email TO: " mail_to "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"

echo "route:
  group_by: ['alertname']
  receiver: email-me

receivers:
  - name: email-me
    email_configs:
      - to: '$mail_to'
        from: 'floydyt279@gmail.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'floydyt279@gmail.com'
        auth_password: 'zmvicfoypnbxseuy'" > alertmanager.yml
sudo mv alertmanager.yml /etc/prometheus/

# Configuring rules file for alerting
log_info "Configuring rules file for alerting..."
if [ -f /etc/prometheus/rules.yml ]; then
	sudo rm /etc/prometheus/rules.yml
fi
sudo mv rules.yml /etc/prometheus/

# Enabling and starting prometheus
log_info "Enablins and starting prometheus..."
sudo systemctl enable prometheus

sudo systemctl start prometheus

log_info "Prometheus server is fully created."
