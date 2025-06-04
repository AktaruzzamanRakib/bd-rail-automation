#!/bin/bash

# =============== 1. LOG-IN TO THE APPLICATION =================


# Colors for better output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Get credentials from journey-info.txt file
JOURNEY_INFO_FILE="files/journey-info.txt"
MOBILE=""
PASSWORD=""

# Try to read credentials from file first
if [ -f "$JOURNEY_INFO_FILE" ]; then
    # Try to parse the file as JSON first
    if command -v jq &> /dev/null && grep -q "^{" "$JOURNEY_INFO_FILE"; then
        echo -e "${GREEN}Reading credentials from JSON file...${NC}"
        MOBILE=$(jq -r '.username // empty' "$JOURNEY_INFO_FILE")
        PASSWORD=$(jq -r '.password // empty' "$JOURNEY_INFO_FILE")
    else
        # Try different formats (key=value and key:value)
        echo -e "${GREEN}Reading credentials from key-value file...${NC}"
        MOBILE=$(grep "^username=" "$JOURNEY_INFO_FILE" | cut -d'=' -f2 | tr -d ' ' || \
                grep -E "^username[[:space:]]*:" "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d '[:space:]')
        PASSWORD=$(grep "^password=" "$JOURNEY_INFO_FILE" | cut -d'=' -f2 | tr -d ' ' || \
                  grep -E "^password[[:space:]]*:" "$JOURNEY_INFO_FILE" | cut -d':' -f2 | tr -d '[:space:]')
    fi
    
    # Check if we got the credentials
    if [ -n "$MOBILE" ] && [ -n "$PASSWORD" ]; then
        echo -e "${GREEN}Successfully loaded credentials from $JOURNEY_INFO_FILE${NC}"
    else
        echo -e "${YELLOW}Warning: Could not find username or password in $JOURNEY_INFO_FILE.${NC}"
    fi
else
    echo -e "${YELLOW}Warning: Could not find $JOURNEY_INFO_FILE.${NC}"
fi

# Configuration
CONFIG_DIR="files/token"
TOKEN_FILE="$CONFIG_DIR/token.txt"
SESSION_FILE="$CONFIG_DIR/session.json"

# Function to check if dependencies are installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: 'jq' is not installed. Please install it using:${NC}"
        echo -e "${YELLOW}sudo apt-get install jq${NC}"
        exit 1
    fi
}

# Function to display usage
show_usage() {
    echo -e "${YELLOW}Usage:${NC} $0 [options]"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  -m, --mobile NUMBER   ${GREEN}Mobile number${NC}"
    echo -e "  -p, --password PASS   ${GREEN}Password${NC}"
    echo -e "  -f, --force           ${GREEN}Force new login even if existing token is present${NC}"
    echo -e "  -h, --help            ${GREEN}Show this help message${NC}"
    echo -e "\n${YELLOW}Example:${NC} $0 --mobile 01712345678 --password myPassword123"
}

# Function to create config directory if it doesn't exist
create_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        chmod 700 "$CONFIG_DIR"  # Set permissions to ensure only the user can access
        echo -e "${YELLOW}Created configuration directory: $CONFIG_DIR${NC}"
    fi
}

# Parse command-line arguments
FORCE_LOGIN=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m|--mobile) MOBILE="$2"; shift ;;
        -p|--password) PASSWORD="$2"; shift ;;
        -f|--force) FORCE_LOGIN=true ;;
        -h|--help) show_usage; exit 0 ;;
        *) echo -e "${RED}Unknown parameter: $1${NC}"; show_usage; exit 1 ;;
    esac
    shift
done

# Check if we have credentials
if [ -z "$MOBILE" ] || [ -z "$PASSWORD" ]; then
    echo -e "${RED}Error: Mobile number and password are required.${NC}"
    echo -e "${YELLOW}Please either:${NC}"
    echo -e "  1. Provide them in $JOURNEY_INFO_FILE file"
    echo -e "  2. Pass them as command-line arguments (-m and -p)"
    show_usage
    exit 1
fi

# Check dependencies
check_dependencies

# Create config directory
create_config_dir

# Check if we already have a valid token
if [ -f "$TOKEN_FILE" ] && [ "$FORCE_LOGIN" = false ]; then
    # Get token expiry timestamp from the session file
    if [ -f "$SESSION_FILE" ]; then
        EXPIRES_AT=$(jq -r '.expires_at // 0' "$SESSION_FILE")
        CURRENT_TIME=$(date +%s)
        
        if [ "$EXPIRES_AT" -gt "$CURRENT_TIME" ]; then
            echo -e "${GREEN}Using existing token (valid until $(date -d @$EXPIRES_AT))${NC}"
            TOKEN=$(cat "$TOKEN_FILE")
            echo "$TOKEN"
            exit 0
        else
            echo -e "${YELLOW}Existing token has expired. Requesting new token...${NC}"
        fi
    fi
fi

echo -e "${BLUE}=====================================${NC}"
echo -e "${CYAN}🔐 BD RAILWAY LOGIN PROCESS 🔐${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "${YELLOW}Mobile Number:${NC} $MOBILE"
echo -e "${YELLOW}Attempting to log in...${NC}"
echo

# Make login request
response=$(curl --silent --location --request POST "https://railspaapi.shohoz.com/v1.0/web/auth/sign-in?mobile_number=$MOBILE&password=$PASSWORD")

# Check if curl request was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to connect to the API server${NC}"
    exit 1
fi

# Check if response contains error
if [[ $response == *"error"* ]] || [[ $response == *"invalid"* ]]; then
    echo -e "${RED}Error: Login failed${NC}"
    echo "$response" | jq '.'
    exit 1
fi

# Save full response for debugging
echo "$response" > "$SESSION_FILE"

# Extract the token
TOKEN=$(echo "$response" | jq -r '.data.token')

# Check if token was successfully extracted
if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo -e "${RED}Error: Couldn't extract token from response${NC}"
    echo -e "${YELLOW}Response:${NC}"
    echo "$response" | jq '.'
    exit 1
fi

# Extract expiry timestamp if available
EXPIRES_AT=$(echo "$response" | jq -r '.data.expires_at // .data.token_expiry // empty')
if [ -z "$EXPIRES_AT" ]; then
    # If expiry isn't directly provided, set it to 24 hours from now
    EXPIRES_AT=$(($(date +%s) + 86400))
    echo "$response" | jq --arg exp "$EXPIRES_AT" '. += {"expires_at": $exp|tonumber}' > "$SESSION_FILE"
fi

# Save the token to file
echo "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"  # Set permissions to ensure only the user can read

echo -e "${GREEN}Login successful! Token saved.${NC}"
echo -e "${BLUE}=====================================${NC}"