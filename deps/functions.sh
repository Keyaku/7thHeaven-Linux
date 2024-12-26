#!/bin/bash

function is_int {
	[[ $1 =~ ^[0-9]+$ ]]
}

function print_error {
	>&2 printf "[${funcstack[2]:-$FUNCNAME[2]}] %s\n" "$*"
}

# Get steam installation type
function steam-installation {
	local steam_type

	## Check if SteamOS
	steam_type="$(grep -qi "SteamOS" /etc/os-release | tr '[:upper:]' '[:lower:]')"

	## Check if system
	[[ -z "$steam_type" ]] && {
		if [[ "$(command -v steam)" =~ /usr/(.+|/)*?/?bin/(.+|/)*?/?steam ]]; then
			steam_type=system
		fi
	}

	## Check if Flatpak
	if command -v flatpak &>/dev/null && {
		flatpak list --app --columns=application | grep -Fwq 'com.valvesoftware.Steam'
	}; then
		## If steam_type was already set, ask which version to use
		[[ "$steam_type" ]] && {
			local value=$(prompt-radio "Multiple installation types found. Pick one:" "System" "Flatpak")
			case $value in
			1) steam_type="system" ;;
			2) steam_type="flatpak" ;;
			esac
		} || steam_type=flatpak
	fi

	[[ "$steam_type" ]] && echo "$steam_type"
	return $?
}

# Locate app_id from name
function steam-app-id {
	local retval=0

	local library="${STEAM_LIBRARY:-"${XDG_DATA_HOME}"/Steam}"
	[[ -z "$STEAM_LIBRARY" ]] && {
		print_error "STEAM_LIBRARY environment variable not set. Assuming default: ${XDG_DATA_HOME}/Steam"
	}

	[[ $# -eq 0 ]] && {
		print_error "Missing App name(s)"
		return 1
	}

	local arg
	for arg in $@; do
		\grep -iElw "$arg" ${library}/steamapps/appmanifest_*.acf | sed -E 's|.+?appmanifest_||;s|\.acf||' | \grep .
		((retval += $?))
	done

	return $retval
}

# Locate SteamLibrary containing app_id
function steam-app-library {
	local retval=0

	local library="${STEAM_LIBRARY:-"${XDG_DATA_HOME}"/Steam}"
	[[ -z "$STEAM_LIBRARY" ]] && {
		print_error "STEAM_LIBRARY environment variable not set. Assuming default: ${XDG_DATA_HOME}/Steam"
	}

	if (( 0 == $# )); then
		print_error "Missing App ID(s)"
		return 1
	fi

	local arg app_id
	for arg in $@; do
		if is_int "$arg"; then
			app_id="$arg"
		else
			app_id=$(steam-app-id "$arg") || return 2
		fi

		local app_path=$(
		awk -v app_id="$app_id" '
			/^[[:space:]]*"[0-9]+"$/ {
				in_block = 1;
				block = $0;
				next;
			}
			in_block {
				block = block "\n" $0;
				if ($0 ~ /^\s*}/) {
					in_block = 0;
					if (block ~ "\""app_id"\"") {
						match(block, /"path"\s+"([^"]+)"/, arr);
						print arr[1];
						exit;
					}
				}
			}
			' "${library}/steamapps/libraryfolders.vdf"
		)

		readlink -f "$app_path"
		((retval += $?))
	done

	return $retval
}

# Locate app compatdata
function steam-app-data {
	local retval=0

	if (( 0 == $# )); then
		print_error "Missing App ID(s)"
		return 1
	fi

	# Parse arguments
	local arg app_id
	for arg in $@; do
		if is_int "$arg"; then
			app_id="$arg"
		else
			app_id=$(steam-app-id "$arg") || {
				((retval += $?))
				continue
			}
		fi

		readlink -f "$(steam-app-library "$arg")/steamapps/compatdata/${app_id}"
		((retval += $?))
	done

	return $retval
}

# Fetches Steam app's Proton path
function steam-app-proton {
	local retval=0

	if (( 0 == $# )); then
		print_error "Missing App ID(s)"
		return 1
	fi

	local arg app_data proton_version
	for arg in $@; do
		app_data="$(steam-app-data "$arg")" || {
			((retval += $?))
			continue
		}

		## Check for Proton version from prefix files
		# Check from config file
		if [[ -f "${app_data}/config_info" ]]; then
			proton_version="$(sed -En '2s,/(files|dist)/.*,,p' "${app_data}/config_info")"
		fi

		# Print Proton version, or error if not found
		if [[ -z "$proton_version" ]]; then
			print_error "Couldn't determine Proton version for '${arg}'"
			((retval++))
			continue
		fi

		echo "$proton_version"
	done

	return $retval
}

function select-proton {
	local STEAM_COMPAT_TOOLS="$STEAM_LIBRARY/compatibilitytools.d"
	local PROTON_LIST=($(find "$STEAM_COMPAT_TOOLS" -maxdepth 1 -type d -name 'GE-Proton*'))
	local PROTON_VERSION PROTON_PATH

	if (( 0 < ${#PROTON_LIST[@]} )); then
		# Found GE-Proton. Check if only one
		if (( 1 == ${#PROTON_LIST[@]} )); then
			PROTON_VERSION="$(basename ${PROTON_LIST})"
			prompt-yesno "Found $PROTON_VERSION in list of compatibility tools. Do you wish to use this one?"
			case $? in
			0) echo "$STEAM_COMPAT_TOOLS/$PROTON_VERSION/proton" ;;
			1) ;; # do nothing
			*) return 1 ;;
			esac
		else
			prompt-yesno "Found multiple GE-Protons in list of compatibility tools. Do you wish to use these over Valve's Proton?" \
			&& { while [[ -z "$PROTON" ]]; do
				PROTON_PATH=$(prompt-dir "Select GE-Proton version") || return 1
				if ! [[ "$PROTON_PATH" =~ "$STEAM_COMPAT_TOOLS"/.* ]]; then
					prompt-user "Selected path is not in Steam library's compatibility tools."
				elif [[ ! -f "$PROTON_PATH/proton" ]]; then
					prompt-user "Selected path does not contain Proton binaries."
				else
					echo "$PROTON_PATH/proton"
				fi
			done }
		fi
	fi

	return 0
}

readonly PROMPT_TYPES=(kdialog zenity dialog)

# Dialog compatibility
function get-prompt {
	local ptype

	for ptype in ${PROMPT_TYPES[@]}; do
		command -v $ptype &>/dev/null && {
			echo "$ptype"
			return 0
		}
	done

	return 1
}

function prompt-user {
	local message="$1"

	case $(get-prompt) in
	kdialog ) kdialog --msgbox "$message" &>/dev/null
	;;
	dialog ) dialog --msgbox "$message" 10 60
	;;
	zenity ) zenity --info --text="$message" &>/dev/null
	;;
	esac
}

function prompt-radio {
	local title="$1"
	shift
	local arglist_off=() arglist=()

	local idx=1 opt
	for opt in $@; do
		arglist+=($idx "$opt")
		((idx++))
	done

	case $(get-prompt) in
	kdialog ) kdialog --radiolist "$title" $(printf '%d %s off ' ${arglist[@]})
	;;
	dialog ) dialog --radiolist "$title" 0 0 0 $(printf '%d %s off ' ${arglist[@]})
	;;
	zenity )
		zenity --title="title" --list --radiolist --column="" --column="Option" \
			${arglist[@]}
	;;
	esac
}

function prompt-yesno {
	local message="$1"

	case $(get-prompt) in
	kdialog ) kdialog --yesno "$message" &>/dev/null
	;;
	dialog ) dialog --yesno "$message" 10 60
	;;
	zenity ) zenity --question --text="$message" &>/dev/null
	;;
	esac
}

function prompt-dir {
	local title="$1"
	local startdir="${2:-$HOME}"

	case $(get-prompt) in
	kdialog ) cd ${startdir}
		echo $(kdialog --getexistingdirectory)
		cd - &>/dev/null
	;;
	dialog ) echo $(dialog --dselect "${startdir}" 10 60 --stdout)
	;;
	zenity ) echo $(zenity --file-selection --directory)
	;;
	esac
}
