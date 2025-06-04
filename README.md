
# Project Automation

This project automates the journey booking process using shell scripts. Follow the instructions below to set up and run the automation.

## Setup Instructions

### 1. Install `jq` on Linux
To parse and work with JSON data, you'll need to install `jq`. Run the following command:

```bash
sudo apt update
sudo apt install jq
```

### 2. Modify `journey-info.txt` with Journey Details
Edit the `/files/journey-info.txt` file to include journey information. Example format:


### 3. Set Execute Permissions for the Script
Make sure the `automate.sh` script is executable. Run the following command to set the necessary permissions:

```bash
chmod +x automate.sh
```

### 4. Run the Automation Script
After modifying the `journey-info.txt` file, run the automation script using the following command:

```bash
bash automate.sh -f
```

This will trigger the automation process using the updated journey details.
