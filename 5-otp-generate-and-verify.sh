#!/bin/bash

# Set colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
TOKEN_FILE="files/token/token.txt"
BOOKED_SEATS_FILE="files/your-booked-seat.txt"

# Function to handle OTP verification
verify_otp() {
    local start_time=$1
    local timeout=$2
    local booked_seats_json=$3
    local token=$4
    
    # Calculate remaining time
    local current_time=$(date +%s)
    local elapsed_time=$((current_time - start_time))
    local remaining_time=$((timeout - elapsed_time))
    
    if [ $remaining_time -le 0 ]; then
        echo -e "${RED}Time limit exceeded. Please start the booking process again.${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Please enter the OTP (timeout in $remaining_time seconds):${NC}"
    
    # Read OTP with timeout
    read -t $remaining_time OTP
    
    # Check if read was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}OTP entry timed out.${NC}"
        exit 1
    fi
    
    # Validate OTP format
    if ! [[ "$OTP" =~ ^[0-9]{1,4}$ ]]; then
        echo -e "${RED}Invalid OTP format. Must be numeric and not more than 4 digits.${NC}"
        verify_otp "$start_time" "$timeout" "$booked_seats_json" "$token"
        return
    fi
    
    echo -e "${GREEN}OTP received: $OTP${NC}"
    
    # Create the verification JSON payload
    VERIFY_PAYLOAD=$(echo "$booked_seats_json" | sed 's/}/,"otp":"'$OTP'"}/')

    
    # Make the API call to verify-otp
    VERIFY_RESPONSE=$(curl --silent --location 'https://railspaapi.shohoz.com/v1.0/web/bookings/verify-otp' \
    --header "Authorization: Bearer $token" \
    --header 'Referer: https://eticket.railway.gov.bd/' \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data "$VERIFY_PAYLOAD")
    
    # Display the API response
    echo -e "${BLUE}API Response:${NC}"
    echo "$VERIFY_RESPONSE" | jq . 2>/dev/null || echo "$VERIFY_RESPONSE"
    
    # Check if the verification was successful
    VERIFICATION_SUCCESS=$(echo "$VERIFY_RESPONSE" | grep -o '"success":true' | wc -l)
    
    if [ "$VERIFICATION_SUCCESS" -gt 0 ]; then
        echo -e "${GREEN}🎉 Congratulations! Your OTP has been successfully verified.${NC}"
        echo -e "${GREEN}Your train tickets have been successfully booked!${NC}"
    else
        echo -e "${RED}Invalid OTP. Please try again.${NC}"
        
        # Try again with the same start time
        verify_otp "$start_time" "$timeout" "$booked_seats_json" "$token"
    fi
}

# Check if required files exist
if [ ! -f "$TOKEN_FILE" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_FILE${NC}"
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

# Read booked seats JSON
BOOKED_SEATS_JSON=$(cat "$BOOKED_SEATS_FILE")
if [ -z "$BOOKED_SEATS_JSON" ]; then
    echo -e "${RED}Error: Booked seats JSON is empty${NC}"
    exit 1
fi


# Make the API call to passenger-details
RESPONSE=$(curl --silent --location 'https://railspaapi.shohoz.com/v1.0/web/bookings/passenger-details' \
--header 'accept: application/json' \
--header 'accept-language: en-US,en;q=0.9' \
--header "authorization: Bearer $TOKEN" \
--header 'content-type: application/json' \
--header 'origin: https://eticket.railway.gov.bd' \
--header 'priority: u=1, i' \
--header 'referer: https://eticket.railway.gov.bd/' \
--header 'sec-fetch-mode: cors' \
--header 'sec-fetch-site: cross-site' \
--data "$BOOKED_SEATS_JSON")

# Display the API response
echo -e "${BLUE}API Response:${NC}"
echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"

# Check if the API call was successful
SUCCESS=$(echo "$RESPONSE" | grep -o '"success":true' | wc -l)

if [ "$SUCCESS" -eq 0 ]; then
    echo -e "${RED}Error: API call was not successful${NC}"
    exit 1
fi

echo -e "${GREEN}API call was successful. An OTP has been sent.${NC}"

# Start time for OTP prompt
START_TIME=$(date +%s)
TIMEOUT=90

# Start the OTP verification process
verify_otp "$START_TIME" "$TIMEOUT" "$BOOKED_SEATS_JSON" "$TOKEN"

# Write the OTP to 'files/otp.txt'
OTP_FILE="files/otp.txt"
echo "otp:$OTP" > "$OTP_FILE"
echo -e "${GREEN}OTP has been saved to $OTP_FILE${NC}"
exit 0