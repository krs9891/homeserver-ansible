#!/usr/env/bin bash

# This script generates a WireGuard configuration file for a NordVPN server
# and saves it to a file. The script also connects to the recommended NordVPN
# server and disconnects after the configuration file is generated.

# https://gist.github.com/bluewalk/7b3db071c488c82c604baf76a42eaad3

# Thanks to darki73 for the script

# At this point it is not used by the role. Manual execution is required.

required_packages=()

check_if_connected() {
    if [ -n "$(nordvpn status | grep "Status: Connected")" ]; then
        return 0
    else
        return 1
    fi
}

# Check whether jq package is installed
if ! command -v jq &>/dev/null; then
    required_packages+=("jq")
fi

# Check whether wireguard package is installed
if ! command -v wg &>/dev/null; then
    required_packages+=("wireguard")
fi

# Check if curl package is installed
if ! command -v curl &>/dev/null; then
    required_packages+=("curl")
fi

# Check if nordvpn package is installed
if ! command -v nordvpn &>/dev/null; then
    required_packages+=("nordvpn")
fi

# Install missing packages required to generate the configuration file
if [ ${#required_packages[@]} -gt 0 ]; then
    sudo apt install -y "${required_packages[@]}"
fi

if ! check_if_connected; then
    nordvpn connect
fi

interface_name=$(sudo wg show | grep interface | cut -d " " -f 2)
private_key=$(sudo wg show $interface_name private-key | cut -d " " -f 2)
my_address=$(ip -f inet addr show $interface_name | grep inet | awk '{print $2}' | cut -d "/" -f 1)

api_response=$(curl -s "https://api.nordvpn.com/v1/servers/recommendations?&filters\[servers_technologies\]\[identifier\]=wireguard_udp&limit=1")
host=$(jq -r '.[]|.hostname' <<<$api_response)
ip=$(jq -r '.[]|.station' <<<$api_response)
city=$(jq -r '.[]|(.locations|.[]|.country|.city.name)' <<<$api_response)
country=$(jq -r '.[]|(.locations|.[]|.country|.name)' <<<$api_response)
server_public_key=$(jq -r '.[]|(.technologies|.[].metadata|.[].value)' <<<$api_response)

server_identifier=$(echo $host | cut -d "." -f 1)
configuration_file="nordvpn-$server_identifier.conf"

{
    echo "# Configuration for $host ($ip) in $city, $country"
    echo "[Interface]"
    echo "Address = $my_address"
    echo "PrivateKey = $private_key"
    echo ""
    echo "[Peer]"
    echo "PublicKey = $server_public_key"
    echo "AllowedIPs = 0.0.0.0/0"
    echo "Endpoint = $host:51820"
} >"$configuration_file"

if check_if_connected; then
    nordvpn disconnect
fi
