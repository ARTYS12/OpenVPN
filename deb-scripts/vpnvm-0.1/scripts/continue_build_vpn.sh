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


# Restarting sysctl.conf
log_info "Restarting sysctl.conf..."
sudo sysctl -p

# Creating iptables rules
log_info "Creating iptables rules..."
iptables.sh enp0s3 udp 1194

# Enabling OpenVPN service
log_info "Enabling and starting OpenVPN services..."
sudo systemctl -f enable openvpn-server@server.service
sudo systemctl start openvpn-server@server.service
sudo systemctl status openvpn-server@server.service > ~/status_openvpn

# Creating clients configs
log_info "Creating clients configs..."
cd ~/clients
while true
do
	read -p "Enter command: (create config), (done): " comm
	case "$comm" in
		"create config")
			read -p "Enter vpn-client name: " client
			make_config.sh "$client"
			log_info "Config for $client is ready."
			;;
		"done")
			log_info "Finishing..."
			sleep 5
			log_info "Please copy configs from ~/clients/files to each client"
			exit 0
			;;
		*)
			log_error "Error! Unknown command $comm"
			;;
	esac
done

log_info "OpenVPN server is fully created."
