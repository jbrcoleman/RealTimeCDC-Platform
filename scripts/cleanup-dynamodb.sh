#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DynamoDB Tables Cleanup${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get AWS configuration
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION=${AWS_REGION:-us-east-1}

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Could not get AWS Account ID${NC}"
    echo "Please configure AWS CLI: aws configure"
    exit 1
fi

echo -e "${YELLOW}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${YELLOW}AWS Region:${NC} $AWS_REGION"
echo ""

# List all tables with cdc-platform prefix
echo -e "${YELLOW}Searching for DynamoDB tables with 'cdc-platform-' prefix...${NC}"
TABLES=$(aws dynamodb list-tables --region $AWS_REGION --query "TableNames[?starts_with(@, 'cdc-platform-')]" --output text 2>/dev/null)

if [ -z "$TABLES" ]; then
    echo -e "${YELLOW}No DynamoDB tables found with 'cdc-platform-' prefix${NC}"
    exit 0
fi

# Display tables found
echo ""
echo -e "${YELLOW}Found the following tables:${NC}"
for table in $TABLES; do
    # Get table info
    ITEM_COUNT=$(aws dynamodb describe-table --table-name $table --region $AWS_REGION --query 'Table.ItemCount' --output text 2>/dev/null || echo "unknown")
    SIZE=$(aws dynamodb describe-table --table-name $table --region $AWS_REGION --query 'Table.TableSizeBytes' --output text 2>/dev/null || echo "unknown")

    if [ "$SIZE" != "unknown" ] && [ "$SIZE" -gt 0 ]; then
        SIZE_MB=$((SIZE / 1024 / 1024))
        echo "  - $table (Items: $ITEM_COUNT, Size: ${SIZE_MB}MB)"
    else
        echo "  - $table (Items: $ITEM_COUNT)"
    fi
done

# Confirmation
echo ""
echo -e "${RED}⚠️  WARNING: This will permanently delete all data in these tables!${NC}"
read -p "Do you want to delete these tables? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

# Delete tables
echo ""
echo -e "${YELLOW}Deleting DynamoDB tables...${NC}"
for table in $TABLES; do
    echo "Deleting: $table"
    aws dynamodb delete-table --table-name $table --region $AWS_REGION 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $table deletion initiated${NC}"
    else
        echo -e "${RED}✗ Failed to delete $table${NC}"
    fi
done

echo ""
echo -e "${YELLOW}Note:${NC} DynamoDB table deletion is asynchronous."
echo "Tables will be fully deleted within a few minutes."
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To verify deletion, run:"
echo "  aws dynamodb list-tables --region $AWS_REGION"
echo ""
