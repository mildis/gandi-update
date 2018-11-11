#!/bin/bash

# requires : curl, jq, gandi.cli, tr, sort, wc, getopts

DOMAIN=example.com
HOST=my-server
TTL=86400
RETRY=5
INDEX=0
GANDI_API_KEY=

PUBLIC_IPV4_PROVIDERS=(http://ifconfig.me/ip https://ipv4.lafibre.info/ip.php)
PUBLIC_IPV4=

GANDIV5_API=https://dns.api.gandi.net/api/v5


while getopts ":d:h:k:t:" OPT; do
	case ${OPT} in
		d)
			DOMAIN=${OPTARG}
			;;
		h)
			HOST=${OPTARG}
			;;
		k)
			GANDI_API_KEY=${OPTARG}
			;;
		t)
			TTL=${OPTARG}
			;;
		\?)
			echo "usage : $0 [-k <gandi API key>] [-d <domain>] [-h <host>] [-t <TTL>]" >&2
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
	logger "Not all IP found are the same :\n${CURRENT_IPV4}" >&2
	exit 1
fi

if [ x"${GANDI_API_KEY}" != "x" ]; then
	GANDI_IPV4=$(curl -s -H "X-API-Key:${GANDI_API_KEY}" ${GANDIV5_API}/domains/${DOMAIN}/records/${HOST}/A|jq -r '.rrset_values[]')
else
	GANDI_DNS=$(gandi record list -f json ${DOMAIN}|jq -r '.[]|select(.name == '\"${HOST}\"')|[.name, .ttl, .type, .value]|@tsv'|tr '\t' ' ')
	GANDI_IPV4=$(echo ${GANDI_DNS}|cut -d' ' -f4)
fi


if [ -z "${CURRENT_IPV4}" ]; then
	logger "ERROR : cannot find current IPv4" >&2
	exit 2
fi

if [ -z "${GANDI_IPV4}" ]; then
	logger "ERROR : cannot get Gandi informations" >&2
	exit 3
fi

if [ x"${GANDI_API_KEY}" = "x" -a -z "${GANDI_DNS}" ]; then
	logger "ERROR : cannot get Gandi informations" >&2
	exit 3
fi

if [ x"${CURRENT_IPV4}" = x"${GANDI_IPV4}" ]; then
	logger "{\"message\": \"No update required\", \"current_ipv4\": \"${CURRENT_IPV4}\"}" >&2
	exit 0
else
	logger "{\"message\": \"Updating address\", \"previous_ipv4\": \"${GANDI_IPV4}\",  \"current_ipv4\": \"${CURRENT_IPV4}\"" >&2
	if [ x"${GANDI_API_KEY}" != "x" ]; then
		curl -s -X PUT -H "Content-Type: application/json" -H "X-API-Key:${GANDI_API_KEY}" -d "{\"rrset_type\":\"A\",\"rrset_ttl\":\"${TTL}\",\"rrset_name\":\"${HOST}\",\"rrset_values\":[\"${CURRENT_IPV4}\"]}" ${GANDIV5_API}/domains/${DOMAIN}/records/${HOST}/A 2>&1 | logger
	else
		gandi record update -r "${GANDI_DNS}" --new-record "${HOST} ${TTL} A ${CURRENT_IPV4}" ${DOMAIN} 2>&1 | logger
	fi
fi

