#!/bin/bash

# Set colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
TOKEN_FILE="files/token/token.txt"
SEAT_FILE="files/seat.txt"
OUTPUT_FILE="files/your-booked-seat.txt"
TRAIN_INFO_FILE="files/ticket-info/2-search-train-info.txt"
JOURNEY_INFO_FILE="files/journey-info.txt"

# Debug mode
DEBUG=true

# Check if required files exist
if [ ! -f "$TOKEN_FILE" ]; then
    echo -e "${RED}Error: Token file not found at $TOKEN_FILE${NC}"
    exit 1
fi

if [ ! -f "$SEAT_FILE" ]; then
    echo -e "${RED}Error: Seat file not found at $SEAT_FILE${NC}"
    exit 1
fi

if [ ! -f "$TRAIN_INFO_FILE" ]; then
    echo -e "${RED}Error: Train info file not found at $TRAIN_INFO_FILE${NC}"
    exit 1
fi

if [ ! -f "$JOURNEY_INFO_FILE" ]; then
    echo -e "${RED}Error: Journey info file not found at $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

# Read number of seats from journey-info.txt
# Try JSON format first
if command -v jq &> /dev/null && grep -q "^{" "$JOURNEY_INFO_FILE"; then
    numberOfSeat=$(jq -r '.number_of_seat // empty' "$JOURNEY_INFO_FILE" 2>/dev/null)
    # Convert string to integer if needed
    if [[ "$numberOfSeat" =~ ^[0-9]+$ ]]; then
        numberOfSeat=$((numberOfSeat))
    else
        numberOfSeat=""
    fi
fi

# If not found or not valid, try key=value format
if [ -z "$numberOfSeat" ] || ! [[ "$numberOfSeat" =~ ^[1-4]$ ]]; then
    numberOfSeat=$(grep "^number_of_seat=" "$JOURNEY_INFO_FILE" | cut -d'=' -f2 | tr -d ' ' 2>/dev/null)
    # If still not found, try key: value format
    if [ -z "$numberOfSeat" ]; then
        numberOfSeat=$(grep -E "^number_of_seat[[:space:]]*:" "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d '[:space:]' 2>/dev/null)
    fi
fi

# Validate input is between 1-4
if [ -z "$numberOfSeat" ] || ! [[ "$numberOfSeat" =~ ^[1-4]$ ]]; then
    echo -e "${RED}Error: Invalid seat number, select between 1-4 numbers${NC}"
    echo -e "${YELLOW}Please set 'number_of_seat' property in $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}Will attempt to reserve $numberOfSeat seats (from journey-info.txt)${NC}"

# Read token
TOKEN=$(cat "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
    echo -e "${RED}Error: Token is empty${NC}"
    exit 1
fi

# Read route_id from the first line of the seat file
ROUTE_ID=$(grep "route_id:" "$SEAT_FILE" | cut -d':' -f2)
if [ -z "$ROUTE_ID" ]; then
    echo -e "${RED}Error: Could not find route_id in $SEAT_FILE${NC}"
    exit 1
fi

# Extract seat IDs from the second line (seats:[...])
SEATS_LINE=$(grep "seats:" "$SEAT_FILE")
SEATS_ARRAY=$(echo "$SEATS_LINE" | sed 's/seats:\[\([^]]*\)\]/\1/')

# Convert to array
IFS=' ' read -r -a ALL_SEATS <<< "$SEATS_ARRAY"

# Check if we have enough seats
TOTAL_SEATS=${#ALL_SEATS[@]}
if [ $TOTAL_SEATS -lt $numberOfSeat ]; then
    echo -e "${RED}Error: Not enough seats available. Found $TOTAL_SEATS, needed $numberOfSeat${NC}"
    exit 1
fi

# echo -e "${GREEN}Found $TOTAL_SEATS available seats: ${ALL_SEATS[*]}${NC}"
echo -e "${GREEN}Using route_id: $ROUTE_ID${NC}"

# Get trip_id and trip_route_id from the train info file
# Read the value of 'desired_seat_type' from JOURNEY_INFO_FILE
# Extract 'desired_seat_type' from JSON format in JOURNEY_INFO_FILE
if command -v jq &> /dev/null; then
    DESIRED_SEAT_TYPE=$(jq -r '.desired_seat_type // empty' "$JOURNEY_INFO_FILE")
else
    DESIRED_SEAT_TYPE=$(grep -E '"desired_seat_type"[[:space:]]*:' "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d '[:space:]"')
fi

# Exit if DESIRED_SEAT_TYPE is null or does not exist
if [ -z "$DESIRED_SEAT_TYPE" ]; then
    echo -e "${RED}Error: 'desired_seat_type' is not set in $JOURNEY_INFO_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}Desired seat type: $DESIRED_SEAT_TYPE${NC}"

# Extract 'trip_id' and 'trip_route_id' from TRAIN_INFO_FILE
if command -v jq &> /dev/null; then
    TRIP_ID=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .trip_id' "$TRAIN_INFO_FILE")
    TRIP_ROUTE_ID=$(jq -r --arg type "$DESIRED_SEAT_TYPE" '.seat_types[] | select(.type == $type) | .trip_route_id' "$TRAIN_INFO_FILE")
else
    TRIP_ID=$(grep -A 5 "\"type\": \"$DESIRED_SEAT_TYPE\"" "$TRAIN_INFO_FILE" | grep "\"trip_id\"" | cut -d':' -f2 | tr -d '[:space:],')
    TRIP_ROUTE_ID=$(grep -A 5 "\"type\": \"$DESIRED_SEAT_TYPE\"" "$TRAIN_INFO_FILE" | grep "\"trip_route_id\"" | cut -d':' -f2 | tr -d '[:space:],')
fi

# Exit if TRIP_ID or TRIP_ROUTE_ID is null
if [ -z "$TRIP_ID" ] || [ -z "$TRIP_ROUTE_ID" ]; then
    echo -e "${RED}Error: Could not find trip_id or trip_route_id for type '$DESIRED_SEAT_TYPE' in $TRAIN_INFO_FILE${NC}"
    exit 1
fi


echo -e "${GREEN}Using trip_id: $TRIP_ID and trip_route_id: $TRIP_ROUTE_ID${NC}"

# Find sequences of 5 continuous numbers
echo -e "${YELLOW}Looking for continuous sequences of 5 seats...${NC}"

# Array to store sequences of 5 continuous numbers
continuous_sequences=()

# Loop through the seats to find continuous sequences
for i in $(seq 0 $((TOTAL_SEATS - 5))); do
    # Check if we have 5 consecutive numbers
    if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ] && \
       [ $((ALL_SEATS[i+2] - ALL_SEATS[i+1])) -eq 1 ] && \
       [ $((ALL_SEATS[i+3] - ALL_SEATS[i+2])) -eq 1 ] && \
       [ $((ALL_SEATS[i+4] - ALL_SEATS[i+3])) -eq 1 ]; then
        # Store this sequence start index
        continuous_sequences+=($i)
        # echo -e "${GREEN}Found continuous sequence: ${ALL_SEATS[i]} ${ALL_SEATS[i+1]} ${ALL_SEATS[i+2]} ${ALL_SEATS[i+3]} ${ALL_SEATS[i+4]}${NC}"
    fi
done

# Check if we found any continuous sequences
has_five_continuous=false
if [ ${#continuous_sequences[@]} -gt 0 ]; then
    has_five_continuous=true
    echo -e "${GREEN}Found ${#continuous_sequences[@]} sequences of 5 continuous numbers${NC}"
else
    echo -e "${YELLOW}No sequences of 5 continuous numbers found${NC}"
fi

# Function to reserve a seat and handle API call
reserve_seat() {
    local ticket_id=$1
    echo -e "${YELLOW}Attempting to reserve seat with ticket_id: $ticket_id${NC}"
    
    # Make the API call
    local response=$(curl --silent --location --request PATCH "https://railspaapi.shohoz.com/v1.0/web/bookings/reserve-seat?ticket_id=$ticket_id&route_id=$ROUTE_ID" \
    --header "Authorization: Bearer $TOKEN")

    #COMMENTED
    # echo -e "${BLUE}Callable cURL:${NC}"
    # echo "curl --silent --location --request PATCH \"https://railspaapi.shohoz.com/v1.0/web/bookings/reserve-seat?ticket_id=$ticket_id&route_id=$ROUTE_ID\" --header \"Authorization: Bearer $TOKEN\""
    
    # Parse the response to get error status
    if [ -z "$response" ]; then
        echo -e "${RED}Error: Empty response from API${NC}"
        return 1
    fi
    
    # Display the API response
    echo -e "${BLUE}API Response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    
    # Save response to debug file
    echo "$response" > "/tmp/reserve_response_$ticket_id.json"
    
    # Check if response contains successful reservation (no error code 422)
    if echo "$response" | grep -q '"error":{"code":422'; then
        error_msg=$(echo "$response" | grep -o '"error_msg":"[^"]*"' | sed 's/"error_msg":"\(.*\)"/\1/')
        echo -e "${RED}Failed to reserve seat $ticket_id: $error_msg${NC}"
        return 1
    else
        # Assuming success if we don't have the error code 422
        echo -e "${GREEN}Successfully reserved seat $ticket_id${NC}"
        return 0
    fi
}

# Initialize variables for the booking process
booked_seats=()
selected_tickets=()
flag=0

# Function to find a random odd seat
find_random_odd_seat() {
    local odd_seats=()
    for seat in "${ALL_SEATS[@]}"; do
        if [ $((seat % 2)) -eq 1 ]; then
            odd_seats+=($seat)
        fi
    done
    
    if [ ${#odd_seats[@]} -gt 0 ]; then
        local random_index=$((RANDOM % ${#odd_seats[@]}))
        echo ${odd_seats[$random_index]}
        return 0
    fi
    
    # No odd seats found, return a random seat
    local random_index=$((RANDOM % ${#ALL_SEATS[@]}))
    echo ${ALL_SEATS[$random_index]}
    return 0
}

# Function to check if a seat is available
is_seat_available() {
    local seat=$1
    for s in "${ALL_SEATS[@]}"; do
        if [ $s -eq $seat ]; then
            return 0
        fi
    done
    return 1
}

# Function to find a seat with multiples
find_seat_with_multiple() {
    local base=$1
    local multiplier=$2
    local max_multiple=$3
    
    for i in $(seq 1 $max_multiple); do
        local candidate=$((base + multiplier * i))
        if is_seat_available $candidate; then
            echo $candidate
            return 0
        fi
    done
    
    echo -1
    return 1
}

# Select seats based on the algorithm
case $numberOfSeat in
    1)  
        if [ "$has_five_continuous" = true ]; then
            # Get the first sequence
            seq_start=${continuous_sequences[0]}
            
            # 2nd seat in the sequence
            target_seat=${ALL_SEATS[$((seq_start + 1))]}
            echo -e "${GREEN}Selected 2nd seat from continuous sequence: $target_seat${NC}"
            
            # Try to reserve the seat
            if reserve_seat $target_seat; then
                booked_seats+=($target_seat)
                flag=$((flag + 1))
            else
                # Rule: if j is not available, try j+(6*v) where v is 1-3
                echo -e "${YELLOW}Primary seat not available, trying multiples of 6${NC}"
                alternative_seat=$(find_seat_with_multiple $target_seat 6 3)
                
                if [ $alternative_seat -ne -1 ]; then
                    if reserve_seat $alternative_seat; then
                        booked_seats+=($alternative_seat)
                        flag=$((flag + 1))
                    fi
                else
                    # Last resort: random odd seat
                    random_seat=$(find_random_odd_seat)
                    echo -e "${YELLOW}Trying random odd seat: $random_seat${NC}"
                    if reserve_seat $random_seat; then
                        booked_seats+=($random_seat)
                        flag=$((flag + 1))
                    fi
                fi
            fi
        else
            # No continuous sequence, select a random odd seat
            random_seat=$(find_random_odd_seat)
            echo -e "${YELLOW}No continuous sequence found. Using random odd seat: $random_seat${NC}"
            if reserve_seat $random_seat; then
                booked_seats+=($random_seat)
                flag=$((flag + 1))
            fi
        fi
        ;;
        
    2)  
        if [ "$has_five_continuous" = true ]; then
            # Get the first sequence
            seq_start=${continuous_sequences[0]}
            
            # 1st and 2nd seats in the sequence
            first_seat=${ALL_SEATS[$seq_start]}
            second_seat=${ALL_SEATS[$((seq_start + 1))]}
            
            echo -e "${GREEN}Selected 1st and 2nd seats from continuous sequence: $first_seat $second_seat${NC}"
            
            # Try to reserve the first seat
            if reserve_seat $first_seat; then
                booked_seats+=($first_seat)
                flag=$((flag + 1))
                
                # Try to reserve the second seat
                if reserve_seat $second_seat; then
                    booked_seats+=($second_seat)
                    flag=$((flag + 1))
                else
                    # Rule: if j is not available, try i+(7*v) where v is 1-3
                    echo -e "${YELLOW}Second seat not available, trying multiples of 7${NC}"
                    alternative_seat=$(find_seat_with_multiple $first_seat 7 3)
                    
                    if [ $alternative_seat -ne -1 ]; then
                        if reserve_seat $alternative_seat; then
                            booked_seats+=($alternative_seat)
                            flag=$((flag + 1))
                        fi
                    else
                        # Find any random available seat
                        random_index=$((RANDOM % ${#ALL_SEATS[@]}))
                        random_seat=${ALL_SEATS[$random_index]}
                        echo -e "${YELLOW}Trying random seat: $random_seat${NC}"
                        if reserve_seat $random_seat; then
                            booked_seats+=($random_seat)
                            flag=$((flag + 1))
                        fi
                    fi
                fi
            else
                # First seat reservation failed, try to find 2 sequential seats elsewhere
                found_sequential=false
                for i in $(seq 0 $((${#ALL_SEATS[@]} - 2))); do
                    if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ]; then
                        first_seat=${ALL_SEATS[$i]}
                        second_seat=${ALL_SEATS[$((i+1))]}
                        echo -e "${YELLOW}Trying sequential seats: $first_seat $second_seat${NC}"
                        
                        if reserve_seat $first_seat; then
                            booked_seats+=($first_seat)
                            flag=$((flag + 1))
                            
                            if reserve_seat $second_seat; then
                                booked_seats+=($second_seat)
                                flag=$((flag + 1))
                                found_sequential=true
                                break
                            fi
                        fi
                    fi
                done
                
                if [ "$found_sequential" = false ] && [ $flag -lt 2 ]; then
                    # Just try any two available seats
                    echo -e "${YELLOW}Trying any two available seats${NC}"
                    for seat in "${ALL_SEATS[@]}"; do
                        if [ $flag -eq 2 ]; then
                            break
                        fi
                        
                        if reserve_seat $seat; then
                            booked_seats+=($seat)
                            flag=$((flag + 1))
                        fi
                    done
                fi
            fi
        else
            # No continuous sequence, try to find 2 sequential seats
            found_sequential=false
            for i in $(seq 0 $((${#ALL_SEATS[@]} - 2))); do
                if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ]; then
                    first_seat=${ALL_SEATS[$i]}
                    second_seat=${ALL_SEATS[$((i+1))]}
                    echo -e "${YELLOW}No continuous sequence found. Trying sequential seats: $first_seat $second_seat${NC}"
                    
                    if reserve_seat $first_seat; then
                        booked_seats+=($first_seat)
                        flag=$((flag + 1))
                        
                        if reserve_seat $second_seat; then
                            booked_seats+=($second_seat)
                            flag=$((flag + 1))
                            found_sequential=true
                            break
                        else
                            # Try with multiple of 7
                            alternative_seat=$(find_seat_with_multiple $first_seat 7 3)
                            if [ $alternative_seat -ne -1 ]; then
                                if reserve_seat $alternative_seat; then
                                    booked_seats+=($alternative_seat)
                                    flag=$((flag + 1))
                                fi
                            fi
                        fi
                    fi
                fi
            done
            
            if [ "$found_sequential" = false ] || [ $flag -lt 2 ]; then
                # Just try any two available seats
                echo -e "${YELLOW}Trying any two available seats${NC}"
                for seat in "${ALL_SEATS[@]}"; do
                    if [ $flag -eq 2 ]; then
                        break
                    fi
                    
                    if ! [[ " ${booked_seats[@]} " =~ " ${seat} " ]]; then
                        if reserve_seat $seat; then
                            booked_seats+=($seat)
                            flag=$((flag + 1))
                        fi
                    fi
                done
            fi
        fi
        ;;
        
    3)  
        if [ "$has_five_continuous" = true ]; then
            # Get the first sequence
            seq_start=${continuous_sequences[0]}
            
            # 3rd, 4th, and 5th seats in the sequence
            third_seat=${ALL_SEATS[$((seq_start + 2))]}
            fourth_seat=${ALL_SEATS[$((seq_start + 3))]}
            fifth_seat=${ALL_SEATS[$((seq_start + 4))]}
            
            echo -e "${GREEN}Selected 3rd, 4th, and 5th seats from continuous sequence: $third_seat $fourth_seat $fifth_seat${NC}"
            
            # Try to reserve the third seat
            if reserve_seat $third_seat; then
                booked_seats+=($third_seat)
                flag=$((flag + 1))
                
                # Try to reserve the fourth and fifth seats
                if reserve_seat $fourth_seat; then
                    booked_seats+=($fourth_seat)
                    flag=$((flag + 1))
                    
                    if reserve_seat $fifth_seat; then
                        booked_seats+=($fifth_seat)
                        flag=$((flag + 1))
                    else
                        # Fifth seat not available, try k+8
                        alternative_seat=$(find_seat_with_multiple $third_seat 8 3)
                        if [ $alternative_seat -ne -1 ]; then
                            if reserve_seat $alternative_seat; then
                                booked_seats+=($alternative_seat)
                                flag=$((flag + 1))
                            fi
                        fi
                    fi
                else
                    # Fourth seat not available, try k+7 and k+8
                    alt_fourth=$(find_seat_with_multiple $third_seat 7 3)
                    if [ $alt_fourth -ne -1 ]; then
                        if reserve_seat $alt_fourth; then
                            booked_seats+=($alt_fourth)
                            flag=$((flag + 1))
                        fi
                    fi
                    
                    alt_fifth=$(find_seat_with_multiple $third_seat 8 3)
                    if [ $alt_fifth -ne -1 ]; then
                        if reserve_seat $alt_fifth; then
                            booked_seats+=($alt_fifth)
                            flag=$((flag + 1))
                        fi
                    fi
                fi
            else
                # Third seat not available, try to find 3 sequential seats
                found_sequential=false
                for i in $(seq 0 $((${#ALL_SEATS[@]} - 3))); do
                    if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ] && \
                       [ $((ALL_SEATS[i+2] - ALL_SEATS[i+1])) -eq 1 ]; then
                        seat1=${ALL_SEATS[$i]}
                        seat2=${ALL_SEATS[$((i+1))]}
                        seat3=${ALL_SEATS[$((i+2))]}
                        echo -e "${YELLOW}Trying sequential seats: $seat1 $seat2 $seat3${NC}"
                        
                        if reserve_seat $seat1 && reserve_seat $seat2 && reserve_seat $seat3; then
                            booked_seats+=($seat1 $seat2 $seat3)
                            flag=$((flag + 3))
                            found_sequential=true
                            break
                        fi
                    fi
                done
                
                if [ "$found_sequential" = false ] && [ $flag -lt 3 ]; then
                    # Just try any three available seats
                    echo -e "${YELLOW}Trying any three available seats${NC}"
                    for seat in "${ALL_SEATS[@]}"; do
                        if [ $flag -eq 3 ]; then
                            break
                        fi
                        
                        if ! [[ " ${booked_seats[@]} " =~ " ${seat} " ]]; then
                            if reserve_seat $seat; then
                                booked_seats+=($seat)
                                flag=$((flag + 1))
                            fi
                        fi
                    done
                fi
            fi
        else
            # No continuous sequence, try to find 3 sequential seats
            found_sequential=false
            for i in $(seq 0 $((${#ALL_SEATS[@]} - 3))); do
                if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ] && \
                   [ $((ALL_SEATS[i+2] - ALL_SEATS[i+1])) -eq 1 ]; then
                    seat1=${ALL_SEATS[$i]}
                    seat2=${ALL_SEATS[$((i+1))]}
                    seat3=${ALL_SEATS[$((i+2))]}
                    echo -e "${YELLOW}No continuous sequence found. Trying sequential seats: $seat1 $seat2 $seat3${NC}"
                    
                    if reserve_seat $seat1; then
                        booked_seats+=($seat1)
                        flag=$((flag + 1))
                        
                        if reserve_seat $seat2; then
                            booked_seats+=($seat2)
                            flag=$((flag + 1))
                            
                            if reserve_seat $seat3; then
                                booked_seats+=($seat3)
                                flag=$((flag + 1))
                                found_sequential=true
                                break
                            else
                                # Try alternative using multiples
                                alt_seat=$(find_seat_with_multiple $seat1 8 3)
                                if [ $alt_seat -ne -1 ]; then
                                    if reserve_seat $alt_seat; then
                                        booked_seats+=($alt_seat)
                                        flag=$((flag + 1))
                                        found_sequential=true
                                        break
                                    fi
                                fi
                            fi
                        else
                            # Try alternatives using multiples
                            alt_seat1=$(find_seat_with_multiple $seat1 7 3)
                            if [ $alt_seat1 -ne -1 ]; then
                                if reserve_seat $alt_seat1; then
                                    booked_seats+=($alt_seat1)
                                    flag=$((flag + 1))
                                fi
                            fi
                            
                            alt_seat2=$(find_seat_with_multiple $seat1 8 3)
                            if [ $alt_seat2 -ne -1 ]; then
                                if reserve_seat $alt_seat2; then
                                    booked_seats+=($alt_seat2)
                                    flag=$((flag + 1))
                                fi
                            fi
                        fi
                    fi
                fi
            done
            
            if [ "$found_sequential" = false ] || [ $flag -lt 3 ]; then
                # Just try any three available seats
                echo -e "${YELLOW}Trying any three available seats${NC}"
                for seat in "${ALL_SEATS[@]}"; do
                    if [ $flag -eq 3 ]; then
                        break
                    fi
                    
                    if ! [[ " ${booked_seats[@]} " =~ " ${seat} " ]]; then
                        if reserve_seat $seat; then
                            booked_seats+=($seat)
                            flag=$((flag + 1))
                        fi
                    fi
                done
            fi
        fi
        ;;
        
    4)  
        if [ "$has_five_continuous" = true ]; then
            # Get the first sequence
            seq_start=${continuous_sequences[0]}
            
            # 1st and 2nd seats in the sequence
            first_seat=${ALL_SEATS[$seq_start]}
            second_seat=${ALL_SEATS[$((seq_start + 1))]}
            
            # Calculate the positions for 1st+6 and 2nd+7
            first_plus_6=$((first_seat + 6))
            second_plus_7=$((second_seat + 7))
            
            echo -e "${GREEN}Target seats: $first_seat $second_seat $first_plus_6 $second_plus_7${NC}"
            
            # First try to reserve the first and second seats
            if reserve_seat $first_seat; then
                booked_seats+=($first_seat)
                flag=$((flag + 1))
                
                if reserve_seat $second_seat; then
                    booked_seats+=($second_seat)
                    flag=$((flag + 1))
                    
                    # Check if the calculated positions are available
                    first_plus_6_available=false
                    second_plus_7_available=false
                    
                    # Check if first+6 is available
                    for seat in "${ALL_SEATS[@]}"; do
                        if [ $seat -eq $first_plus_6 ]; then
                            first_plus_6_available=true
                            break
                        fi
                    done
                    
                    # Check if second+7 is available
                    for seat in "${ALL_SEATS[@]}"; do
                        if [ $seat -eq $second_plus_7 ]; then
                            second_plus_7_available=true
                            break
                        fi
                    done
                    
                    # Try to reserve 1st+6 and 2nd+7 if available
                    if [ "$first_plus_6_available" = true ]; then
                        if reserve_seat $first_plus_6; then
                            booked_seats+=($first_plus_6)
                            flag=$((flag + 1))
                        else
                            # Try multiple of 6
                            for v in {1..3}; do
                                multiple=$((first_seat + 6 * v))
                                multiple_available=false
                                for seat in "${ALL_SEATS[@]}"; do
                                    if [ $seat -eq $multiple ]; then
                                        multiple_available=true
                                        break
                                    fi
                                done
                                
                                if [ "$multiple_available" = true ]; then
                                    if reserve_seat $multiple; then
                                        booked_seats+=($multiple)
                                        flag=$((flag + 1))
                                        break
                                    fi
                                fi
                            done
                        fi
                    else
                        # Try multiple of 6
                        for v in {1..3}; do
                            multiple=$((first_seat + 6 * v))
                            multiple_available=false
                            for seat in "${ALL_SEATS[@]}"; do
                                if [ $seat -eq $multiple ]; then
                                    multiple_available=true
                                    break
                                fi
                            done
                            
                            if [ "$multiple_available" = true ]; then
                                if reserve_seat $multiple; then
                                    booked_seats+=($multiple)
                                    flag=$((flag + 1))
                                    break
                                fi
                            fi
                        done
                    fi
                    
                    if [ "$second_plus_7_available" = true ]; then
                        if reserve_seat $second_plus_7; then
                            booked_seats+=($second_plus_7)
                            flag=$((flag + 1))
                        else
                            # Try multiple of 7
                            for v in {1..3}; do
                                multiple=$((second_seat + 7 * v))
                                multiple_available=false
                                for seat in "${ALL_SEATS[@]}"; do
                                    if [ $seat -eq $multiple ]; then
                                        multiple_available=true
                                        break
                                    fi
                                done
                                
                                if [ "$multiple_available" = true ]; then
                                    if reserve_seat $multiple; then
                                        booked_seats+=($multiple)
                                        flag=$((flag + 1))
                                        break
                                    fi
                                fi
                            done
                        fi
                    else
                        # Try multiple of 7
                        for v in {1..3}; do
                            multiple=$((second_seat + 7 * v))
                            multiple_available=false
                            for seat in "${ALL_SEATS[@]}"; do
                                if [ $seat -eq $multiple ]; then
                                    multiple_available=true
                                    break
                                fi
                            done
                            
                            if [ "$multiple_available" = true ]; then
                                if reserve_seat $multiple; then
                                    booked_seats+=($multiple)
                                    flag=$((flag + 1))
                                    break
                                fi
                            fi
                        done
                    fi
                fi
            fi
            
            # If the above strategy didn't work, try to find 2 pairs of sequential seats
            if [ $flag -lt 4 ]; then
                echo -e "${YELLOW}Primary strategy failed, trying to find 2 pairs of sequential seats${NC}"
                # Reset booked seats
                for seat in "${booked_seats[@]}"; do
                    echo -e "${YELLOW}Releasing previously booked seat: $seat${NC}"
                    # Here you would add API call to release the seat if needed
                done
                booked_seats=()
                flag=0
                
                # Find pairs with difference less than 40
                for i in $(seq 0 $((${#ALL_SEATS[@]} - 2))); do
                    if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ]; then
                        first_pair_start=$i
                        first_pair_end=$((i+1))
                        
                        # Try to find a second pair
                        for j in $(seq $((i+2)) $((${#ALL_SEATS[@]} - 2))); do
                            if [ $((ALL_SEATS[j+1] - ALL_SEATS[j])) -eq 1 ] && \
                               [ $((ALL_SEATS[j] - ALL_SEATS[first_pair_start])) -lt 40 ]; then
                                second_pair_start=$j
                                second_pair_end=$((j+1))
                                
                                # Try to reserve these 4 seats
                                seat1=${ALL_SEATS[$first_pair_start]}
                                seat2=${ALL_SEATS[$first_pair_end]}
                                seat3=${ALL_SEATS[$second_pair_start]}
                                seat4=${ALL_SEATS[$second_pair_end]}
                                
                                echo -e "${YELLOW}Trying two pairs: $seat1,$seat2 and $seat3,$seat4${NC}"
                                
                                if reserve_seat $seat1 && reserve_seat $seat2 && \
                                   reserve_seat $seat3 && reserve_seat $seat4; then
                                    booked_seats+=($seat1 $seat2 $seat3 $seat4)
                                    flag=4
                                    break 2
                                fi
                            fi
                        done
                    fi
                done
                
                # If still not all seats are booked, try any 4 seats within a range of 40
                if [ $flag -lt 4 ]; then
                    echo -e "${YELLOW}Pair strategy failed, trying any 4 seats within a range of 40${NC}"
                    # Reset booked seats
                    booked_seats=()
                    flag=0
                    
                    # Try windows of 40 seats
                    for i in $(seq 0 $((${#ALL_SEATS[@]} - 4))); do
                        if [ $((ALL_SEATS[i+3] - ALL_SEATS[i])) -lt 40 ]; then
                            # Try to book 4 seats in this window
                            seat1=${ALL_SEATS[$i]}
                            seat2=${ALL_SEATS[$i+1]}
                            seat3=${ALL_SEATS[$i+2]}
                            seat4=${ALL_SEATS[$i+3]}
                            
                            echo -e "${YELLOW}Trying 4 seats within range 40: $seat1,$seat2,$seat3,$seat4${NC}"
                            
                            if reserve_seat $seat1 && reserve_seat $seat2 && \
                               reserve_seat $seat3 && reserve_seat $seat4; then
                                booked_seats+=($seat1 $seat2 $seat3 $seat4)
                                flag=4
                                break
                            fi
                        fi
                    done
                fi
                
                # Last resort: just try any 4 available seats
                if [ $flag -lt 4 ]; then
                    echo -e "${YELLOW}Range strategy failed, trying any 4 available seats${NC}"
                    # Reset booked seats
                    booked_seats=()
                    flag=0
                    
                    for seat in "${ALL_SEATS[@]}"; do
                        if [ $flag -eq 4 ]; then
                            break
                        fi
                        
                        if ! [[ " ${booked_seats[@]} " =~ " ${seat} " ]]; then
                            if reserve_seat $seat; then
                                booked_seats+=($seat)
                                flag=$((flag + 1))
                            fi
                        fi
                    done
                fi
            fi
        else
            # No continuous sequence, try to find 2 pairs of sequential seats with difference < 40
            echo -e "${YELLOW}No continuous sequence found, looking for 2 pairs of sequential seats${NC}"
            
            for i in $(seq 0 $((${#ALL_SEATS[@]} - 2))); do
                if [ $((ALL_SEATS[i+1] - ALL_SEATS[i])) -eq 1 ]; then
                    first_pair_start=$i
                    first_pair_end=$((i+1))
                    
                    # Try to find a second pair
                    for j in $(seq $((i+2)) $((${#ALL_SEATS[@]} - 2))); do
                        if [ $((ALL_SEATS[j+1] - ALL_SEATS[j])) -eq 1 ] && \
                           [ $((ALL_SEATS[j] - ALL_SEATS[first_pair_start])) -lt 40 ]; then
                            second_pair_start=$j
                            second_pair_end=$((j+1))
                            
                            # Try to reserve these 4 seats
                            seat1=${ALL_SEATS[$first_pair_start]}
                            seat2=${ALL_SEATS[$first_pair_end]}
                            seat3=${ALL_SEATS[$second_pair_start]}
                            seat4=${ALL_SEATS[$second_pair_end]}
                            
                            echo -e "${YELLOW}Trying two pairs: $seat1,$seat2 and $seat3,$seat4${NC}"
                            
                            if reserve_seat $seat1 && reserve_seat $seat2 && \
                               reserve_seat $seat3 && reserve_seat $seat4; then
                                booked_seats+=($seat1 $seat2 $seat3 $seat4)
                                flag=4
                                break 2
                            fi
                        fi
                    done
                fi
            done
            
            # If still not all seats are booked, try any 4 seats within a range of 40
            if [ $flag -lt 4 ]; then
                echo -e "${YELLOW}Pair strategy failed, trying any 4 seats within a range of 40${NC}"
                # Reset booked seats
                booked_seats=()
                flag=0
                
                # Try windows of 40 seats
                for i in $(seq 0 $((${#ALL_SEATS[@]} - 4))); do
                    if [ $((ALL_SEATS[i+3] - ALL_SEATS[i])) -lt 40 ]; then
                        # Try to book 4 seats in this window
                        seat1=${ALL_SEATS[$i]}
                        seat2=${ALL_SEATS[$i+1]}
                        seat3=${ALL_SEATS[$i+2]}
                        seat4=${ALL_SEATS[$i+3]}
                        
                        echo -e "${YELLOW}Trying 4 seats within range 40: $seat1,$seat2,$seat3,$seat4${NC}"
                        
                        if reserve_seat $seat1 && reserve_seat $seat2 && \
                           reserve_seat $seat3 && reserve_seat $seat4; then
                            booked_seats+=($seat1 $seat2 $seat3 $seat4)
                            flag=4
                            break
                        fi
                    fi
                done
            fi
            
            # Last resort: just try any 4 available seats
            if [ $flag -lt 4 ]; then
                echo -e "${YELLOW}Range strategy failed, trying any 4 available seats${NC}"
                # Reset booked seats
                booked_seats=()
                flag=0
                
                for seat in "${ALL_SEATS[@]}"; do
                    if [ $flag -eq 4 ]; then
                        break
                    fi
                    
                    if ! [[ " ${booked_seats[@]} " =~ " ${seat} " ]]; then
                        if reserve_seat $seat; then
                            booked_seats+=($seat)
                            flag=$((flag + 1))
                        fi
                    fi
                done
            fi
        fi
        ;;
esac

# Check if we reserved enough seats
if [ $flag -lt $numberOfSeat ]; then
    echo -e "${RED}Warning: Only reserved $flag seats out of $numberOfSeat requested${NC}"
fi

# Create the output file with the reserved seats
mkdir -p $(dirname "$OUTPUT_FILE")

# Check if we have any booked seats before creating output
if [ ${#booked_seats[@]} -eq 0 ]; then
    echo -e "${RED}No seats were successfully reserved${NC}"
    echo '{"trip_id": 0, "trip_route_id": 0, "ticket_ids": []}' > "$OUTPUT_FILE"
else
    # Generate the JSON output
    cat > "$OUTPUT_FILE" << EOF
{
  "trip_id": $TRIP_ID,
  "trip_route_id": $TRIP_ROUTE_ID,
  "ticket_ids": [
$(for i in "${!booked_seats[@]}"; do
    if [ $i -eq $(( ${#booked_seats[@]} - 1 )) ]; then
        echo "    ${booked_seats[$i]}"
    else
        echo "    ${booked_seats[$i]},"
    fi
done)
  ]
}
EOF
fi

echo -e "${GREEN}Results saved to $OUTPUT_FILE${NC}"
cat "$OUTPUT_FILE"

exit 0