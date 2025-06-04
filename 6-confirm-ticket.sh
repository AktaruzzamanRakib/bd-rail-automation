#!/bin/bash

# Set colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# File paths
TOKEN_FILE="files/token/token.txt"
JOURNEY_INFO_FILE="files/journey-info.txt"
SEARCH_TRAIN_INFO_FILE="files/ticket-info/2-search-train-info.txt"
OTP_FILE="files/otp.txt"
BOOKED_SEATS_FILE="files/your-booked-seat.txt"

# Check if required files exist
if [ ! -f "$TOKEN_FILE" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_FILE${NC}"
    exit 1
fi

if [ ! -f "$JOURNEY_INFO_FILE" ]; then
    echo -e "${RED}Error: Journey info file not found at $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

if [ ! -f "$SEARCH_TRAIN_INFO_FILE" ]; then
    echo -e "${RED}Error: Search train info file not found at $SEARCH_TRAIN_INFO_FILE${NC}"
    exit 1
fi

if [ ! -f "$OTP_FILE" ]; then
    echo -e "${RED}Error: OTP file not found at $OTP_FILE${NC}"
    exit 1
fi

if [ ! -f "$BOOKED_SEATS_FILE" ]; then
    echo -e "${RED}Error: Booked seats file not found at $BOOKED_SEATS_FILE${NC}"
    exit 1
fi

# Read token
TOKEN=$(cat "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Token is empty${NC}"
    exit 1
fi

# Read OTP
if [ -f "$OTP_FILE" ]; then
    OTP=$(grep -oP '(?<=otp:)[0-9]+' "$OTP_FILE")
    if [ -z "$OTP" ]; then
        echo -e "${RED}Error: OTP is empty or not found in $OTP_FILE${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: OTP file not found at $OTP_FILE${NC}"
    exit 1
fi

# Print the value of OTP
echo -e "${CYAN}OTP: $OTP${NC}"

# Step 3: Extract boarding_point_id from search train info
BOARDING_POINT_ID=$(grep -o '"boarding_points":\[{"trip_point_id":[0-9]\+' "$SEARCH_TRAIN_INFO_FILE" | grep -o '[0-9]\+' | head -1)

if [ -z "$BOARDING_POINT_ID" ]; then
    # Try alternative pattern
    BOARDING_POINT_ID=$(grep -o '"boarding_points":\s*\[{[^}]*"trip_point_id":\s*[0-9]\+' "$SEARCH_TRAIN_INFO_FILE" | grep -o '"trip_point_id":\s*[0-9]\+' | grep -o '[0-9]\+' | head -1)
fi

if [ -z "$BOARDING_POINT_ID" ]; then
    # Try another pattern
    BOARDING_POINT_ID=$(grep -o '"trip_point_id":\s*[0-9]\+' "$SEARCH_TRAIN_INFO_FILE" | grep -o '[0-9]\+' | head -1)
fi

if [ -z "$BOARDING_POINT_ID" ]; then
    echo -e "${RED}Error: Could not extract boarding point ID${NC}"
    exit 1
fi

# Step 4: Read journey info
FROM_CITY=$(grep -o '"from_city":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
TO_CITY=$(grep -o '"destination_city":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
EMAIL=$(grep -o '"email":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
PHONE=$(grep -o '"phone":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
DATE_OF_JOURNEY=$(grep -o '"journey_date":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
SEAT_CLASS=$(grep -o '"desired_seat_type":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' "')
NUMBER_OF_SEAT=$(grep -o '"number_of_seat":[^,}]*' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d ' ",')

# Display extracted email and phone
echo -e "${CYAN}Email: $EMAIL${NC}"
echo -e "${CYAN}Phone: $PHONE${NC}"

# Step 5, 6, 7: Read passenger details
# Extract passenger genders
# Read passenger genders from the JSON file
PASSENGER_GENDERS=$(jq -r '.passenger_genders | join(",")' "$JOURNEY_INFO_FILE")
IFS=',' read -ra GENDER_ARRAY <<< "$PASSENGER_GENDERS"

# Add double quotes to each value in GENDER_ARRAY
for i in "${!GENDER_ARRAY[@]}"; do
    GENDER_ARRAY[$i]="\"${GENDER_ARRAY[$i]}\""
done

# Add "Adult" to the array until its size matches NUMBER_OF_SEAT
while [ "${#GENDER_ARRAY[@]}" -lt "$NUMBER_OF_SEAT" ]; do
    GENDER_ARRAY+=("\"male\"")
done

# Join the array back into a string
PASSENGER_GENDERS=$(IFS=','; echo "${GENDER_ARRAY[*]}")

# Print passenger Gender
echo -e "${CYAN}Passenger genders: $PASSENGER_GENDERS${NC}"

# Extract passenger types
PASSENGER_TYPES=$(jq -r '.passenger_types | join(",")' "$JOURNEY_INFO_FILE")
IFS=',' read -ra TYPE_ARRAY <<< "$PASSENGER_TYPES"

# Add double quotes to each value in TYPE_ARRAY
for i in "${!TYPE_ARRAY[@]}"; do
    TYPE_ARRAY[$i]="\"${TYPE_ARRAY[$i]}\""
done

# Add "Adult" to the array until its size matches NUMBER_OF_SEAT
while [ "${#TYPE_ARRAY[@]}" -lt "$NUMBER_OF_SEAT" ]; do
    TYPE_ARRAY+=("\"Adult\"")
done

# Join the array back into a string
PASSENGER_TYPES=$(IFS=','; echo "${TYPE_ARRAY[*]}")

# Print passenger types
echo -e "${CYAN}Passenger types: $PASSENGER_TYPES${NC}"




# Read passenger names from the JSON file
PASSENGER_NAMES=$(jq -r '.passenger_names | join(",")' "$JOURNEY_INFO_FILE")
IFS=',' read -ra NAME_ARRAY <<< "$PASSENGER_NAMES"

# Add double quotes to each value in NAME_ARRAY
for i in "${!NAME_ARRAY[@]}"; do
    NAME_ARRAY[$i]="\"${NAME_ARRAY[$i]}\""
done

# Add a default name to the array until its size matches NUMBER_OF_SEAT
while [ "${#NAME_ARRAY[@]}" -lt "$NUMBER_OF_SEAT" ]; do
    NAME_ARRAY+=("\"DEFAULT Passenger Name\"")
done

# Join the array back into a string
PASSENGER_NAMES=$(IFS=','; echo "${NAME_ARRAY[*]}")

# Print passenger names
echo -e "${CYAN}Passenger names: $PASSENGER_NAMES${NC}"



# Make sure we have enough values for each array based on number of seats
GENDER_JSON="["
TYPE_JSON="["
NAME_JSON="["

for ((i=0; i<$NUMBER_OF_SEAT; i++)); do
    if [ $i -lt ${#GENDER_ARRAY[@]} ]; then
        GENDER_JSON+="${GENDER_ARRAY[$i]}"
    else
        GENDER_JSON+="\"male\""
    fi
    
    if [ $i -lt ${#TYPE_ARRAY[@]} ]; then
        TYPE_JSON+="${TYPE_ARRAY[$i]}"
    else
        TYPE_JSON+="\"Adult\""
    fi
    
    if [ $i -lt ${#NAME_ARRAY[@]} ]; then
        NAME_JSON+="${NAME_ARRAY[$i]}"
    else
        NAME_JSON+="\"DEFAULT Passenger Name\""
    fi
    
    if [ $i -lt $((NUMBER_OF_SEAT-1)) ]; then
        GENDER_JSON+=","
        TYPE_JSON+=","
        NAME_JSON+=","
    fi
done

GENDER_JSON+="]"
TYPE_JSON+="]"
NAME_JSON+="]"

# Step 8: Create null arrays for passport and other fields
function create_array_values() {
    local value=$1
    local count=$NUMBER_OF_SEAT
    local result="["
    
    for ((i=0; i<count; i++)); do
        result+="$value"
        if [ $i -lt $((count-1)) ]; then
            result+=","
        fi
    done
    
    result+="]"
    echo "$result"
}

EMPTY_ARRAY=$(create_array_values '""')
NULL_ARRAY=$(create_array_values 'null')

# Step 9: Read booking info from booked seats file
# Read TRIP_ID and TRIP_ROUTE_ID from 'files/trip-info.txt'
TRIP_INFO_FILE="files/trip-info.txt"

if [ ! -f "$TRIP_INFO_FILE" ]; then
    echo -e "${RED}Error: Trip info file not found at $TRIP_INFO_FILE${NC}"
    exit 1
fi

TRIP_ID=$(grep "TRIP_ID" "$TRIP_INFO_FILE" | cut -d':' -f2 | tr -d ' ,')
TRIP_ROUTE_ID=$(grep "TRIP_ROUTE_ID" "$TRIP_INFO_FILE" | cut -d':' -f2 | tr -d ' ,')

# Validate TRIP_ID and TRIP_ROUTE_ID
if [ -z "$TRIP_ID" ]; then
    echo -e "${RED}Error: TRIP_ID is missing or empty in $TRIP_INFO_FILE${NC}"
    exit 1
fi

if [ -z "$TRIP_ROUTE_ID" ]; then
    echo -e "${RED}Error: TRIP_ROUTE_ID is missing or empty in $TRIP_INFO_FILE${NC}"
    exit 1
fi

# Extract ticket IDs as an array
TICKET_IDS_STR=$(grep -A 20 "ticket_ids" "$BOOKED_SEATS_FILE" | grep -o '[0-9]\+' | head -n "$NUMBER_OF_SEAT" | tr '\n' ',' | sed 's/,$//')
IFS=',' read -ra TICKET_IDS_ARRAY <<< "$TICKET_IDS_STR"

# Format ticket IDs for JSON
TICKET_IDS_JSON="["
for i in "${!TICKET_IDS_ARRAY[@]}"; do
    if [ "$i" -eq 0 ]; then
        TICKET_IDS_JSON+="${TICKET_IDS_ARRAY[$i]}"
    else
        TICKET_IDS_JSON+=",$((TICKET_IDS_ARRAY[$i]))"
    fi
done
TICKET_IDS_JSON+="]"

# Create the payload
PAYLOAD='{
    "is_bkash_online": true,
    "boarding_point_id": '$BOARDING_POINT_ID',
    "contactperson": 0,
    "from_city": "'$FROM_CITY'",
    "to_city": "'$TO_CITY'",
    "date_of_journey": "'$DATE_OF_JOURNEY'",
    "seat_class": "'$SEAT_CLASS'",
    "gender": '$GENDER_JSON',
    "page": '$EMPTY_ARRAY',
    "passengerType": '$TYPE_JSON',
    "pemail": "'$EMAIL'",
    "pmobile": "'$PHONE'",
    "pname": '$NAME_JSON',
    "ppassport": '$EMPTY_ARRAY',
    "priyojon_order_id": null,
    "referral_mobile_number": null,
    "ticket_ids": '$TICKET_IDS_JSON',
    "trip_id": '$TRIP_ID',
    "trip_route_id": '$TRIP_ROUTE_ID',
    "isShohoz": 0,
    "enable_sms_alert": 0,
    "first_name": '$NULL_ARRAY',
    "middle_name": '$NULL_ARRAY',
    "last_name": '$NULL_ARRAY',
    "date_of_birth": '$NULL_ARRAY',
    "nationality": '$NULL_ARRAY',
    "passport_type": '$NULL_ARRAY',
    "passport_no": '$NULL_ARRAY',
    "passport_expiry_date": '$NULL_ARRAY',
    "visa_type": '$NULL_ARRAY',
    "visa_no": '$NULL_ARRAY',
    "visa_issue_place": '$NULL_ARRAY',
    "visa_issue_date": '$NULL_ARRAY',
    "visa_expire_date": '$NULL_ARRAY',
    "otp": "'$OTP'",
    "selected_mobile_transaction": 1
}'


# Save payload to a file for debugging
mkdir -p files
echo "$PAYLOAD" > "files/confirm_payload.json"
echo -e "${YELLOW}Payload saved to files/confirm_payload.json${NC}"

# Print the payload for debugging
# echo -e "${BLUE}Payload:${NC}"
# echo "$PAYLOAD" | jq .

# Read the payload from 'files/confirm_payload.json'
if [ -f "files/confirm_payload.json" ]; then
    FULL_PAYLOAD=$(cat "files/confirm_payload.json")
else
    echo -e "${RED}Error: Payload file not found at files/confirm_payload.json${NC}"
    exit 1
fi

# Make the API call
echo -e "${YELLOW}Making API call...${NC}"
RESPONSE=$(curl --silent --location --request PATCH 'https://railspaapi.shohoz.com/v1.0/web/bookings/confirm' \
--header 'accept: application/json' \
--header 'accept-language: en-US,en;q=0.9' \
--header "authorization: Bearer $TOKEN" \
--header 'content-type: application/json' \
--header 'origin: https://eticket.railway.gov.bd' \
--header 'priority: u=1, i' \
--header 'referer: https://eticket.railway.gov.bd/' \
--header 'sec-fetch-mode: cors' \
--header 'sec-fetch-site: cross-site' \
--data-raw "$FULL_PAYLOAD")

# Print the full API response
echo -e "\n${BLUE}Full API Response:${NC}"
echo "$RESPONSE" | jq .

# Save response to a file
echo "$RESPONSE" > "files/confirm_response.json"
echo -e "${YELLOW}Response saved to files/confirm_response.json${NC}"

# Display the response
echo -e "\n${BLUE}API Response:${NC}"
echo "$RESPONSE" | grep -o '"message":"[^"]*"' | cut -d'"' -f4
echo

# Extract and display redirect URL if available
REDIRECT_URL=$(echo "$RESPONSE" | grep -o '"redirectUrl":"[^"]*"' | cut -d'"' -f4 | sed 's|\\||g' | sed 's|//|/|g')
if [ -n "$REDIRECT_URL" ]; then
    echo -e "${GREEN}Redirect URL: $REDIRECT_URL${NC}"
    echo -e "${YELLOW}Opening payment page in your default browser...${NC}"
    
    # Detect the operating system and open the URL in the default browser
    if command -v xdg-open &> /dev/null; then
        # Linux
        xdg-open "$REDIRECT_URL"
    elif command -v open &> /dev/null; then
        # macOS
        open "$REDIRECT_URL"
    elif command -v start &> /dev/null; then
        # Windows
        start "$REDIRECT_URL"
    else
        echo -e "${YELLOW}Please open the following URL in your browser:${NC}"
        echo -e "${BLUE}$REDIRECT_URL${NC}"
    fi
fi

# Extract and display booking details if available
if echo "$RESPONSE" | grep -q '"order_id"'; then
    ORDER_ID=$(echo "$RESPONSE" | grep -o '"order_id":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}Order ID: $ORDER_ID${NC}"
fi