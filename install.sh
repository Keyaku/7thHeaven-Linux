#!/bin/bash

readonly SCRIPT="$(readlink -f "$0")"
readonly SCRIPT_DIR="$(dirname "${SCRIPT}")"
readonly NAME="$(basename "${SCRIPT_DIR}")"
readonly VERSION=1.0
readonly LOGFILE="${SCRIPT_DIR}/${NAME}.log"

readonly XDG_DESKTOP_DIR=$(xdg-user-dir DESKTOP)

# Load functions
. "${SCRIPT_DIR}"/deps/functions.sh
. "${SCRIPT_DIR}"/deps/helpers.sh

# Check for main dependencies
has_dependencies=false
for dep in ${PROMPT_TYPES[@]}; do
	if command -v $dep &>/dev/null; then
		has_dependencies=true
		break
	fi
done
if [[ "$has_dependencies" != true ]]; then
	echo "One of the following dialog prompters needs to be installed:"
	echo "${PROMPT_TYPES[@]}"
	exit 1
fi

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
*)
	echo "Unknown Steam installation state."
	exit 1
;;
esac

readonly STEAM_COMPAT_TOOLS="$STEAM_LIBRARY/compatibilitytools.d"

# Start script
echo "" > "${LOGFILE}"
exec > >(tee -ia "${LOGFILE}") 2>&1

readonly HEADER_MSG=(
	"Based on 7thDeck by dotaxis."
	"This script will:"
	"1. Apply patches to FF7's proton prefix to accomodate 7th Heaven"
	"2. Install 7th Heaven to a directory of your choosing"
	"3. Add 7th Heaven to Steam using a custom launcher script"
	"4. Add a custom controller config for Steam Deck, to allow mouse control with trackpad without holding down the STEAM button"
	"---"
	"For support, please open an issue on GitHub, or ask in the #Steamdeck-Proton channel of the Tsunamods Discord"
)

print_rectangle 72 2 '#' "${HEADER_MSG[@]}"
printf '\n'


# Check for FF7 and set paths
readonly FF7_APP_ID=39140
while [[ -z "$FF7_LIBRARY" ]]; do
	# if ! pgrep_steam >/dev/null; then run_steam &>/dev/null; fi
	# while ! pgrep_steam >/dev/null; do sleep 1; done
	echo -n "Checking if FF7 is installed... "
	FF7_LIBRARY=$(steam-app-library ${FF7_APP_ID})
	if [[ -z "$FF7_LIBRARY" ]]; then
		echo -e "\nNot found! Launching Steam to install."
		run_steam steam://install/${FF7_APP_ID} &>/dev/null &
		read -p "Press Enter when FINAL FANTASY VII is done installing."
		kill_steam
		while pgrep_steam; do sleep 1; done
		rm "$STEAM_LIBRARY"/steamapps/libraryfolders.vdf &>> "${LOGFILE}"
		rm "$STEAM_LIBRARY"/config/libraryfolders.vdf &>> "${LOGFILE}"
	else
		echo "OK!"
		echo "Found FF7 at $FF7_LIBRARY!"
		echo
	fi
done

# Set paths and compat_mounts after libraries have been properly detected
FF7_DIR="$FF7_LIBRARY/steamapps/common/FINAL FANTASY VII"
WINEPATH="$FF7_LIBRARY/steamapps/compatdata/${FF7_APP_ID}/pfx"

# Check for SteamLinuxRuntime
readonly STEAM_RUNTIME_APP_ID=1628350
while true; do
	# if ! pgrep_steam >/dev/null; then run_steam &>/dev/null; fi
	# while ! pgrep_steam >/dev/null; do sleep 1; done
	RUNTIME=$(LIBRARY=$(steam-app-library ${STEAM_RUNTIME_APP_ID}) && [[ -n "$LIBRARY" ]] && echo "$LIBRARY/steamapps/common/SteamLinuxRuntime_sniper/run")
	echo -n "Checking if Steam Linux Runtime is installed... "
	if [[ -z "$RUNTIME" ]]; then
		echo -e "\nNot found! Launching Steam to install."
		run_steam steam://install/${STEAM_RUNTIME_APP_ID} &>/dev/null &
		read -p "Press Enter when Steam Linux Runtime 3.0 (sniper) is done installing."
		kill_steam
		while pgrep steam >/dev/null; do sleep 1; done
		rm "$STEAM_LIBRARY"/steamapps/libraryfolders.vdf &>> "${LOGFILE}"
		rm "$STEAM_LIBRARY"/config/libraryfolders.vdf &>> "${LOGFILE}"
	else
		echo "OK!"
		echo "Found SLR at $RUNTIME!"
		echo
		break
	fi
done

# Check for Proton
# FIXME: Add ability to select Proton version
readonly PROTON_9_APP_ID=2805730
while true; do
	# if ! pgrep_steam >/dev/null; then run_steam &>/dev/null; fi
	# while ! pgrep_steam >/dev/null; do sleep 1; done
	PROTON=$(select-proton)
	echo -n "Checking if Proton 9 is installed... "
	if [[ -z "$PROTON" ]]; then
		echo -e "\nNot found! Launching Steam to install."
		run_steam steam://install/${PROTON_9_APP_ID} &>/dev/null &
		read -p "Press Enter when Proton 9 is done installing."
		kill_steam
		while pgrep_steam >/dev/null; do sleep 1; done
		rm "$STEAM_LIBRARY"/steamapps/libraryfolders.vdf &>> "${LOGFILE}"
		rm "$STEAM_LIBRARY"/config/libraryfolders.vdf &>> "${LOGFILE}"
	else
		echo "OK!"
		echo "Found Proton at $PROTON!"
		echo
		break
	fi
done

export STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_TOOLS}:$(steam-app-library ${PROTON_9_APP_ID}):$(steam-app-library ${STEAM_RUNTIME_APP_ID}):$(steam-app-library ${FF7_APP_ID})"


# Force FF7 under Proton 9
echo "Rebuilding Final Fantasy VII under Proton..."
while pidof_steam > /dev/null; do
	kill_steam &>> "${LOGFILE}"
	sleep 1
done
cp "$STEAM_LIBRARY"/config/config.vdf "$STEAM_LIBRARY"/config/config.vdf.bak
perl -0777 -i -pe 's/"CompatToolMapping"\n\s+{/"CompatToolMapping"\n\t\t\t\t{\n\t\t\t\t\t"'${FF7_APP_ID}'"\n\t\t\t\t\t{\n\t\t\t\t\t\t"name"\t\t"proton_9"\n\t\t\t\t\t\t"config"\t\t""\n\t\t\t\t\t\t"priority"\t\t"250"\n\t\t\t\t\t}/gs' \
"$STEAM_LIBRARY"/config/config.vdf
[[ "${WINEPATH}" = */compatdata/${FF7_APP_ID}/pfx ]] && rm -rf "${WINEPATH%/pfx}"/*
echo "Sign into the Steam account that owns FF7 if prompted."
run_steam steam://rungameid/${FF7_APP_ID} &>/dev/null &
echo "Waiting for Steam..."
if [[ "$steam_type" != "flatpak" ]]; then
	while ! pgrep "FF7_Launcher" > /dev/null; do sleep 1; done
	killall -9 "FF7_Launcher.exe"
fi
echo

# Fix infinite loop on "Verifying installed game is compatible"
[[ -L "$FF7_DIR/FINAL FANTASY VII" ]] && unlink "$FF7_DIR/FINAL FANTASY VII"

# Ask for install path
echo "Waiting for you to select an installation path..."
prompt-user "Choose an installation path for 7th Heaven. The folder must already exist."
while [[ -z "$INSTALL_PATH" || ! -d "$INSTALL_PATH" ]]; do
	INSTALL_PATH=$(prompt-dir "Select 7th Heaven Install Folder") || { echo "No directory selected. Exiting."; exit 1; }
	prompt-yesno "7th Heaven will be installed to $INSTALL_PATH. Continue?"
	case $? in
		0) echo "Installing to $INSTALL_PATH." ;;
		1) echo "Select a different path." ;;
		*) echo "An unexpected error has occurred. Exiting"; exit 1 ;;
	esac
done

echo

# Download 7th Heaven from Github
echo "Downloading 7th Heaven..."
download-deps "tsunamods-codes/7th-Heaven" "*.exe" SEVENTH_INSTALLER
echo

# # Install 7th Heaven using EXE
echo "Installing 7th Heaven..."
mkdir -p "${WINEPATH}/drive_c/ProgramData" # fix vcredist install - infirit
STEAM_COMPAT_APP_ID=${FF7_APP_ID} STEAM_COMPAT_DATA_PATH="${WINEPATH%/pfx}" \
STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_LIBRARY}" \
"$RUNTIME" -- "$PROTON" waitforexitandrun \
"$SEVENTH_INSTALLER" /VERYSILENT /DIR="Z:$INSTALL_PATH" /LOG="7thHeaven.log" &>> "${LOGFILE}"
echo

# Tweaks to 7th Heaven install directory
echo "Applying patches to 7th Heaven..."
mkdir -p "$INSTALL_PATH/7thWorkshop/profiles"
cp -f "$INSTALL_PATH/Resources/FF7_1.02_Eng_Patch/ff7.exe" "$FF7_DIR/ff7.exe"
cp -f "${SCRIPT_DIR}/deps/7th Heaven.sh" "$INSTALL_PATH/"
cp -f "${SCRIPT_DIR}/deps/functions.sh" "$INSTALL_PATH/"
cp -f "${SCRIPT_DIR}/deps/settings.xml" "$INSTALL_PATH/7thWorkshop/"
[[ ! -f "$INSTALL_PATH/7thWorkshop/profiles/Default.xml" ]] && cp "${SCRIPT_DIR}/deps/Default.xml" "$INSTALL_PATH/7thWorkshop/profiles/" &>> "${LOGFILE}"
sed -i "s|<LibraryLocation>REPLACE_ME</LibraryLocation>|<LibraryLocation>Z:$INSTALL_PATH/mods</LibraryLocation>|" "$INSTALL_PATH/7thWorkshop/settings.xml"
sed -i "s|<FF7Exe>REPLACE_ME</FF7Exe>|<FF7Exe>Z:$FF7_DIR/ff7.exe</FF7Exe>|" "$INSTALL_PATH/7thWorkshop/settings.xml"
echo

# Tweaks to game
echo "Applying patches to FF7..."
cp -f "${SCRIPT_DIR}/deps/timeout.exe" "$WINEPATH/drive_c/windows/system32/"
echo "FF7DISC1" > "$WINEPATH/drive_c/.windows-label"
echo "44000000" > "$WINEPATH/drive_c/.windows-serial"
[[ ! -d "$FF7_DIR/music/vgmstream" ]] && mkdir -p "$FF7_DIR/music/vgmstream"
[[ -d "$FF7_DIR/data/music_ogg" ]] && cp "$FF7_DIR/data/music_ogg/"* "$FF7_DIR/music/vgmstream/"
if [[ -d "$FF7_DIR/data/lang-en" ]]; then
	data_files=(
		battle/camdat{0..2}.bin
		battle/co.bin
		battle/scene.bin
		kernel/KERNEL.BIN
		kernel/kernel2.bin
		kernel/WINDOW.BIN
	)
	for ff7_file in "${data_files[@]}"; do
		ln -fs "$FF7_DIR/data/lang-en/$ff7_file" "$FF7_DIR/data/$ff7_file"
	done
fi
echo

# SteamOS only
if [[ "$steam_type" == "steamos" ]]; then
	# Steam Deck Auto-Config (mod)
	mkdir -p "$INSTALL_PATH/mods"
	cp -rf "${SCRIPT_DIR}"/deps/SteamDeckSettings "$INSTALL_PATH/mods/"

	# This allows moving and clicking the mouse by using the right track-pad without holding down the STEAM button
	echo "Adding controller config..."
	cp -f "${SCRIPT_DIR}"/deps/controller_neptune_gamepad+mouse+click.vdf "$STEAM_LIBRARY"/controller_base/templates/controller_neptune_gamepad+mouse+click.vdf
	for CONTROLLERCONFIG in "$STEAM_LIBRARY"/steamapps/common/Steam\ Controller\ Configs/*/config/configset_controller_neptune.vdf ; do
		if grep -q "\"${FF7_APP_ID}\"" "$CONTROLLERCONFIG"; then
			perl -0777 -i -pe 's/"${FF7_APP_ID}"\n\s+\{\n\s+"template"\s+"controller_neptune_gamepad_fps.vdf"\n\s+\}/"${FF7_APP_ID}"\n\t\{\n\t\t"template"\t\t"controller_neptune_gamepad+mouse+click.vdf"\n\t\}\n\t"7th heaven"\n\t\{\n\t\t"template"\t\t"controller_neptune_gamepad+mouse+click.vdf"\n\t\}/gs' "$CONTROLLERCONFIG"
		else
			perl -0777 -i -pe 's/"controller_config"\n\{/"controller_config"\n\{\n\t"${FF7_APP_ID}"\n\t\{\n\t\t"template"\t"controller_neptune_gamepad+mouse+click.vdf"\n\t\}\n\t"7th heaven"\n\t\{\n\t\t"template"\t"controller_neptune_gamepad+mouse+click.vdf"\n\t\}/' "$CONTROLLERCONFIG"
		fi
	done
	echo
fi

# Add shortcut to Desktop/Launcher
echo "Adding 7th Heaven to Desktop and Launcher..."
xdg-icon-resource install "${SCRIPT_DIR}"/deps/7th-heaven.png --size 64 --novendor
mkdir -p "${XDG_DATA_HOME}/applications" &>> "${LOGFILE}"
readonly APP_DESKTOP="#!/usr/bin/env xdg-open
[Desktop Entry]
Name=7th Heaven
Icon=7th-heaven
Exec=\"$INSTALL_PATH/7th Heaven.sh\"
Path=$INSTALL_PATH
Categories=Game;
Terminal=false
Type=Application
StartupNotify=false"

readonly DESKTOP_PATHS=(
	# Launcher
	"${XDG_DATA_HOME}/applications"
	# Desktop
	"${XDG_DESKTOP_DIR}"
)

for app_shortcut in ${DESKTOP_PATHS[@]}; do
	rm -r "${app_shortcut}/7th Heaven.desktop" 2>/dev/null
	echo "${APP_DESKTOP}" > "${app_shortcut}/applications/7th Heaven.desktop"
	chmod ug+x "${app_shortcut}/7th Heaven.desktop"
done

update-desktop-database ${XDG_DATA_HOME}/applications &>> "${LOGFILE}"
echo

# Add launcher to Steam
echo "Adding 7th Heaven to Steam..."
"${SCRIPT_DIR}"/deps/steamos-add-to-steam "${XDG_DATA_HOME}/applications/7th Heaven.desktop" &>> "${LOGFILE}"
sleep 5
echo

echo -e "All done!\nYou can close this window and launch 7th Heaven from Steam or the desktop now."
