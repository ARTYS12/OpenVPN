#!/bin/bash

# set -x # Uncomment for debugging
set -e # Exit on first error

# 1. Creating root certificate



#
# Initialisation pki
#

./easyrsa init-pki

#
# Creating root certificate
#

./easyrsa build-ca

echo "------------"
echo "Root certificate is successfully created"
echo "------------"
