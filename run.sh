#!/usr/bin/env bash
[[ -z "$server_path" ]] && server_path=$(which clockify-watch-server)
[[ -z "$client_path" ]] && client_path=$(which clockify-watch-client)

if [[ ! -x "$server_path" ]]; then
	echo "clockify-watch-server not found"
	exit 1
fi

if [[ ! -x "$client_path" ]]; then
	echo "clockify-watch-client not found"
	exit 1
fi

running_procs = $(ps -A | grep "[c]lockify-watch-server" | awk '{print $1}')
proc_count = $(wc -l <<<"$running_procs")

if [ $proc_count -eq 0 ]; then
	echo "Starting clockify-watch-server"
	nohup clockify-watch-server &
fi

$client_path "$@"
