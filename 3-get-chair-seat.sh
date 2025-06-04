#!/bin/bash

# Colors for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# File paths
TOKEN_FILE="files/token/token.txt"
TRAIN_INFO_FILE="files/ticket-info/2-search-train-info.txt"
OUTPUT_FILE="files/seat.txt"
JOURNEY_INFO_FILE="files/journey-info.txt"

# Create directory if it doesn't exist
mkdir -p $(dirname "$OUTPUT_FILE")

# 1. Read token from file
if [ ! -f "$TOKEN_FILE" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_FILE${NC}"
    exit 1
fi

TOKEN=$(cat "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Token is empty${NC}"
    exit 1
fi

# 2. Get trip_id, trip_route_id and route_id for S_CHAIR from train info file
if [ ! -f "$TRAIN_INFO_FILE" ]; then
    echo -e "${RED}Error: Train info file not found at $TRAIN_INFO_FILE${NC}"
    exit 1
fi


if [ ! -f "$JOURNEY_INFO_FILE" ]; then
    echo -e "${RED}Error: Journey info file not found at $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

# Extract desired_seat_type from journey-info.txt
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq: sudo apt install jq${NC}"
    exit 1
fi

DESIRED_SEAT_TYPE=$(jq -r '.desired_seat_type' "$JOURNEY_INFO_FILE")

echo -e "${YELLOW}Desired seat type: $DESIRED_SEAT_TYPE${NC}"

if [ -z "$DESIRED_SEAT_TYPE" ]; then
    echo -e "${RED}Error: desired_seat_type is not specified in $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

# Extract trip_id, trip_route_id and route_id for the desired seat type
TRIP_ID=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .trip_id' "$TRAIN_INFO_FILE")
TRIP_ROUTE_ID=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .trip_route_id' "$TRAIN_INFO_FILE")
ROUTE_ID=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .route_id' "$TRAIN_INFO_FILE")
SEAT_TYPE=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .type' "$TRAIN_INFO_FILE")

if [ -z "$SEAT_TYPE" ] || [ -z "$TRIP_ID" ] || [ -z "$TRIP_ROUTE_ID" ] || [ -z "$ROUTE_ID" ]; then
    echo -e "${RED}Error: Could not find information for seat type: $DESIRED_SEAT_TYPE${NC}"
    exit 1
fi

# Write TRIP_ID, TRIP_ROUTE_ID, ROUTE_ID, and SEAT_TYPE to 'files/trip-info.txt'
TRIP_INFO_FILE="files/trip-info.txt"
mkdir -p $(dirname "$TRIP_INFO_FILE")

echo "TRIP_ID:$TRIP_ID" > "$TRIP_INFO_FILE"
echo "TRIP_ROUTE_ID:$TRIP_ROUTE_ID" >> "$TRIP_INFO_FILE"
echo "ROUTE_ID:$ROUTE_ID" >> "$TRIP_INFO_FILE"
echo "SEAT_TYPE:$SEAT_TYPE" >> "$TRIP_INFO_FILE"

echo -e "${GREEN}Successfully wrote trip information to $TRIP_INFO_FILE${NC}"
echo -e "${GREEN}Found trip_id: $SEAT_TYPE, Found trip_id: $TRIP_ID, trip_route_id: $TRIP_ROUTE_ID, route_id: $ROUTE_ID for seat type: $DESIRED_SEAT_TYPE${NC}"

echo -e "${YELLOW}Fetching seat availability data...${NC}"

# Fetch seat layout data using the provided API details with dynamic values
response=$(curl -s "https://railspaapi.shohoz.com/v1.0/web/bookings/seat-layout?trip_id=$TRIP_ID&trip_route_id=$TRIP_ROUTE_ID" \
  -H 'sec-ch-ua-platform: "Linux"' \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Referer: https://eticket.railway.gov.bd/' \
  -H 'sec-ch-ua: "Chromium";v="134", "Not:A-Brand";v="24", "Google Chrome";v="134"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36' \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json')

# Check if curl was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to fetch data from API.${NC}"
    exit 1
fi

# Save the entire response for debugging (optional)
echo "$response" > files/debug_api_response.json

# Check if the API returned empty content or an error
if [ -z "$response" ]; then
    echo -e "${RED}Error: API returned empty response.${NC}"
    exit 1
fi

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Using alternative parsing method.${NC}"
    echo -e "${YELLOW}Install jq for more reliable JSON parsing: sudo apt install jq${NC}"
    
    # Extract ticket IDs using grep and sed where seat_availability is 1
    ticket_ids=$(echo "$response" | grep -o '"seat_availability":1.*"ticket_id":[0-9]*' | sed 's/.*ticket_id":\([0-9]*\).*/\1/')
else
    # Use jq for better JSON parsing - this handles the nested structure
    ticket_ids=$(echo "$response" | jq -r '
        .data.seatLayout | 
        if type == "array" then
            .[] | .layout | 
            if type == "array" then
                .[] | .[] | 
                select(.seat_availability == 1) | 
                .ticket_id
            else empty end
        else empty end
    ')
fi

# Check if we got any available tickets
if [ -z "$ticket_ids" ]; then
    echo -e "${RED}No available seats found.${NC}"
    # Still write the route_id on the first line
    echo "route_id:$ROUTE_ID" > "$OUTPUT_FILE"
    echo "seats:[]" >> "$OUTPUT_FILE"
    exit 0
fi

# Count the number of tickets for status display
ticket_count=$(echo "$ticket_ids" | wc -w)
echo -e "${GREEN}Found $ticket_count available seats.${NC}"

# Clear previous content and write route_id on the first line
echo "route_id:$TRIP_ROUTE_ID" > "$OUTPUT_FILE"

# Start the seats array on the second line
echo -n "seats:[" >> "$OUTPUT_FILE"

# Process and write all ticket IDs in one line as an array
first=true
for id in $ticket_ids; do
    if [ "$first" = true ]; then
        echo -n "$id" >> "$OUTPUT_FILE"
        first=false
    else
        echo -n " $id" >> "$OUTPUT_FILE"
    fi
done

# Close the array
echo "]" >> "$OUTPUT_FILE"

echo -e "${GREEN}Successfully wrote route_id and available ticket IDs to $OUTPUT_FILE${NC}"

# Show the content of the file
# echo -e "${YELLOW}Content of $OUTPUT_FILE:${NC}"
# cat "$OUTPUT_FILE"

exit 0