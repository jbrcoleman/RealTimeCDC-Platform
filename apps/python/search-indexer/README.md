# Search Indexer Service

Real-time search index updater that consumes product CDC events and maintains a searchable product catalog in DynamoDB.

## Features

- **Real-time Indexing**: Updates search index immediately when products change
- **Full-text Search**: Tokenizes product names and descriptions
- **Multiple Search Methods**: Search by name, price range, or tokens
- **DynamoDB GSI**: Global Secondary Indexes for efficient queries
- **Automatic Cleanup**: Removes deleted products from index

## Search Index Schema

### DynamoDB Table: `product-search-index`

**Primary Key**: `product_id` (Number)

**Global Secondary Indexes**:
1. `name-index`: Partition key on `name_lower` for name lookups
2. `price-index`: Partition key on `price` for price-based filtering

**Item Structure**:
```json
{
  "product_id": 123,
  "name": "Laptop",
  "name_lower": "laptop",
  "description": "High-performance laptop",
  "price": 129999,
  "price_display": "$1299.99",
  "stock_quantity": 50,
  "search_tokens": ["laptop", "high", "performance"],
  "indexed_at": "2025-01-15T10:30:00",
  "cdc_timestamp": "2025-01-15T09:25:00"
}
```

## Search Capabilities

### 1. Search by Product ID
```python
table.get_item(Key={'product_id': 123})
```

### 2. Search by Name
```python
table.query(
    IndexName='name-index',
    KeyConditionExpression=Key('name_lower').eq('laptop')
)
```

### 3. Search by Price
```python
table.query(
    IndexName='price-index',
    KeyConditionExpression=Key('price').eq(129999)
)
```

### 4. Full-text Search (Client-side)
```python
# Scan and filter by tokens
response = table.scan(
    FilterExpression=Attr('search_tokens').contains('wireless')
)
```

## Text Tokenization

The service tokenizes product names and descriptions:
- Converts to lowercase
- Splits on non-alphanumeric characters
- Removes duplicates
- Stores as `search_tokens` array

**Example**:
- Input: "High-Performance Wireless Mouse"
- Tokens: ["high", "performance", "wireless", "mouse"]

## CDC Event Processing

### CREATE/UPDATE Operations
1. Parse product data from CDC event
2. Tokenize name and description
3. Build search document
4. Upsert to DynamoDB (PUT operation)

### DELETE Operations
1. Extract product_id from before image
2. Delete from DynamoDB index

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka broker addresses | `cdc-platform-kafka-bootstrap.kafka.svc.cluster.local:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `search-indexer-group` |
| `KAFKA_TOPIC` | Product events topic | `dbserver1.public.products` |
| `DYNAMODB_TABLE` | Search index table name | `product-search-index` |
| `AWS_REGION` | AWS region | `us-east-1` |

## AWS Permissions Required

The service account needs these IAM permissions (provided via EKS Pod Identity):

- `dynamodb:CreateTable`
- `dynamodb:DescribeTable`
- `dynamodb:PutItem`
- `dynamodb:DeleteItem`
- `dynamodb:Query`
- `dynamodb:Scan`

## Query Patterns

### Product Catalog API
You can build a REST API on top of this index:

```python
from fastapi import FastAPI, Query
from boto3.dynamodb.conditions import Key, Attr

app = FastAPI()

@app.get("/search")
def search_products(q: str = Query(...)):
    """Full-text search across products"""
    response = table.scan(
        FilterExpression=Attr('search_tokens').contains(q.lower())
    )
    return response['Items']

@app.get("/products/{product_id}")
def get_product(product_id: int):
    """Get product by ID"""
    response = table.get_item(Key={'product_id': product_id})
    return response.get('Item')

@app.get("/products/name/{name}")
def search_by_name(name: str):
    """Search by exact name match"""
    response = table.query(
        IndexName='name-index',
        KeyConditionExpression=Key('name_lower').eq(name.lower())
    )
    return response['Items']
```

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export KAFKA_BOOTSTRAP_SERVERS=localhost:9092
export AWS_REGION=us-east-1
export DYNAMODB_TABLE=product-search-index-dev

# Run
python app.py
```

## Build Docker Image

```bash
docker build -t search-indexer:latest .
docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  -e AWS_REGION=us-east-1 \
  search-indexer:latest
```

## Kubernetes Deployment

See `k8s/consumers/search-indexer/` for deployment manifests.

## Performance Considerations

### Scalability
- **Horizontal Scaling**: Run multiple instances in same consumer group
- **DynamoDB**: Pay-per-request billing scales automatically
- **GSI**: Queries are efficient with proper key design

### Cost Optimization
- Use on-demand billing for variable workloads
- Consider provisioned capacity for predictable traffic
- Monitor GSI write capacity consumption

## Monitoring

Key metrics to track:
- Index latency (time from CDC event to DynamoDB write)
- Indexing errors
- DynamoDB throttling
- Consumer lag

## Future Enhancements

- [ ] Add Elasticsearch for advanced full-text search
- [ ] Implement search result ranking
- [ ] Add faceted search (categories, price ranges)
- [ ] Support fuzzy matching and typo tolerance
- [ ] Add search analytics and popular queries tracking
