#!/bin/bash

#set -x # Uncomment for debugging
set -e # Exit on first error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No color

log_info() {
	echo -e "${GREEN}INFO: $1${NC}"
}

log_error() {
	echo -e "${RED}ERROR: $1${NC}"
}

# Function for validate input
check_input() {
	local promt="$1"
	local varname="$2"
	local regex="$3"
	local input

	while true
	do
		read -r -p "$promt" input
		if [[ "$input" =~ $regex ]]; then
			eval "$varname=\"\$input\""
			break
		else
			log_error "Invalid input. Please try again."
		fi
	done
}

# 1. Installing iptables (checking for existence or installing)
log_info "Checking for iptables..."
sleep 1
if command -v iptables &> /dev/null; then
	log_info "Iptables is already installed."
else
	log_info "Iptables is not installed."
	log_info "Installing iptables..."
	sudo apt install iptables -y
	log_info "Iptables is installed."
fi

# 2. Clearing firewall
log_info "Clearing firewall..."
sleep 1


sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables-save

log_info "Firewall is cleared"

# 3. Installing prometheus-node-exporter for monitoring server (checking for existence or installing)
log_info "Checking for prometheus-node-exporter..."
sleep 1
if command -v prometheus-node-exporter &> /dev/null; then
	log_info "Prometheus-node-exporter is already installed."
else
	log_info "Prometheus-node-exporter is not installed."
	log_info "Installing promtheus-node-exporter..."
	sudo apt update
	sudo apt install prometheus-node-exporter -y
	log_info "Prometheus-node exporter is installed"
fi

# 4. Installing esay-rsa
log_info "Installing easy-rsa..."
sleep 1
sudo apt install easy-rsa -y
if [ -d /home/"$(whoami)"/easy-rsa ]; then
	if [ -f /home/"$(whoami)"/easy-rsa/vars ]; then
		sudo mv /home/"$(whoami)"/easy-rsa/vars /home/"$(whoami)"/
	fi
	sudo rm -r /home/"$(whoami)"/easy-rsa
else
	mkdir /home/"$(whoami)"/easy-rsa
fi
sudo ln -s /usr/share/easy-rsa/* ~/easy-rsa
sudo chown "$(whoami)":"$(whoami)" /home/"$(whoami)"/easy-rsa
sudo chown -R "$(whoami)":"$(whoami)" /home/"$(whoami)"/easy-rsa
log_info "Easy-rsa is installed."

# 5. Creating root's certificate
cd /home/"$(whoami)"/easy-rsa

# Initzialization PKI
log_info "Initzialisation pki..."
sleep 1

./easyrsa init-pki
log_info "Initzialisation pki completed."

# Creating root's certificate
log_info "Creating root's certificate..."
sleep 1

./easyrsa build-ca
log_info "Creating root's certificate completed."

# 6. Building firewall with using iptables
log_info "Building firewall..."
sleep 1

# Installing netfilter-persistent for saving iptables rules (checking for existence or installing)
log_info "Checking for netfilter-persistent..."
sleep 1
if command -v netfilter-persistent &> /dev/null; then
	log_info "Netfilter-persistent is already installed."
else
	log_info "Netfilter-persistent is not instaled."
	log_info "Installing netfilter-persistent..."
	sudo apt install netfilter-persistent -y
	log_info "Netfilter-persistent is installed."
fi

# Creating iptables rules
log_info "Creating iptables rules..."
sleep 1

check_input "Enter ip-address of prometheus server: " promvm_ip "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
check_input "Enter port of node_exporter (e.g. default '9100'): " node_exporter_port "^[0-9]+$"

sudo iptables -A INPUT -j DROP
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp -s "$promvm_ip" --dport "$node_exporter_port" -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -j DROP
sudo iptables -A INPUT -j LOG --log-prefix "DROPPED: "
sudo netfilter-persistent save

log_info "Iptables rules is created and saved."
log_info "Certification server is created."
