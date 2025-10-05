#!/bin/bash

get_log_path(){
	while true; do
		read -p "Enter the path to the folder /log: " path

		path=$(echo "$path" | xargs) 

		if [ -z "$path" ]; then
			echo "The path to the folder cannot be empty"
			continue
		fi

		path="${path/#\~/$HOME}"
		normalized_path=$(realpath -s "$path" 2>/dev/null)

		if [ ! -d "$normalized_path" ]; then
			echo "Folder '$path' does not exist or it is not a folder"
			continue
		fi

		if [ ! -r "$normalized_path" ] || [ ! -w "$normalized_path" ]; then
			echo "No access rights to the folder"
			continue
		fi

		echo "Folder found: $normalized_path"
		echo "$normalized_path"
		break
	done
}

get_log_path
