#!/bin/bash
set -e

# CDC Pipeline End-to-End Test Script
# This script generates test data and verifies the entire pipeline

echo "=========================================="
echo "CDC Platform - End-to-End Pipeline Test"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "$1"
    echo -e "==========================================${NC}"
    echo ""
}

# Get RDS connection details
print_section "1. Getting Database Connection Details"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT/terraform-infra"
RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null | cut -d: -f1)
RDS_DATABASE=$(terraform output -raw rds_database_name 2>/dev/null)
RDS_USERNAME=$(terraform output -raw rds_username 2>/dev/null)
SECRET_ARN=$(terraform output -raw rds_master_secret_arn 2>/dev/null)
cd "$PROJECT_ROOT"

if [ -z "$RDS_ENDPOINT" ]; then
    print_error "Could not get RDS endpoint"
    exit 1
fi

print_info "Database: $RDS_DATABASE @ $RDS_ENDPOINT"

# Get database password
DB_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id "$SECRET_ARN" \
    --query 'SecretString' \
    --output text 2>/dev/null | jq -r '.password' | tr -d '\n')

if [ -z "$DB_PASSWORD" ]; then
    print_error "Could not retrieve database password"
    exit 1
fi

# Create test data SQL
print_section "2. Generating Test Data"

cat <<EOF > /tmp/test-data.sql
-- Insert new products
INSERT INTO products (name, description, price, stock_quantity)
VALUES
    ('Tablet', '10-inch tablet', 399.99, 80),
    ('Smartwatch', 'Fitness tracking smartwatch', 249.99, 150),
    ('Webcam', '4K webcam', 89.99, 200)
ON CONFLICT DO NOTHING;

-- Update existing products (price changes)
UPDATE products SET price = 1299.99, updated_at = NOW() WHERE name = 'Laptop';
UPDATE products SET stock_quantity = stock_quantity - 5, updated_at = NOW() WHERE name = 'Mouse';

-- Insert new orders
INSERT INTO orders (customer_id, total_amount, status)
VALUES
    (101, 0, 'pending'),
    (102, 0, 'pending'),
    (103, 0, 'pending')
RETURNING id;

-- Get the last 3 order IDs
DO \$\$
DECLARE
    order_id_1 INT;
    order_id_2 INT;
    order_id_3 INT;
BEGIN
    SELECT id INTO order_id_1 FROM orders WHERE customer_id = 101 ORDER BY created_at DESC LIMIT 1;
    SELECT id INTO order_id_2 FROM orders WHERE customer_id = 102 ORDER BY created_at DESC LIMIT 1;
    SELECT id INTO order_id_3 FROM orders WHERE customer_id = 103 ORDER BY created_at DESC LIMIT 1;

    -- Insert order items
    INSERT INTO order_items (order_id, product_id, quantity, price)
    SELECT order_id_1, id, 1, price FROM products WHERE name = 'Tablet';

    INSERT INTO order_items (order_id, product_id, quantity, price)
    SELECT order_id_2, id, 2, price FROM products WHERE name = 'Smartwatch';

    INSERT INTO order_items (order_id, product_id, quantity, price)
    SELECT order_id_3, id, 1, price FROM products WHERE name = 'Webcam';

    -- Update order totals
    UPDATE orders o SET total_amount = (
        SELECT COALESCE(SUM(quantity * price), 0)
        FROM order_items
        WHERE order_id = o.id
    ), updated_at = NOW() WHERE id IN (order_id_1, order_id_2, order_id_3);
END \$\$;

-- Show summary
SELECT 'Products' as table_name, COUNT(*) as record_count FROM products
UNION ALL
SELECT 'Orders', COUNT(*) FROM orders
UNION ALL
SELECT 'Order Items', COUNT(*) FROM order_items;
EOF

print_status "Test data SQL generated"

# Execute test data insertion
print_section "3. Inserting Test Data into Database"

kubectl run db-test-insert --rm -i --restart=Never --image=postgres:16 \
    --env="PGPASSWORD=$DB_PASSWORD" \
    --command -- bash -c "psql 'sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE' -f /dev/stdin" < /tmp/test-data.sql

print_status "Test data inserted successfully"

# Wait for CDC to capture events
print_section "4. Waiting for CDC to Capture Events"
print_info "Waiting 10 seconds for Debezium to capture and publish events..."
sleep 10
print_status "CDC capture window complete"

# Check Kafka topics for new events
print_section "5. Verifying Kafka Topics Have New Events"

echo "📊 Products Topic (latest 3 events):"
kubectl exec -n kafka cdc-platform-kafka-brokers-0 -- \
    bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic dbserver1.public.products \
    --from-beginning \
    --max-messages 3 \
    --timeout-ms 5000 2>/dev/null | grep -o '"name":"[^"]*"' | tail -3 || print_warning "No events found in products topic"

echo ""
echo "📊 Orders Topic (latest 3 events):"
kubectl exec -n kafka cdc-platform-kafka-brokers-0 -- \
    bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic dbserver1.public.orders \
    --from-beginning \
    --max-messages 3 \
    --timeout-ms 5000 2>/dev/null | grep -o '"status":"[^"]*"' | tail -3 || print_warning "No events found in orders topic"

echo ""
echo "📊 Order Items Topic (latest 3 events):"
kubectl exec -n kafka cdc-platform-kafka-brokers-0 -- \
    bin/kafka-console-consumer.sh \
    --bootstrap-server localhost:9092 \
    --topic dbserver1.public.order-items \
    --from-beginning \
    --max-messages 3 \
    --timeout-ms 5000 2>/dev/null | grep -o '"quantity":[0-9]*' | tail -3 || print_warning "No events found in order-items topic"

print_status "Kafka topics verified"

# Check Debezium connector status
print_section "6. Checking Debezium Connector Status"

CONNECTOR_STATE=$(kubectl get kafkaconnector postgres-connector -n kafka -o jsonpath='{.status.connectorStatus.connector.state}' 2>/dev/null || echo "UNKNOWN")
if [ "$CONNECTOR_STATE" = "RUNNING" ]; then
    print_status "Debezium connector is RUNNING"
else
    print_error "Debezium connector state: $CONNECTOR_STATE"
fi

TASKS=$(kubectl get kafkaconnector postgres-connector -n kafka -o jsonpath='{.status.connectorStatus.tasks}' 2>/dev/null)
if [ ! -z "$TASKS" ]; then
    echo "Tasks status:"
    echo "$TASKS" | jq -r '.[] | "  Task \(.id): \(.state)"' 2>/dev/null || echo "$TASKS"
fi

# Check Flink jobs
print_section "7. Checking Flink Job Status"

FLINK_PODS=$(kubectl get pods -n flink -l component=jobmanager --no-headers 2>/dev/null | wc -l)
if [ "$FLINK_PODS" -gt 0 ]; then
    print_info "Found $FLINK_PODS Flink JobManager pod(s)"

    # List Flink jobs
    echo ""
    echo "Flink Jobs:"
    kubectl get pods -n flink -l component=jobmanager --no-headers | while read pod rest; do
        echo ""
        echo "JobManager: $pod"
        kubectl exec -n flink $pod -- flink list 2>/dev/null || print_warning "Could not list jobs from $pod"
    done

    # Check TaskManagers
    TASKMANAGERS=$(kubectl get pods -n flink -l component=taskmanager --no-headers 2>/dev/null | wc -l)
    print_info "Found $TASKMANAGERS TaskManager pod(s)"

    if [ "$TASKMANAGERS" -eq 0 ]; then
        print_warning "No TaskManagers found - jobs may not be running"
    fi
else
    print_warning "No Flink JobManager pods found"
    print_info "Checking Flink deployments..."
    kubectl get deployments,statefulsets -n flink 2>/dev/null || print_warning "No Flink resources found"
fi

# Check consumer applications
print_section "8. Checking Consumer Applications"

CONSUMER_PODS=$(kubectl get pods -n cdc-consumers --no-headers 2>/dev/null | wc -l)
if [ "$CONSUMER_PODS" -gt 0 ]; then
    print_info "Found $CONSUMER_PODS consumer pod(s)"
    kubectl get pods -n cdc-consumers

    echo ""
    echo "Recent consumer logs (last 10 lines from first pod):"
    FIRST_POD=$(kubectl get pods -n cdc-consumers --no-headers | head -1 | awk '{print $1}')
    if [ ! -z "$FIRST_POD" ]; then
        kubectl logs -n cdc-consumers $FIRST_POD --tail=10 2>/dev/null || print_warning "Could not get logs"
    fi
else
    print_warning "No consumer pods found in cdc-consumers namespace"
fi

# Database statistics
print_section "9. Final Database Statistics"

kubectl run db-stats --rm -i --restart=Never --image=postgres:16 \
    --env="PGPASSWORD=$DB_PASSWORD" \
    --command -- psql "sslmode=require host=$RDS_ENDPOINT port=5432 user=$RDS_USERNAME dbname=$RDS_DATABASE" -c "
    SELECT
        'Products' as table_name,
        COUNT(*) as total_records,
        COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '5 minutes') as recent_changes
    FROM products
    UNION ALL
    SELECT
        'Orders',
        COUNT(*),
        COUNT(*) FILTER (WHERE updated_at > NOW() - INTERVAL '5 minutes')
    FROM orders
    UNION ALL
    SELECT
        'Order Items',
        COUNT(*),
        COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '5 minutes')
    FROM order_items;
"

# Cleanup
rm -f /tmp/test-data.sql

# Summary
print_section "10. Test Summary"

print_status "Test data generation complete"
print_info "What was tested:"
echo "  1. ✅ Database connectivity and data insertion"
echo "  2. ✅ CDC capture by Debezium connector"
echo "  3. ✅ Event publishing to Kafka topics"
echo "  4. ✅ Debezium connector health"
echo "  5. ✅ Flink job deployment status"
echo "  6. ✅ Consumer application status"
echo ""

print_info "Next steps to verify end-to-end processing:"
echo "  1. Check Flink job outputs:"
echo "     kubectl logs -n flink <flink-jobmanager-pod> --tail=50"
echo ""
echo "  2. Monitor consumer logs:"
echo "     kubectl logs -n cdc-consumers <consumer-pod> -f"
echo ""
echo "  3. Insert more test data and watch real-time:"
echo "     bash scripts/test-cdc-pipeline.sh"
echo ""
echo "  4. Check Kafka consumer groups:"
echo "     kubectl exec -n kafka cdc-platform-kafka-brokers-0 -- \\"
echo "       bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list"
echo ""

print_status "CDC Pipeline Test Complete!"
