#!/bin/bash

# Colors for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set directories and files
TOKEN_DIR="files/token"
TOKEN_FILE="$TOKEN_DIR/token.txt"
INFO_DIR="files/ticket-info"
INFO_FILE="$INFO_DIR/2-search-train-info.txt"
JOURNEY_INFO_FILE="files/journey-info.txt"

# Default values - will be used if not found in config file
DEFAULT_SEAT_TYPE=""
DEFAULT_FROM_CITY=""
DEFAULT_TO_CITY=""
DEFAULT_JOURNEY_DATE=$(date +"%d-%b-%Y") # Today's date as default

# Check if force flag is provided
FORCE=false
if [[ "$1" == "-f" ]]; then
    FORCE=true
    echo -e "${YELLOW}Force mode enabled${NC}"
fi

# Function to read a property from journey info file with multiple format support
read_property() {
    local property_name="$1"
    local default_value="$2"
    local value=""
    
    # Try standard key=value format
    value=$(grep -oP "^${property_name}\s*=\s*\K.*" "$JOURNEY_INFO_FILE" 2>/dev/null)
    
    # If not found, try key:value format
    if [ -z "$value" ]; then
        value=$(grep -oP "^${property_name}\s*:\s*\K.*" "$JOURNEY_INFO_FILE" 2>/dev/null)
    fi
    
    # If not found and jq is available, try JSON format
    if [ -z "$value" ] && command -v jq &>/dev/null; then
        value=$(jq -r ".${property_name} // empty" "$JOURNEY_INFO_FILE" 2>/dev/null)
    fi
    
    # If still not found, use default value
    if [ -z "$value" ]; then
        if [ -n "$default_value" ]; then
            echo -e "${YELLOW}Warning: ${property_name} not found in ${JOURNEY_INFO_FILE}, using default: ${default_value}${NC}"
            value="$default_value"
        elif [ "$FORCE" = true ]; then
            echo -e "${YELLOW}Warning: ${property_name} property is missing in ${JOURNEY_INFO_FILE}${NC}"
            value="$default_value"
        else
            echo -e "${RED}Error: ${property_name} property is missing in ${JOURNEY_INFO_FILE}${NC}"
            return 1
        fi
    fi
    
    echo "$value"
    return 0
}

# Ensure directories exist
mkdir -p "$TOKEN_DIR"
mkdir -p "$INFO_DIR"

# Check if journey info file exists
if [ ! -f "$JOURNEY_INFO_FILE" ]; then
    if [ "$FORCE" = true ]; then
        echo -e "${YELLOW}Warning: Journey info file not found at ${JOURNEY_INFO_FILE}, creating with default values${NC}"
        mkdir -p "$(dirname "$JOURNEY_INFO_FILE")"
        echo "journey_date=$DEFAULT_JOURNEY_DATE" > "$JOURNEY_INFO_FILE"
        echo "from_city=$DEFAULT_FROM_CITY" >> "$JOURNEY_INFO_FILE"
        echo "to_city=$DEFAULT_TO_CITY" >> "$JOURNEY_INFO_FILE"
        echo "desired_seat_type=$DEFAULT_SEAT_TYPE" >> "$JOURNEY_INFO_FILE"
    else
        echo -e "${RED}Error: Journey info file not found at ${JOURNEY_INFO_FILE}${NC}"
        exit 1
    fi
fi

# Check if token file exists
if [ ! -f "$TOKEN_FILE" ]; then
  echo -e "${RED}Error: Token file not found at ${TOKEN_FILE}${NC}"
  exit 1
fi

# Read token from file
TOKEN=$(cat "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
  echo -e "${RED}Error: Token is empty${NC}"
  exit 1
fi

# Read journey parameters with fallback to defaults
JOURNEY_DATE=$(read_property "journey_date" "$DEFAULT_JOURNEY_DATE") || exit 1
echo -e "${GREEN}Journey date: ${JOURNEY_DATE}${NC}"

FROM_CITY=$(read_property "from_city" "$DEFAULT_FROM_CITY") || exit 1
echo -e "${GREEN}From city: ${FROM_CITY}${NC}"

TO_CITY=$(read_property "destination_city" "$DEFAULT_TO_CITY") || exit 1
echo -e "${GREEN}To city: ${TO_CITY}${NC}"

DESIRED_SEAT_TYPE=$(read_property "desired_seat_type" "$DEFAULT_SEAT_TYPE") || exit 1
echo -e "${GREEN}Seat class: ${DESIRED_SEAT_TYPE}${NC}"

# Call the API and save the response to a temporary file
echo -e "${YELLOW}Searching for train trips...${NC}"

RESPONSE=$(curl --silent --location "https://railspaapi.shohoz.com/v1.0/web/bookings/search-trips-v2?from_city=$FROM_CITY&to_city=$TO_CITY&date_of_journey=$JOURNEY_DATE&seat_class=$DESIRED_SEAT_TYPE" \
--header 'sec-ch-ua-platform: "Linux"' \
--header "Authorization: Bearer $TOKEN" \
--header 'Referer: https://eticket.railway.gov.bd/' \
--header 'sec-ch-ua: "Chromium";v="134", "Not:A-Brand";v="24", "Google Chrome";v="134"' \
--header 'sec-ch-ua-mobile: ?0' \
--header 'X-Requested-With: XMLHttpRequest' \
--header 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36' \
--header 'Accept: application/json' \
--header 'Content-Type: application/json')

# Check if the response is valid
if [ -z "$RESPONSE" ]; then
    echo -e "${RED}Error: Empty response from API${NC}"
    exit 1
fi

# Check if the response is valid JSON using jq
if ! echo "$RESPONSE" | jq . >/dev/null 2>&1; then
    echo -e "${RED}Error: Invalid JSON response from API${NC}"
    echo "$RESPONSE" | head -20
    exit 1
fi

# Create a temporary file for complete response (for debugging)
echo "$RESPONSE" | jq '.' > "files/train_response.json"
echo -e "${GREEN}Complete API response saved to files/train_response.json${NC}"

# Check if the API returned an error
ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.message // empty' 2>/dev/null)
if [ -n "$ERROR_MESSAGE" ] && [ "$ERROR_MESSAGE" != "null" ]; then
    echo -e "${RED}API Error: ${ERROR_MESSAGE}${NC}"
    exit 1
fi

# Process the response and extract required information for Desired Train
echo -e "${YELLOW}Processing train information...${NC}"

# Check if there are any trains in the response
TRAIN_COUNT=$(echo "$RESPONSE" | jq -r '.data.trains | length // 0' 2>/dev/null)
if [ "$TRAIN_COUNT" -eq 0 ]; then
    echo -e "${RED}Error: No trains found in the response${NC}"
    exit 1
fi

DESIRED_TRAIN=$(read_property "desired_train" "") || exit 1
FILTERED_DATA=$(echo "$RESPONSE" | jq -r --arg desired_train "$DESIRED_TRAIN" '.data.trains[] | select(.trip_number | contains($desired_train)) | {
    trip_number,
    departure_date_time_jd,
    origin_city_name,
    destination_city_name,
    seat_types: [.seat_types[] | {type, trip_id, trip_route_id, route_id}],
    boarding_points: [.boarding_points[] | {trip_point_id}]
}')

# Write the filtered data to the output file
echo "$FILTERED_DATA" > "$INFO_FILE"

# Check if information was found and saved
if [ -s "$INFO_FILE" ]; then
  echo -e "${GREEN}Train information for $DESIRED_TRAIN has been saved to ${INFO_FILE}${NC}"
  cat "$INFO_FILE"  # Display the file contents
else
  echo -e "${YELLOW}No RUPOSHI BANGLA EXPRESS trains found in the response${NC}"
  
  # For debugging, show the available trains
  echo -e "${YELLOW}Available trains:${NC}"
  echo "$RESPONSE" | jq -r '.data.trains[].trip_number'
  
  # If force mode is on, use the first available train
  if [ "$FORCE" = true ]; then
    echo -e "${YELLOW}Force mode: using the first available train${NC}"
    FILTERED_DATA=$(echo "$RESPONSE" | jq -r '.data.trains[0] | {
      trip_number,
      departure_date_time_jd,
      origin_city_name,
      destination_city_name,
      seat_types: [.seat_types[] | {type, trip_id, trip_route_id, route_id}]
    }')
    echo "$FILTERED_DATA" > "$INFO_FILE"
    echo -e "${GREEN}Train information has been saved to ${INFO_FILE}${NC}"
    cat "$INFO_FILE"
  fi
fi

# # Write basic information to 'files/basic-infos.txt'
# BASIC_INFO_FILE="files/basic-infos.txt"
# mkdir -p "$(dirname "$BASIC_INFO_FILE")"
# echo "date_of_journey: $JOURNEY_DATE" > "$BASIC_INFO_FILE"
# echo "seat_class: $DESIRED_SEAT_TYPE" >> "$BASIC_INFO_FILE"
# echo "from_city: $FROM_CITY" >> "$BASIC_INFO_FILE"
# echo "to_city: $TO_CITY" >> "$BASIC_INFO_FILE"

echo -e "${GREEN}Basic information has been saved to ${BASIC_INFO_FILE}${NC}"
echo -e "${GREEN}Process completed.${NC}"