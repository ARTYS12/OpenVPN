#!/bin/bash

sudo iptables -F
sudo iptables -X
sudo iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
sudo iptables -t nat -F POSTROUTING

sudo apt install iptables-persistent -y

interface=$1
proto=$2
port=$3
read -p "Enter ssh port: " ssh_port
read -p "Enter machines ip-address who can connect to VPN-server via SSH: " trusted_ip
# OpenVPN
sudo iptables -A INPUT -i "$interface" -m state --state NEW -p "$proto" --dport "$port" -j ACCEPT
# Allow TUN interface connections to OpenVPN server
sudo iptables -A INPUT -i tun+ -j ACCEPT
# Allow TUN interface connections to be forwarded through other interfaces
sudo iptables -A FORWARD -i tun+ -j ACCEPT
sudo iptables -A FORWARD -i tun+ -o "$interface" -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i "$interface" -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT
# NAT the VPN client traffic to the internet
sudo iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$interface" -j MASQUERADE

if [ -n "$trusted_ip" ]; then
	sudo iptables -A INPUT -p tcp --dport $ssh_port -s $trusted_ip -i $interface -j ACCEPT
else
	sudo iptables -A INPUT -p tcp --dport $ssh_port -i $interface -j ACCEPT
fi

sudo iptables -A OUTPUT -o $interface -m conntrack --ctstate NEW -j DROP

sudo iptables -A INPUT -j LOG --log-prefix "IPTABLES_DROP: "
# Allow traffic for prometheus exporters
read -p "Enter ip-address of prometheus server: " ip_promvm
read -p "Enter port of node_exporter (e.g. default 9100): " port_node_exporter
read -p "Enter port of openvpn_exporter (e.g. default 9176): " port_openvpn_exporter
read -p "Enter port of ping_exporter (e.g. default 9427): " port_ping_exporter

sudo iptables -A INPUT -p tcp -s $ip_promvm --dport $port_node_exporter -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ip_promvm --dport $port_openvpn_exporter -j ACCEPT
sudo iptables -A INPUT -p tcp -s $ip_promvm --dport $port_ping_exporter -j ACCEPT

sudo netfilter-persistent save
