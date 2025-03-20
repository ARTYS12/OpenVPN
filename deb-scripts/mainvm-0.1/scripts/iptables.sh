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

# 3. Installing netfilter-persistent (checking for existence or installing)
log_info "Checking for netfilter-persistent..."
if command -v netfilter-persistent &> /dev/null; then
	log_info "Netfilter-persistent is already installed."
else
	log_info "Netfilter-persistent is not installed."
	log_info "Installing netfilter-persistent..."
	sudo apt install netfilter-persistent -y
	log_info "Netfilter-persistent is installed."
fi

# 4. Creating iptables rules
log_info "Creating iptables rules..."
sudo iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -j LOG --log-prefix "DROPPED: "
sudo netfilter-persistent save

log_info "Iptables rules is created."
