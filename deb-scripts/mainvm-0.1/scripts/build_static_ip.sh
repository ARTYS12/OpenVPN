#!/bin/bash

# Set -e: Exit immediately if a command exits with a non-zero status.
set -e

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

# Validate IP address format
is_valid_ip() {
  local ip="$1"
  local regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
  [[ "$ip" =~ $regex ]]
}

# Function to execute a remote command with password prompt and heredoc
execute_remote_command() {
  local user="$1"
  local ip_addr="$2"
  local command="$3"
  local config_file="$4"
  local config_content="$5"

  read -s -p "Enter password for $user@$ip_addr: " password
  if [[ -z "$password" ]]; then
    log_error "Password not entered. Skipping command on $user@$ip_addr."
    return 1  # Return non-zero status to indicate failure
  fi

  ssh "$user@$ip_addr" "echo '$password' | sudo -S bash -c 'cat << EOF > $config_file
$config_content
EOF
sudo chmod 600 $config_file && sudo netplan apply'"
  local result=$?
  if [[ $result -eq 0 ]]; then
    log_info "Successfully executed command on $user@$ip_addr."
    return 0
  else
    log_error "Error executing command on $user@$ip_addr. Exit code: $result"
    return 1
  fi
}

# Main Script Logic

log_info "Building static IP address configurations."

read -p "Enter the number of machines you want to configure: " num
if ! [[ "$num" =~ ^[0-9]+$ ]]; then
  log_error "Invalid input: Number of machines must be a positive integer."
  exit 1
fi

for ((i=1; i<=$num; i++))
do
  log_info "Configuring machine $i"

  read -p "Enter the current IP address of machine $i: " ip_addr_old
  if ! is_valid_ip "$ip_addr_old"; then
    log_error "Invalid input: Current IP address is not in a valid format."
    continue # Skip to the next iteration
  fi

  read -p "Enter the root user's name on machine with IP $ip_addr_old: " name
  if [[ -z "$name" ]]; then
    log_error "Invalid input: Username cannot be empty."
    continue
  fi

  read -p "Enter the new static IP address you want to set up on machine '$name'@'$ip_addr_old': " ip_addr_new
  if ! is_valid_ip "$ip_addr_new"; then
    log_error "Invalid input: New IP address is not in a valid format."
    continue
  fi

  read -p "Enter the subnet mask (e.g., 192.168.1.1): " subnet
  if ! is_valid_ip "$subnet"; then
    log_error "Invalid input: Subnet mask is not in a valid format."
    continue
  fi

  # Find the interface name remotely (added timeout to prevent hangs)
  interface=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$name@$ip_addr_old" "ip -o a | awk -v ip='$ip_addr_old' '\$4 == ip || \$4 ~ \"^\"ip\"(/[^/]+)?\" {getline; print \$2}' | sed 's/://g'" 2>/dev/null)

  if [[ -z "$interface" ]]; then
    log_error "Could not determine interface name on $name@$ip_addr_old.  Please verify the current IP address and SSH connectivity."
    continue
  fi

  static_ip="network:
  version: 2
  renderer: networkd
  ethernets:
    $interface:
      dhcp4: no
      addresses:
       - $ip_addr_new/24
      routes:
       - to: 0.0.0.0/0
         via: $subnet
      nameservers:
        addresses:
         - 8.8.8.8
         - 8.8.4.4
"

  log_info "Generating static IP configuration for $name@$ip_addr_old:"
  echo "$static_ip"

  # Apply the configuration remotely
  log_info "Applying configuration for $name@$ip_addr_old"

  # Execute remote commands using heredoc and execute_remote_command
  if execute_remote_command "$name" "$ip_addr_old" "Setting static IP config" "/etc/netplan/01-netcfg.yaml" "$static_ip"; then
      log_info "Successfully applied static IP configuration to machine with current IP $ip_addr_old, new IP is $ip_addr_new"
  else
    log_error "Failed to apply static IP configuration to machine with current IP $ip_addr_old."
  fi

done

log_info "Script completed."
