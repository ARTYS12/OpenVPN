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


log_info "Creating backup..."
if [ ! -d /home/"$(whoami)"/deb-packages ]; then
        mkdir /home/"$(whoami)"/dep-packages
fi
log_info "Please move your scripts for cavm, vpnvm, mainvm and promvm into ~/deb-packages folder."
cd /home/"$(whoami)"/deb-packages
git add .
DATE=$(date +%Y-%m-%d)
MESSAGE="Backup created ($DATE) and moved to GitLab."
git commit -m "$MESSAGE"
git push origin master


