#!/bin/bash

# requires : curl, jq, gandi.cli

DOMAIN=example.com
HOST=my-server
TTL=86400
RETRY=5

while [ x"${CURRENT_IPV4}" = "x" -a ${RETRY} -gt 0 ]; do
	((RETRY--))
	CURRENT_IPV4=$(curl -qs -m 30 http://ifconfig.me/ip)
done

GANDI_DNS=$(gandi record list -f json ${DOMAIN}|jq -r '.[]|select(.name == '\"${HOST}\"')|[.name, .ttl, .type, .value]|@tsv'|tr '\t' ' ')
GANDI_IPV4=$(echo ${GANDI_DNS}|cut -d' ' -f4)

if [ -z "${CURRENT_IPV4}" ]; then
	echo "ERROR : cannot find current IPv4" >&2
	exit 1
fi

if [ -z "${GANDI_DNS}" -o -z "${GANDI_IPV4}" ]; then
	echo "ERROR : cannot get Gandi informations" >&2
	exit 2
fi

if [ x"${CURRENT_IPV4}" = x"${GANDI_IPV4}" ]; then
	echo "No update required" >&2
	exit 0
else
	echo "Updating ${GANDI_IPV4} to ${CURRENT_IPV4}" >&2
	gandi record update -r "${GANDI_DNS}" --new-record "${HOST} ${TTL} A ${CURRENT_IPV4}" ${DOMAIN}
fi

