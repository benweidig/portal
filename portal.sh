#!/usr/bin/env bash


################################################################################
# PORTAL.SH
################################################################################
# Helper for creating an SSH port forwarding to a Docker container.
#
# Usage: ./portal.sh <command> <host> [<command args>]
#
# Commands:
#   ls      List all available container and exposed ports
#           Usage: ./portal.sh ls <host>
#
#   bind    Start a SSH port forward for a container
#           Usage: ./portal.sh ls <host> <container[:port]> [<local port>]
#
#   connect Start a SSH port forward for a container and open remote shell
#           Usage: ./portal.sh ls <host> <container[:port]> [<local port>]
#
# Requirements:
#   jq, ssh, sed, nc, column, bash 4+
################################################################################

VERSION="0.0.1"

# CHECK FOR REQUIRED INSTALLED APPS
REQUIREMENTS=(jq ssh sed nc column)
for APP in "${REQUIREMENTS[@]}"; do
    command -v "$APP" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        >&2 echo "Required '$APP' is not installed"
        exit 1
    fi
done


# PRINT HELP IF NO ARGS
if [[ $# -lt 2 ]]; then
    echo "Portal - SSH port forwarding helper (${VERSION})"
    echo ""
    echo "Usage:  ${0##*/} <command> <host> [<command args>]"
    echo ""
    echo "Commands:"
    echo "  ls      List all available container and exposed ports"
    echo "          Usage: ${0##*/} ls <host>"
    echo ""
    echo "  bind    Start a SSH port forward for a container"
    echo "          Usage: ${0##*/} bind <host> <container[:port]> [<local port>]"
    echo ""
    echo "  connect Start a SSH port forward for a container and open remote shell"
    echo "          Usage: ${0##*/} bind <host> <container[:port]> [<local port>]"
    exit 1
fi



# VALIDATE HOST ARG
HOST=$2
# REGEX FOR VALIDATING A HOSTNAME ACCORDING TO RFC 1123
HOSTNAME_REGEX="^(([a-zA-Z]|[a-zA-Z][a-zA-Z0-9\-]*[a-zA-Z0-9])\\.)*([A-Za-z]|[A-Za-z][A-Za-z0-9\\-]*[A-Za-z0-9])$"
if [[ ! $HOST =~ $HOSTNAME_REGEX ]]; then
    # IF THE HOST IS NOT A HOSTNAME WE TRY TO VALIDATE IT AS IP
    IP_REGEX="^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$"
    if [[ ! $HOST =~ $IP_REGEX ]]; then
        >&2 echo "'$HOST' is not a valid IP address"
        exit 1
    fi
    >&2 echo "'$HOST' is not a valid hostname"
    exit 1
fi


# SHARED DOCKER PORT STYLE SED EXPRESSION
# REMOVES UDP-PORTS AND CONTAINER HOSTS FROM PORT DEFINITIONS
PORT_SANITIZER="s/[0-9]*\/udp\(, \)\{0,1\}//g; s/.*->//g; s/\/tcp//g;"

CMD=$1
case $CMD in

    # COMMAND ls <host>
    ls )
        if [[ ! $# -eq 2 ]]; then
            >&2 echo "Invalid number of arguments (expected: 2 - current: $#)"
            exit 1
        fi

        # RETRIEVE RUNNING CONTAINER LIST
        SSH_OUTPUT=$(ssh "$HOST" "docker container ls --format '{{json .}}'")

        # EXTRACT NECESSARY INFOS AND PRINT AS TABLE
        OUTPUT=$(printf "CONTAINER\t| PORTS\n")
        while IFS= read -r line; do
            NAME=$(jq -r '.Names' <<< "$line")
            PORTS=$(jq -r '.Ports' <<< "$line")
            PORTS=$(sed -e "$PORT_SANITIZER" <<< "$PORTS")
            # shellcheck disable=SC2001
            PORTS=$(sed -e "s/\([0-9]*\)\(,*\)/${COLOR_WHITE}\1${COLOR_RESET}\2/" <<< $PORTS)
            OUTPUT=$(printf "%s\n%s\t| %s" "${OUTPUT}" "${NAME}" "${PORTS}")
        done < <(echo "$SSH_OUTPUT")
        column -ts $'\t' <<< "$OUTPUT"
        exit 0
        ;;

    # COMMAND bind <host> <container[:port]> [local port]
    bind|connect )
        if [[ $# -lt 3 || $# -gt 4 ]]; then
            >&2 echo "Invalid number of arguments (expected: 3-4 - current: $#)"
            exit 1
        fi


        # VALIDATE AND EXTRACT CONTAINER NAME AND PORT
        CONTAINER_REGEX="^([a-zA-Z0-9][a-zA-Z0-9_.-]*)(:([1-9]|[1-5]?[0-9]{2,4}|6[1-4][0-9]{3}|65[1-4][0-9]{2}|655[1-2][0-9]|6553[1-5]))?$"
        if [[ ! $3 =~ $CONTAINER_REGEX ]]; then
            >&2 echo "'$3' is not a valid container name (optionally with port)"
            exit 1
        fi
        CONTAINER_NAME=${BASH_REMATCH[1]}
        CONTAINER_PORT=${BASH_REMATCH[2]:1}
        
        # RETRIEVE NETWORK SETTINGS OF CONTAINER FOR AT LEAST THE IP
        # shellcheck disable=SC2029
        SSH_OUTPUT=$(ssh "$HOST" "docker inspect --format '{{json .NetworkSettings}}' $CONTAINER_NAME")
        
        # THE IP IS EITHER DIRECTLY IN .NetworkSettings
        # OR WE CHECK THE FIRST NETWORK
        CONTAINER_IP=$(jq -r '.IPAddress' <<< "$SSH_OUTPUT")
        if [[ -z "$CONTAINER_IP" ]]; then
            CONTAINER_IP=$(jq -r '.Networks | to_entries[0] | .value.IPAddress' <<< "$SSH_OUTPUT")
        fi

        # EXTRACT FIRST TCP PORT IF NO PORT WAS PROVIDED
        if [[ -z "$CONTAINER_PORT" ]]; then
            FIRST_TCP=$(jq -r '.Ports | with_entries(select(.key | test(".*/tcp"))) | keys[0]' <<< "$SSH_OUTPUT")
            CONTAINER_PORT=$(sed -e "$PORT_SANITIZER" <<< "$FIRST_TCP")
            if [[ -z "$CONTAINER_PORT" || "$CONTAINER_PORT" == "null" ]]; then
                >&2 echo "No container port was exposed or given as argument"
                exit 1
            fi
        fi

        # FIND CORRECT LOCAL PORT (EITHER CONTAINER PORT OR PROVIDED) AND CHECK IF AVAILABLE
        LOCAL_PORT=$4
        if [[ -z "$LOCAL_PORT" ]]; then
            nc -z 127.0.0.1 "$CONTAINER_PORT" > /dev/null 2>&1
            # shellcheck disable=SC2181
            if [[ $? -eq 0 ]]; then
                >&2 echo "Local port $CONTAINER_PORT is already in use"
                exit 1
            fi
        else
            nc -z 127.0.0.1 "$LOCAL_PORT" > /dev/null 2>&1
            # shellcheck disable=SC2181
            if [[ $? -eq 0 ]]; then
                >&2 echo "Local port $LOCAL_PORT is already in use"
                exit 1
            fi
        fi

        # PRINT SETTINGS AND START FORWARDING
        echo "PORTAL ESTABLISHED"
        echo "Host       : $HOST"
        echo "Container  : $CONTAINER_NAME:$CONTAINER_PORT"
        echo "Local port : $LOCAL_PORT"
        echo ""

        case $CMD in
            bind )
                echo "Press ^C to stop forwarding"
                ssh -N -L "$LOCAL_PORT:$CONTAINER_IP:$CONTAINER_PORT" "$HOST"
                ;;
            connect )
                echo "Press ^D to stop forwarding and exit connection"
                ssh -L "$LOCAL_PORT:$CONTAINER_IP:$CONTAINER_PORT" "$HOST"
                ;;
        esac
        ;;

    * )
        >&2 echo "Invalid command '$CMD'"
        exit 1
        ;;

esac
