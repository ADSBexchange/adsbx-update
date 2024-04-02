#!/bin/bash

lastmove_epoch='211676880' #Set value far in the past
minmoving='5' # cutoff for "moving" in meters/sec, must be integer
minstill='600' # minimum time GPS must be "still" before reactivating MLAT.  If under this time, MLAT will be deactivated.
source /boot/adsb-config.txt


function refresh_pos {

        # Get GPS string, ignore if x/y accuracy is > 50 meters.
        GPS_STRING=$(gpspipe --json -n 10 | grep -m 1 "\"epx\"" | jq -c 'select(.epx < 50 and .epy < 50)')
        echo $GPS_STRING > /tmp/gpspos
        SPEED=$(echo $GPS_STRING | jq -r '.speed')
        SPEED=$(echo "$SPEED" | awk '{print int($1)}') # truncate to integer value
        GPS_LAT=$(echo $GPS_STRING | jq -r '.lat')
        GPS_LON=$(echo $GPS_STRING | jq -r '.lon')
        GPS_ALT=$(echo $GPS_STRING | jq -r '.alt')
        if [ "$SPEED" -ge "$minmoving" ]; then
           echo "We are moving, speed is greater than $minmoving m/s, speed: " $SPEED
            # Track the last known time we were moving
            lastmove_epoch=$(date +%s)
        else
            echo "We're not moving"
        fi
        timestill=$(( $(date +%s) - lastmove_epoch ))

}

function restartIfEnabled() {
    # check if enabled
    if systemctl is-enabled "$1" &>/dev/null; then
            systemctl restart "$1"
    fi
}


function restartAdsbServices() {
    # Restart services that depend on coordinates
        services="readsb dump978-fa adsbexchange-978 adsbexchange-feed adsbexchange-mlat"
        for service in $services; do
                restartIfEnabled $service
        done
}


function update_adsb_config() {
    local lat=$1
    local lon=$2
    local alt=$3
    alt=${alt%.*}m #truncate decimal and add units

    # Check if the file exists
    if [[ ! -f /boot/adsb-config.txt ]]; then
        echo "Error: Configuration file not found."
        return 1
    fi

    # Using sed to update the values in the file
    sudo sed -i "s/^LATITUDE=.*/LATITUDE=$lat/" /boot/adsb-config.txt
    sudo sed -i "s/^LONGITUDE=.*/LONGITUDE=$lon/" /boot/adsb-config.txt
    sudo sed -i "s/^ALTITUDE=.*/ALTITUDE=$alt/" /boot/adsb-config.txt

    timeout 3 wget https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat\&longitude=$lon\&localityLanguage=en -q -T 3 -O /tmp/webconfig/geocode
    cat /tmp/webconfig/geocode | jq -r .'locality' > /tmp/webconfig/location
    cat /tmp/webconfig/geocode | jq -r .'principalSubdivisionCode' >> /tmp/webconfig/location
    cat /tmp/webconfig/geocode | jq -r .'countryName' >> /tmp/webconfig/location

}


#################

while true; do

  refresh_pos

  # Check if LATITUDE or LONGITUDE is greater than .002 difference from the values configured.
if [[ -n "$GPS_LAT" && -n "$GPS_LON" && -n "$GPS_ALT" ]] && \
   [[ "$(echo "scale=10; lat_diff = $LATITUDE - $GPS_LAT; if (lat_diff < 0) -lat_diff else lat_diff" | bc)" > 0.002 ]] && \
   [[ "$(echo "scale=10; lon_diff = $LONGITUDE - $GPS_LON; if (lon_diff < 0) -lon_diff else lon_diff" | bc)" > 0.002 ]] && \
   [[ "$timestill" -gt "$minstill" ]]; then
    echo "Position changed more than .002 deg, and we have been still $timestill seconds."
    echo "Configuring new position of $GPS_LAT, $GPS_LON, $GPS_ALT"
    # echo "Old Positions are, $LATITUDE, $LONGITUDE, $ALTITUDE"
    update_adsb_config "$GPS_LAT" "$GPS_LON" "$GPS_ALT"
    source /boot/adsb-config.txt # read in new configured values
    echo "Restarting Services.."
    restartAdsbServices
fi



 # Turn MLAT on or off if receiver is in motion, or not in motion
 if systemctl is-active --quiet adsbexchange-mlat; then
     # Service is running
     if [ "$timestill" -lt "$minstill" ]; then
         echo "MLAT is running and timestill is less than $minstill, stopping the service..."
         sudo systemctl stop adsbexchange-mlat
     fi
 else
     # Service is not running
     if [ "$timestill" -gt "$minstill" ]; then
         echo "MLAT is not running and timestill is greater than $minstill. Starting MLAT"
         restartIfEnabled adsbexchange-mlat
     fi
 fi



  echo -----
  echo String: $GPS_STRING
  echo GPS LAT LON ALT Speed: $GPS_LAT, $GPS_LON, $GPS_ALT, $SPEED
  echo Configured LAT/LON/ALT $LATITUDE $LONGITUDE $ALTITUDE
  echo "Stationary for: $timestill"
  echo -----


  sleep 60
done
