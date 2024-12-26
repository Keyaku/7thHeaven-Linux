#!/bin/bash

readonly SCRIPT="$(readlink -f "$0")"
readonly SCRIPT_DIR="$(dirname "$SCRIPT")"


# Check for Steam installation
steam_type=$(steam-installation)

# Setting Steam executable and Library path
case $steam_type in
flatpak )
	echo "Running script for Flatpak version"
	STEAM_LIBRARY="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
;;
steamos | system )
	echo "Running script for regular install"
	STEAM_LIBRARY="$XDG_DATA_HOME/Steam"
;;
esac

# Load functions
. "$SCRIPT_DIR"/functions.sh

IS_GAMESCOPE=$(pgrep gamescope > /dev/null && echo true || echo false)
if [[ $IS_GAMESCOPE == true ]]; then
	echo "d3d9.shaderModel = 1" > dxvk.conf
else
	[[ -f "dxvk.conf" ]] && rm dxvk.conf
fi

export STEAM_COMPAT_APP_ID=39140
export STEAM_COMPAT_TOOLS="$STEAM_LIBRARY/compatibilitytools.d"
FF7_LIBRARY=$(steam-app-library ${STEAM_COMPAT_APP_ID})
export STEAM_COMPAT_DATA_PATH="$([[ -n "${FF7_LIBRARY}" ]] && echo "${FF7_LIBRARY}/steamapps/compatdata/${STEAM_COMPAT_APP_ID}")"

export STEAM_COMPAT_CLIENT_INSTALL_PATH=$(readlink -f "$STEAM_LIBRARY")
export STEAM_COMPAT_MOUNTS="$(steam-app-library 2805730):$(steam-app-library 1628350):${FF7_LIBRARY}}"
export WINEDLLOVERRIDES="dinput=n,b"
export DXVK_HDR=0
export PATH=$(echo "${PATH}" | sed -e "s|:$HOME/dotnet||")
unset DOTNET_ROOT

# Select runtime
RUNTIME="$(LIBRARY=$(steam-app-library 1628350) && [[ -n "$LIBRARY" ]] && echo "$LIBRARY/steamapps/common/SteamLinuxRuntime_sniper/run")"

# Select Proton
PROTON="$("$(steam-app-proton ${STEAM_COMPAT_APP_ID})/proton")"

# Default case
if [[ -z "$PROTON" ]]; then
	PROTON="$(LIBRARY=$(steam-app-library 2805730) && [[ -n "$LIBRARY" ]] && echo "$LIBRARY/steamapps/common/Proton 9.0 (Beta)/proton")"
fi

[ ! -d "$STEAM_COMPAT_DATA_PATH" ] && { prompt-user "FF7 prefix not found!"; exit 1; }
[[ -z "$RUNTIME" ]] && { prompt-user "Steam Linux Runtime not found!"; exit 1; }
[[ -z "$PROTON" ]] && { prompt-user "Proton not found!"; exit 1; }

echo "Running full command:"
echo "$RUNTIME" -- "$PROTON" waitforexitandrun "$SCRIPT_DIR/7th Heaven.exe" $*
"$RUNTIME" -- "$PROTON" waitforexitandrun "$SCRIPT_DIR/7th Heaven.exe" $*
