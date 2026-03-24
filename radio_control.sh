#!/bin/bash

# Configuration
RADIO_IP="${RADIO_IP:-XX.XX.XX.XX}"
RADIO_PIN="1234"  # Default UNDOK pin. Change if you set a custom one.

# Help function
usage() {
    cat <<EOF
Roberts Radio Control Script

Usage: $(basename "$0") [flags] [command] [value]

Flags:
  -i, --ip <addr>   IP address of the radio (default: XX.XX.XX.XX)
  -h, --help        Show this help message

Commands:
  on                Turn the radio ON
  off               Turn the radio OFF (Standby)
  status            Check power status
  vol [0-32]        Set volume or get current volume
  volup             Increase volume by 1
  voldown           Decrease volume by 1
  mute              Mute the radio
  unmute            Unmute the radio
  togglemute        Toggle mute state
  mode [id]         Set source mode or get current mode
  next              Next track or station
  prev              Previous track or station
  play              Start playback
  pause             Pause playback
  info              Show "Now Playing" information
  pair              Initiate Bluetooth pairing
  device            Show device information (Model, Version, IP)

Common Mode IDs:
  0: Internet Radio   1: Tidal           2: Deezer
  3: Amazon Music     4: Spotify         5: Local Music
  6: Music Player     7: DAB             8: FM Radio
  9: Bluetooth        10: AUX

Note: Run "mode" without an ID to see the current source's ID.

EOF
    exit 1
}

# Parse flags
while [[ "$1" =~ ^- ]]; do
    case "$1" in
        -i|--ip)
            RADIO_IP="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# FSAPI Call Helper
fsapi_call() {
    local method="$1"
    local path="$2"
    local value="$3"
    local url="http://$RADIO_IP/fsapi/$method/$path?pin=$RADIO_PIN"
    [ -n "$value" ] && url="$url&value=$value"
    curl -s "$url"
}

# Extract value from FSAPI response
get_value() {
    echo "$1" | tr -d '\n\r' | sed -e 's/.*<value>//' -e 's/<\/value>.*//' -e 's/<[^>]*>//g'
}

# Check if an argument was provided
if [ -z "$1" ]; then
    usage
fi

case "$1" in
    on)
        echo "Turning Radio ON..."
        fsapi_call "SET" "netRemote.sys.power" "1" > /dev/null
        ;;
    off)
        echo "Turning Radio OFF (Standby)..."
        fsapi_call "SET" "netRemote.sys.power" "0" > /dev/null
        ;;
    status)
        RESPONSE=$(fsapi_call "GET" "netRemote.sys.power")
        VALUE=$(get_value "$RESPONSE")
        if [[ "$VALUE" == "1" ]]; then
            echo "Radio is currently: ON"
        else
            echo "Radio is currently: OFF"
        fi
        ;;
    vol)
        if [ -n "$2" ]; then
            echo "Setting Volume to $2..."
            fsapi_call "SET" "netRemote.sys.audio.volume" "$2" > /dev/null
        else
            RESPONSE=$(fsapi_call "GET" "netRemote.sys.audio.volume")
            VALUE=$(get_value "$RESPONSE")
            echo "Current Volume: $VALUE"
        fi
        ;;
    volup)
        CUR_VOL=$(get_value "$(fsapi_call "GET" "netRemote.sys.audio.volume")")
        NEW_VOL=$((CUR_VOL + 1))
        [ $NEW_VOL -gt 32 ] && NEW_VOL=32
        echo "Increasing volume to $NEW_VOL..."
        fsapi_call "SET" "netRemote.sys.audio.volume" "$NEW_VOL" > /dev/null
        ;;
    voldown)
        CUR_VOL=$(get_value "$(fsapi_call "GET" "netRemote.sys.audio.volume")")
        NEW_VOL=$((CUR_VOL - 1))
        [ $NEW_VOL -lt 0 ] && NEW_VOL=0
        echo "Decreasing volume to $NEW_VOL..."
        fsapi_call "SET" "netRemote.sys.audio.volume" "$NEW_VOL" > /dev/null
        ;;
    mute)
        echo "Muting..."
        fsapi_call "SET" "netRemote.sys.audio.mute" "1" > /dev/null
        ;;
    unmute)
        echo "Unmuting..."
        fsapi_call "SET" "netRemote.sys.audio.mute" "0" > /dev/null
        ;;
    togglemute)
        CUR_MUTE=$(get_value "$(fsapi_call "GET" "netRemote.sys.audio.mute")")
        if [[ "$CUR_MUTE" == "1" ]]; then
            echo "Unmuting..."
            fsapi_call "SET" "netRemote.sys.audio.mute" "0" > /dev/null
        else
            echo "Muting..."
            fsapi_call "SET" "netRemote.sys.audio.mute" "1" > /dev/null
        fi
        ;;
    mode)
        if [ -n "$2" ]; then
            echo "Changing Mode to $2..."
            fsapi_call "SET" "netRemote.sys.mode" "$2" > /dev/null
        else
            RESPONSE=$(fsapi_call "GET" "netRemote.sys.mode")
            VALUE=$(get_value "$RESPONSE")
            echo "Current Mode: $VALUE"
        fi
        ;;
    next)
        echo "Next track/station..."
        fsapi_call "SET" "netRemote.nav.action.navigate" "1" > /dev/null
        ;;
    prev)
        echo "Previous track/station..."
        fsapi_call "SET" "netRemote.nav.action.navigate" "-1" > /dev/null
        ;;
    play)
        echo "Playing..."
        fsapi_call "SET" "netRemote.nav.state" "1" > /dev/null
        ;;
    pause)
        echo "Pausing..."
        fsapi_call "SET" "netRemote.nav.state" "2" > /dev/null
        ;;
    info)
        NAME=$(get_value "$(fsapi_call "GET" "netRemote.play.info.name")")
        TEXT=$(get_value "$(fsapi_call "GET" "netRemote.play.info.text")")
        echo "Now Playing: $NAME"
        echo "Info: $TEXT"
        ;;
    pair)
        echo "Switching to Bluetooth mode (ID 9)..."
        fsapi_call "SET" "netRemote.sys.mode" "9" > /dev/null
        sleep 1
        echo "Initiating Bluetooth pairing..."
        fsapi_call "SET" "netRemote.bluetooth.pairing" "1" > /dev/null
        ;;
    device)
        FRIENDLY=$(get_value "$(fsapi_call "GET" "netRemote.sys.info.friendlyName")")
        MODEL=$(get_value "$(fsapi_call "GET" "netRemote.sys.info.modelName")")
        VERSION=$(get_value "$(fsapi_call "GET" "netRemote.sys.info.version")")
        IP_RAW=$(get_value "$(fsapi_call "GET" "netRemote.sys.net.ipConfig.address")")
        
        # Convert integer IP to dotted decimal (Big Endian)
        if [[ "$IP_RAW" =~ ^[0-9]+$ ]]; then
            IP="$(( (IP_RAW >> 24) & 255 )).$(( (IP_RAW >> 16) & 255 )).$(( (IP_RAW >> 8) & 255 )).$(( IP_RAW & 255 ))"
        else
            IP="$IP_RAW"
        fi
        
        echo "Device Name: $FRIENDLY"
        echo "Model:       $MODEL"
        echo "Version:     $VERSION"
        echo "Radio IP:    $IP"
        ;;
    *)
        usage
        ;;
esac
