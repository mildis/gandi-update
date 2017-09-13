#!/bin/bash

# requires : curl, jq, gandi.cli, tr, sort, wc, getopts

DOMAIN=example.com
HOST=my-server
TTL=86400
RETRY=5
INDEX=0

PUBLIC_IPV4_PROVIDERS=(http://ifconfig.me/ip https://ipv4.lafibre.info/ip.php)
PUBLIC_IPV4=

while getopts ":d:h:t:" OPT; do
	case ${OPT} in
		d)
			DOMAIN=${OPTARG}
			;;
		h)
			HOST=${OPTARG}
			;;
		t)
			TTL=${OPTARG}
			;;
		\?)
			echo "usage : $0 [-d <domain>] [-h <host>] [-t <TTL>]" >&2
			exit 255
			;;
	esac
done

for PUBPROV in ${PUBLIC_IPV4_PROVIDERS[@]}; do
	while [ x"${PUBLIC_IPV4[${INDEX}]}" = "x" -a ${RETRY} -gt 0 ]; do
		((RETRY--))
		PUBLIC_IPV4[${INDEX}]=$(curl -qs -m 30 ${PUBPROV})
	done
	((INDEX++))
done

CURRENT_IPV4=$(echo "${PUBLIC_IPV4[@]}"|tr ' ' '\n'|sort -u)

if [ $(echo "${CURRENT_IPV4}"|wc -l) -ne 1 ]; then
	echo "Not all IP found are the same :\n${CURRENT_IPV4}" >&2
	exit 1
fi

GANDI_DNS=$(gandi record list -f json ${DOMAIN}|jq -r '.[]|select(.name == '\"${HOST}\"')|[.name, .ttl, .type, .value]|@tsv'|tr '\t' ' ')
GANDI_IPV4=$(echo ${GANDI_DNS}|cut -d' ' -f4)

if [ -z "${CURRENT_IPV4}" ]; then
	echo "ERROR : cannot find current IPv4" >&2
	exit 2
fi

if [ -z "${GANDI_DNS}" -o -z "${GANDI_IPV4}" ]; then
	echo "ERROR : cannot get Gandi informations" >&2
	exit 3
fi

if [ x"${CURRENT_IPV4}" = x"${GANDI_IPV4}" ]; then
	echo "No update required" >&2
	exit 0
else
	echo "Updating ${GANDI_IPV4} to ${CURRENT_IPV4}" >&2
	gandi record update -r "${GANDI_DNS}" --new-record "${HOST} ${TTL} A ${CURRENT_IPV4}" ${DOMAIN}
fi

