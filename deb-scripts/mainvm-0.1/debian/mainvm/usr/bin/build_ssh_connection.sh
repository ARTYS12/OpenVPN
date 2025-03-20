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

# 1. Installing SSH (checking for existence instead of installing)
log_info "Checking for SSH..."
sleep 1
if command -v ssh &> /dev/null; then
    log_info "SSH is installed."
else
    log_error "SSH is not installed. Please install SSH manually on each machine. (sudo apt update && sudo apt upgrade && sudo apt install ssh).  The script will exit."
    exit 1
fi

# 2. Creating SSH keys

log_info "Creating SSH keys on each machine..."

declare -a names
declare -a ip_addrs

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

# Prompt for the number of servers
check_input "Enter the number of servers you want to connect to via SSH: " num '^[0-9]+$'

# Prompt for server information
for ((i=1; i<=$num; i++)); do
  check_input "Enter username on server $i: " name '^[a-zA-Z0-9_-]+$'
  names+=("$name")
  check_input "Enter IP address of server $i: " ip_addr '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
  ip_addrs+=("$ip_addr")
done

# Changing sshd_config
log_info "Configuring sshd_config..."

for ((i=0; i<${#names[@]}; i++)); do
  log_info "Editing sshd_config on ${names[$i]}@${ip_addrs[$i]}..."

  read -s -p "Enter password for ${names[$i]}@${ip_addrs[$i]}: " password
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^#PubkeyAuthentication no/PubkeyAuthentication no/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
  if [ $? -eq 0 ]; then
    log_info "sshd_config successfully edited on ${names[$i]}@${ip_addrs[$i]}."
    log_info "Restarting the SSH service on ${names[$i]}@${ip_addrs[$i]}."
    execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S systemctl restart ssh"
    #check_input "Enter (done) after restarting the service on ${names[$i]}@${ip_addrs[$i]}: " comma "done"
  else
    log_error "Error editing sshd_config on ${names[$i]}@${ip_addrs[$i]}"
  fi
done

# Create keys
for ((i=0; i<${#names[@]}; i++)); do
  log_info "Processing ${names[$i]}@${ip_addrs[$i]}..."
  SSH_KEYGEN="ssh-keygen -t rsa -f ~/.ssh/id_rsa -N ''" # Added -N '' to avoid password prompt
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "$SSH_KEYGEN"

  if [[ $? -eq 0 ]]; then
    log_info "SSH key successfully created on ${names[$i]}@${ip_addrs[$i]}"
  else
    log_error "Error creating key on ${names[$i]}@${ip_addrs[$i]}"
  fi
done

# 4. Collecting public keys

log_info "Collecting public keys..."

if [ -e "$HOME/authorized_keys" ]; then
  rm "$HOME/authorized_keys"
fi
touch "$HOME/authorized_keys"

for ((i=0; i<${#names[@]}; i++)); do
  log_info "Getting key from ${names[$i]}@${ip_addrs[$i]}..."
  scp -o StrictHostKeyChecking=no "${names[$i]}"@"${ip_addrs[$i]}":~/.ssh/id_rsa.pub "$HOME/"
  if [ $? -eq 0 ]; then
    cat "$HOME/id_rsa.pub" >> "$HOME/authorized_keys"
    rm "$HOME/id_rsa.pub"
  else
    log_error "Failed to get key from ${names[$i]}@${ip_addrs[$i]}"
  fi
done

log_info "SSH key collection complete. Please check the file $HOME/authorized_keys."
sleep 2
cat $HOME/authorized_keys
check_input "Enter (done) if it's all good: " comma "done"

# 5. Adding keys to each server

log_info "Adding keys to each server..."

for ((i=0; i<${#names[@]}; i++)); do
  log_info "Sending authorized_keys to ${names[$i]}@${ip_addrs[$i]}..."
  scp -o StrictHostKeyChecking=no "$HOME/authorized_keys" "${names[$i]}"@"${ip_addrs[$i]}":~/.ssh/authorized_keys
  if [ $? -eq 0 ]; then
      log_info "Keys successfully added to ${names[$i]}@${ip_addrs[$i]}"
  else
      log_error "Error adding keys to ${names[$i]}@${ip_addrs[$i]}"
  fi
done

# 6. Installing node_exporter

log_info "Installing prometheus-node-exporter..."

for ((i=0; i<${#names[@]}; i++)); do
  log_info "Installing node_exporter on ${names[$i]}@${ip_addrs[$i]}"

  #Prompt for password if sudoers is not configured
  read -s -p "Enter password for ${names[$i]}@${ip_addrs[$i]}: " password
  if [[ -z "$password" ]]; then
    log_error "Password not entered.  Installation of node_exporter skipped on ${names[$i]}@${ip_addrs[$i]}."
    continue
  fi

  #Install node_exporter using the password entered
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S apt update && echo '$password' | sudo -S apt install prometheus-node-exporter -y"

  if [ $? -eq 0 ]; then
    log_info "Successfully installed node_exporter on ${names[$i]}@${ip_addrs[$i]}"
  else
    log_error "Error installing node_exporter on ${names[$i]}@${ip_addrs[$i]}"
  fi

done

# 7. Configuring sshd_config
log_info "Configuring sshd_config..."

for ((i=0; i<${#names[@]}; i++)); do
  log_info "Editing sshd_config on ${names[$i]}@${ip_addrs[$i]}..."

  read -s -p "Enter password for ${names[$i]}@${ip_addrs[$i]}: " password
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication no/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config"
  execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
  if [ $? -eq 0 ]; then
    log_info "sshd_config successfully edited on ${names[$i]}@${ip_addrs[$i]}."
    log_info "Restarting the SSH service..."
    execute_remote_command "${names[$i]}" "${ip_addrs[$i]}" "echo '$password' | sudo -S systemctl restart ssh"
  else
    log_error "Error editing sshd_config on ${names[$i]}@${ip_addrs[$i]}"
  fi
done

# 8. Installing GIT (checking for existence or installing)
log_info "Checking for GIT..."
if command -v git &> /dev/null; then
	log_info "GIT is already installed."
else
	log_info "GIT is not installed."
	log_info "Installing GIT..."
	sudo apt install git -y
	log_info "GIT is installed."
fi

# 9. Creating backuper for deb-packages
log_info "Creating backuper..."
if [ ! -d /home/"$(whoami)"/deb-packages ]; then
	mkdir /home/"$(whoami)"/deb-packages
fi
log_info "Please move your scripts for cavm, vpnvm, mainvm and promvm into ~/deb-packages folder after script will be finished.."
sleep 2
cd /home/"$(whoami)"/deb-packages
git init --initial-branch=master
git remote add origin git@gitlab.skillbox.ru:artiom_abramov_1/devops-advanced.git

log_info "Script finished."
