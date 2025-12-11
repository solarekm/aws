#!/bin/bash
##
## ECR Repository Scanner (Bash version)
## Lists all ECR repositories and checks if 'scan on push' is enabled.
##

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default profile
PROFILE=""

# Function to display usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

List all ECR repositories and check if scan on push is enabled.

OPTIONS:
    -p, --profile PROFILE    AWS profile name to use
    -h, --help              Display this help message

EXAMPLES:
    $0
    $0 --profile service42.dev.admin
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--profile)
            PROFILE="$2"
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

# Build AWS CLI command with profile if specified
AWS_CMD="aws ecr describe-repositories"
if [[ -n "$PROFILE" ]]; then
    AWS_CMD="$AWS_CMD --profile $PROFILE"
fi

echo "Fetching ECR repositories..."

# Fetch repositories
REPOS_JSON=$($AWS_CMD --output json 2>/dev/null) || {
    echo -e "${RED}Error: Failed to fetch ECR repositories. Check your AWS credentials.${NC}" >&2
    exit 1
}

# Count repositories
REPO_COUNT=$(echo "$REPOS_JSON" | jq -r '.repositories | length')

if [[ "$REPO_COUNT" -eq 0 ]]; then
    echo -e "\n${YELLOW}No ECR repositories found.${NC}"
    exit 0
fi

echo -e "\nFound ${BOLD}$REPO_COUNT${NC} repository(ies):\n"

# Print table header
printf "${BOLD}%-40s %-20s %-80s %-20s${NC}\n" "Repository Name" "Scan on Push" "Repository URI" "Created At"
printf "%-40s %-20s %-80s %-20s\n" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..20})" "$(printf '%.0s-' {1..80})" "$(printf '%.0s-' {1..20})"

# Initialize counters
ENABLED_COUNT=0
DISABLED_COUNT=0

# Parse and display repository information
echo "$REPOS_JSON" | jq -r '.repositories[] | 
    [
        .repositoryName,
        (.imageScanningConfiguration.scanOnPush // false),
        .repositoryUri,
        .createdAt
    ] | @tsv' | while IFS=$'\t' read -r name scan_on_push uri created; do
    
    # Format scan on push status
    if [[ "$scan_on_push" == "true" ]]; then
        SCAN_STATUS="${GREEN}✓ Enabled${NC}"
        ((ENABLED_COUNT++)) || true
    else
        SCAN_STATUS="${RED}✗ Disabled${NC}"
        ((DISABLED_COUNT++)) || true
    fi
    
    # Format date (extract date part)
    CREATED_DATE=$(echo "$created" | cut -d'T' -f1)
    CREATED_TIME=$(echo "$created" | cut -d'T' -f2 | cut -d'.' -f1)
    FORMATTED_DATE="$CREATED_DATE $CREATED_TIME"
    
    # Print row
    printf "%-40s %-31s %-80s %-20s\n" \
        "${name:0:40}" \
        "$(echo -e "$SCAN_STATUS")" \
        "${uri:0:80}" \
        "$FORMATTED_DATE"
done

# Calculate summary (re-parse to count)
ENABLED_COUNT=$(echo "$REPOS_JSON" | jq -r '[.repositories[] | select(.imageScanningConfiguration.scanOnPush == true)] | length')
DISABLED_COUNT=$((REPO_COUNT - ENABLED_COUNT))

# Print summary
echo ""
printf "%.0s=" {1..150}
echo ""
echo -e "${BOLD}Summary:${NC}"
echo "  Total repositories: $REPO_COUNT"
echo -e "  Scan on push enabled: ${GREEN}$ENABLED_COUNT${NC}"
echo -e "  Scan on push disabled: ${RED}$DISABLED_COUNT${NC}"
printf "%.0s=" {1..150}
echo ""
