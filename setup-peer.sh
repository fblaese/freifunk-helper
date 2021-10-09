#!/bin/bash

set -e
set -o pipefail

SERVER="ff1.zbau.f3netze.de"
PUBKEY="1DjlSgEXl6fBWTSPwa8yrHF7wQ8qFU18uXbuVRUuSBY="


error() {
	echo Error: "$@" 2>&1
}

get_random_port() {
	local port=$(comm -1 -3 <(grep -r listen-port /etc/network/ | sed 's/.*listen-port \([0-9]*\).*/\1/' | sort) <(for f in {31600..31800}; do echo $f; done) | shuf -n1)

	echo "$port"

	return 0
}

check_port() {
	local port="$1"

	grep -r listen-port /etc/network/ | grep "$port" >/dev/null
	[ $? -eq "0" ] && error "Given port already in use!" && return 1

	return 0
}

check_name() {
	local name="$1"

	grep -r "wg_$name" /etc/network/interfaces.d >/dev/null
	[ $? -eq "0" ] && error "Given name already in use!" && return 1

	return 0
}

setup_wireguard() {

	local name="$1"
	local contactaddress="$2"
	local peerkey="$3"
	local port="$4"

	wg_config=$(cat <<EOF

##
# $contactaddress
##
auto wg_$name
iface wg_$name inet6 static inherits wg
	pre-up wg set \$IFACE peer $peerkey endpoint [::1]:33433 allowed-ips ::/0,0.0.0.0/0
	pre-up wg set \$IFACE listen-port $port
iface wg_$name inet static inherits wg
EOF
)

	echo "$wg_config" >> /etc/network/interfaces.d/30-wg

	ifup "wg_$name"

	return 0
}

setup_bird() {
	local name="$1"
	local rxcost="$2"

	echo "interface \"wg_$name\" { rxcost $rxcost; };" >> /etc/bird/babelpeers.conf

	birdc c

	return 0
}

read_args() {
	while [ -z "$name" ]; do
		read -p "Enter name (without prefix): " name
		[ -z "$name" ] && error "Empty name not allowed!"
		check_name "$name" || name=""
	done

	while [ -z "$contact" ]; do
		read -p "Enter contact: " contact
		[ -z "$contact" ] && error "Empty contact not allowed!"
	done

	while [ -z "$peerkey" ]; do
		read -p "Enter peerkey: " peerkey
		[ -z "$peerkey" ] && error "Empty peerkey not allowed!"
	done

	read -p "Enter rxcost [4096]: " rxcost
	rxcost=${rxcost:-4096}

	while [ -z "$port" ]; do
		read -p "Enter port [-1]: " port
		port=${port:-$(get_random_port)}
		check_port "$port" || port=""
	done
}

print_mail() {
	local name="$1"
	local rxcost="$2"
	local port="$3"

	cat <<EOF
Hallo $name,

Ich habe dir einen Wireguard-Tunnel angelegt:

Server: $SERVER
Port: $port
Public Key: $PUBKEY

Die MTU steht auf unserer Seite auf 1412 Byte (optimal für PPPoE DSL/Glas und IPv6 Transport) und eine Babel rxcost von $rxcost.
Sag bitte Bescheid, wenn du für MTU oder rxcost etwas anderes haben möchtest.
Deine E-Mail Adresse habe ich als technischen Kontakt am Server hinterlegt.

Für das Peering gilt das Pico Peering Agreement [1] sowie die Regeln der Freifunk Franken Community [2].
Bitte achte darauf, dass du nur Adressen announced, die du auch verwenden darfst (z.B. über das F3 Netze e.V. Subnetz Tool [3] erhaltene oder im Wiki [4] registrierte Adressen).

Für technische Fragen zum Peering kannst du dich jederzeit an uns wenden, für Probleme bei der Routereinrichtung wende dich bitte an die Community [5].

Gruß

[1] https://www.picopeer.net/PPA-de.shtml
[2] https://wiki.freifunk-franken.de/w/Portal:Layer3Peering#Regeln
[3] https://sub.f3netze.de/
[4a] https://wiki.freifunk-franken.de/w/Portal:Netz/IPv6
[4b] https://wiki.freifunk-franken.de/w/Portal:Netz
[5] https://wiki.freifunk-franken.de/w/Kommunikation
EOF
}

read_args

setup_wireguard "$name" "$contact" "$peerkey" "$port"
setup_bird "$name" "$rxcost"

echo; echo;

print_mail "$name" "$rxcost" "$port"
