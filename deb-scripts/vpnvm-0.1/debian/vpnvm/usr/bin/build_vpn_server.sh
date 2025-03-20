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

# Function to execute a remote SSH command
execute_remote_command() {
  local user="$1"
  local ip="$2"
  local command="$3"

  ssh -o StrictHostKeyChecking=no "$user@$ip" "$command"
  local result=$?
  if [[ $result -eq 0 ]]; then
    log_info "Command successfully executed on $user@$ip"
  else
    log_error "Error executing command on $user@$ip (code $result)"
  fi
  return $result
}

# 1. Installing iptables (checking for existence or installing)
log_info "Checking for iptables..."
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
sudo iptables -F
sudo iptables -X
sudo iptables -P INPUT ACCEPT
sudo iptables -P OUTPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables-save
log_info "Firewall is cleared"

# 3. Installing openvpn and easy-rsa (checking for existence or installing)
# Checking for openvpn
log_info "Checking for OpenVPN..."
if command -v openvpn &> /dev/null; then
	log_info "OpenVPN is already installed."
else
	log_info "OpenVPN is not installed."
	log_info "Installing OpenVPN."
	sudo apt update
	sudo apt install openvpn -y
	log_info "OpenVPN is installed."
fi

# Checking for easy-rsa
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


# 4. Creating VPN-server
log_info "Creating VPN-server..."
check_input "Enter ip-address of certification server: " cavm_ip
check_input "Enter root's nickname on certification server : " nickname

# Initzialisation pki
cd /home/"$(whoami)"/easy-rsa
./easyrsa init-pki

# Generating server.req, copying server.key to opevpn folder, copying server.req to ceritifcation server
log_info "Generating server.req..."
./easyrsa gen-req server nopass

log_info "Copying server.key to openvpn folder..."
sudo cp ~/easy-rsa/pki/private/server.key /etc/openvpn/server/

log_info "Copying server.req to certification server..."
scp ~/easy-rsa/pki/reqs/server.req "$nickname"@"$cavm_ip":/home/"$nickname"/easy-rsa/pki/reqs/

# Signing request on certification server
while true
do
	log_info "Please sign the servers request on certification server"
	read -p "Enter (done) or (exit): " comm
	case "$comm" in
		done)
			log_info "Continuation..."
			break
			;;
		exit)
			log_error "Breaking script by user command ..."
			exit 2
			;;
		*)
			log_error "Error! Unknown command $comm"
			;;
	esac
done

# Copying certificates to openvpn folder
log_info "Copying certificates to OpenVPN folder..."

scp "$nickname"@"$cavm_ip":/home/"$nickname"/easy-rsa/pki/ca.crt ~/
scp "$nickname"@"$cavm_ip":/home/"$nickname"/easy-rsa/pki/issued/server.crt ~/
sudo mv ~/ca.crt /etc/openvpn/server/
sudo mv ~/server.crt /etc/openvpn/server/

# Generating ta.key, copying ta.key to openvpn
log_info "Generating ta.key..."
openvpn --genkey secret ~/ta.key

log_info "Copying ta.key to OpenVPN folder..."
sudo cp ~/ta.key /etc/openvpn/server

# Creating folder fo clients
log_info "Creating folder for clients configs..."
if [ -d ~/clients ]; then
	sudo rm -r ~/clients
fi

mkdir -p ~/clients
mkdir -p ~/clients/keys
sudo chmod 700 ~/clients
# Creating request for each user and signing requests for each client
log_info "Creating requset for each user and signing requests for each client..."

while true
do
	read -p "Enter command: (create user), (done), (exit): " comm
	case "$comm" in
		"create user")
			read -p "Enter the name of the user you want to create a VPN configuration for: " client
			cd ~/easy-rsa
			./easyrsa gen-req "$client" nopass
			cp ~/easy-rsa/pki/private/"$client".key ~/clients/keys/
			scp ~/easy-rsa/pki/reqs/"$client".req "$nickname"@"$cavm_ip":/home/"$nickname"/easy-rsa/pki/reqs/
			while true
			do
				log_info "Please sign the clients request on certification server"
				read -p "Enter (done) or (exit): " comma
				case "$comma" in
					done)
						log_info "Contonuation..."
						break
						;;
					exit)
						log_error "Breaking script by users command..."
						exit 2
						;;
					*)
						log_error "Error! Unknown command $comma"
						;;
				esac
			done
			scp "$nickname"@"$cavm_ip":/home/"$nickname"/easy-rsa/pki/issued/"$client".crt ~/
			sudo cp ~/"$client".crt /etc/openvpn/server/
			mv ~/"$client".crt ~/clients/keys/
			;;
		done)
			log_info "Continuation..."
			break
			;;
		exit)
			log_error "Breaking script by users command..."
			exit 2
			;;
		*)
			log_error "Error! Unknown command $comm"
			;;
	esac
done
mv ~/ta.key ~/clients/keys/
sudo cp /etc/openvpn/server/ca.crt ~/clients/keys/
sudo chown "$nickname":"$nickname" ~/clients/keys/*

# 5. Installing prometheus-node-exporter for monitoring server (checking for existence or installing)
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

# 6. Creating user for exporter
log_info "Creating user for exporter..."
check_user=$(echo $(sudo cat /etc/group | grep exporter))
if [ ! "$check_user" == "" ];then
	sudo deluser exporter
	sudo delgroup exporter
	if [ -d /home/exporter ]; then
		sudo rm -r /home/exporter
	fi
fi
sudo adduser exporter
sudo adduser $(whoami) exporter
sudo chmod g=rwx /home/exporter


# 7. Installing ssh-connetion to exporter, exporters, unzip and GO
read -s -p "Enter password for user exporter: " password
while true
do
	read -p "Enter ip address of vpn-server: " vpnvm_ip
	if [ $(ping "$vpnvm_ip" | echo $?) -eq 1 ]; then
		log_error "Invalid ip-address $vpnvm_ip. Please try again."
	else
		break
	fi
done

# Installing ssh-connection to exporter user
log_info "Creating authorized_keys file to exporter user..."
sudo mkdir /home/exporter/.ssh
sudo chown exporter:exporter /home/exporter/.ssh
sudo touch /home/exporter/.ssh/authorized_keys
sudo chown -R exporter:exporter /home/exporter/.ssh/
sudo cp ~/.ssh/authorized_keys /home/exporter/.ssh/

sudo sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

sudo systemctl restart ssh

# Downloading ping_exporter
execute_remote_command "exporter" "$vpnvm_ip" "wget https://github.com/czerwonk/ping_exporter/archive/refs/heads/main.zip"

# Downloading openvpn_exporter
execute_remote_command "exporter" "$vpnvm_ip" "wget https://github.com/kumina/openvpn_exporter/archive/refs/heads/master.zip"

# Installing unzip (checking existence or installing)
log_info "Checking for unzip..."
if command -v unzip &> /dev/null; then
	log_info "Unzip is already installed."
else
	log_info "Unzip is not installed."
	log_info "Installing unzip..."
	sudo apt update
	sudo apt install unzip -y
	log_info "Unzip is installed."
fi

# Installing GO (checking existence or installing)
log_info "Checking for GO..."
if command -v go &> /dev/null; then
	log_info "GO is already installed."
else
	log_info "GO is not installed."
	log_info "Installing GO..."
	sudo apt update
	sudo apt install golang-go -y
	log_info "GO is installed."
fi

# Creating directory for exporters
log_info "Creating directory fo exporters..."
execute_remote_command "exporter" "$vpnvm_ip" "mkdir /home/exporter/exporters"
execute_remote_command "exporter" "$vpnvm_ip" "mv main.zip /home/exporter/exporters && mv master.zip /home/exporter/exporters"
execute_remote_command "exporter" "$vpnvm_ip" "unzip /home/exporter/exporters/main.zip -d /home/exporter/exporters/ && rm /home/exporter/exporters/main.zip && mv /home/exporter/exporters/ping_exporter-main /home//exporter/exporters/ping_exporter"
execute_remote_command "exporter" "$vpnvm_ip" "unzip /home/exporter/exporters/master.zip -d /home/exporter/exporters/ && rm /home/exporter/exporters/master.zip && mv /home/exporter/exporters/openvpn_exporter-master /home/exporter/exporters/openvpn_exporter"

# Installing ping exporter and openvpn exporter
log_info "Installing exporters..."
execute_remote_command "exporter" "$vpnvm_ip" "sed -i 's/^go 1.24/go 1.23.1/' /home/exporter/exporters/ping_exporter/go.mod"
execute_remote_command "exporter" "$vpnvm_ip" "cd /home/exporter/exporters/ping_exporter && go generate && go build"

execute_remote_command "exporter" "$vpnvm_ip" "cd /home/exporter/exporters/openvpn_exporter && go generate && go build"

# Creating services for exporters
log_info "Creating services for exporters..."
touch ping_exporter.service
echo "[Unit]
Description=Ping Exporter
After=network.target

[Service]
User=exporter
Group=exporter
ExecStart=/home/exporter/exporters/ping_exporter/ping_exporter '$vpnvm_ip'
Restart=on-failure

[Install]
WantedBy=multi-user.target" > ping_exporter.service
sudo mv ping_exporter.service /etc/systemd/system/

if [ ! -f /var/log/openvpn/openvpn-status.log ]; then
	sudo touch /var/log/openvpn/openvpn-status.log
fi
sudo chgrp exporter /var/log/openvpn/openvpn-status.log
sudo chmod 660 /var/log/openvpn/openvpn-status.log

touch openvpn_exporter.service
echo "[Unit]
Description=OpenVPN Exporter
After=network.target

[Service]
User=exporter
Group=exporter
ExecStart=/home/exporter/exporters/openvpn_exporter/openvpn_exporter -openvpn.status_paths=/var/log/openvpn/openvpn-status.log
Restart=on-failure

[Install]
WantedBy=multi-user.target" > openvpn_exporter.service
sudo mv openvpn_exporter.service /etc/systemd/system/

# Enabling and starting services
log_info "Enabling and starting services..."

sudo systemctl enable ping_exporter.service
sudo systemctl enable openvpn_exporter.service

sudo setcap cap_net_raw+ep /home/exporter/exporters/ping_exporter/ping_exporter

sudo systemctl start ping_exporter.service
sudo systemctl start openvpn_exporter.service

# 8. Configurating OpenVPN
log_info "Configurating OpenVPN..."
mkdir ~/clients/files
sudo cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/clients/base.conf
sudo cp /usr/share/doc/openvpn/examples/sample-config-files/server.conf /etc/openvpn/server/

# 9. Finishing first script
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

log_info "Please configure /etc/openvpn/server/server.conf file"
log_info "Please configure ~/clients/files/base.conf"
log_info "Please configure /etc/sysctl.conf file"
log_info "After configuration pleast start (continue_build_vpn.sh) script"
exit 0

