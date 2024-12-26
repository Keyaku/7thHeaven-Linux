function print_rectangle {
	(( $# <= 3 )) && {
		print_error "Missing arguments: WIDTH PADDING DELIMITER [array of lines]"
		return 1
	}

	local width=$1
	local pad=$2
	local inner_width=$(($width - (2 + $pad*2))) # interior padded with spaces
	local delim=$3
	shift 3
	local text=("$@")

	local line="" word=""
	local i=0

	_print_separator() {
		printf -- "%0.s${delim}" $(seq 1 ${width})
		printf '\n'
	}
	_print_line() {
		printf "%-${pad}s %-${inner_width}s %+${pad}s\n" "${delim}" "$1" "${delim}"
	}
	_print_centered_line() {
		local _text=$1
		local _text_length=${#_text}
		local _padding=$(( (inner_width - _text_length) / 2 ))

		# Generate left and right padding
		local _lpad=$(printf '%*s' "$_padding" "")
		local _rpad=$(printf '%*s' $(( $_padding + (${_text_length} - $inner_width) )) "")

		# Print the centered line
		printf "%-${pad}s %s%s%s %+${pad}s\n" "${delim}" "$_lpad" "$_text" "$_rpad" "${delim}"
	}

	# Print title
	printf '\n'
	_print_separator
	local title="${NAME} ${VERSION}"
	_print_centered_line "$title"

	# Print top border
	_print_separator

	local text_line word
	for text_line in "${text[@]}"; do
		# If separator line, print only delimiter characters
		if [[ "$text_line" == "---" ]]; then
			_print_separator
			continue
		fi

		for word in $text_line; do
			if (( 0 == ${#line} )); then
				line=$word
			elif (( ${#line} + ${#word} + 1 <= $inner_width )); then
				line="$line $word"
			else
				_print_line "$line"
				line=$word
			fi
		done

		if (( 0 < ${#line} )); then
			_print_line "$line"
			line=""
		fi
	done

	# Print remaining line if exists
	if (( 0 < ${#line} )); then
		_print_line "$line"
	fi

	# Print bottom border
	_print_separator
}


# Download from GitHub
function download-deps {
	local XDG_CACHE_HOME="${XDG_CACHE_HOME:=${HOME}/.cache}"
	local REPO=$1
	local FILTER=$2
	local RETURN_VARIABLE=$3
	local RELEASE_URL=$(
		curl -s https://api.github.com/repos/"$REPO"/releases/latest  \
		| grep "browser_download_url.$FILTER" \
		| head -1 \
		| cut -d : -f 2,3 \
		| tr -d \")
	local FILENAME="${XDG_CACHE_HOME}/$(basename "$RELEASE_URL")"
	if [ -f "$FILENAME" ]; then
		echo "$FILENAME is ready to be installed."
	else
		echo "$FILENAME not found. Downloading..."
		curl -#SL -o $FILENAME $RELEASE_URL
	fi
	eval "${RETURN_VARIABLE}=\"$FILENAME\""
}


### Steam-related

function run_steam {
	if [[ "$steam_type" == "flatpak" ]]; then
		com.valvesoftware.Steam $@
	else
		nohup steam
	fi
}

function pidof_steam {
	if [[ "$steam_type" == "flatpak" ]]; then
		local pids=($(flatpak ps --columns=pid,application | sed -E '/com\.valvesoftware\.Steam/!d;s/^([0-9]+).*/\1/g'))
		(( 0 != ${#pids[@]} ))
	else
		pidof steam
	fi
}

function pgrep_steam {
	if [[ "$steam_type" == "flatpak" ]]; then
		flatpak ps --columns=pid,application | grep -qF com.valvesoftware.Steam
	else
		pgrep steam
	fi
}

function kill_steam {
	if [[ "$steam_type" == "flatpak" ]]; then
		flatpak kill com.valvesoftware.Steam
	else
		killall -9 steam
	fi
}
