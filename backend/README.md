# Maccy Sync Backend

End-to-end encrypted clipboard synchronization backend using Cloudflare Workers and D1 database.

## Features

- 🔒 **Zero-knowledge architecture**: Server never sees plaintext data
- ⚡ **Cloudflare Workers**: Global edge deployment with low latency
- 💾 **D1 Database**: Distributed SQLite for encrypted storage
- 🚦 **Rate limiting**: Durable Objects for distributed rate limiting
- 🔐 **Token authentication**: Secure API access per device
- 📊 **Monitoring**: Built-in statistics and logging

## Prerequisites

- [Bun](https://bun.sh) v1.0+ (JavaScript runtime)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/) v3.0+ (Cloudflare Workers CLI)
- Cloudflare account (free tier works fine)

## Setup

### 1. Install Dependencies

```bash
cd backend
bun install
```

### 2. Login to Cloudflare

```bash
bun run cf:login
```

### 3. Create D1 Database

```bash
bun run db:create
```

This will output a database ID. Copy it and update `wrangler.toml`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "maccy-sync-db"
database_id = "your-database-id-here"  # Replace with actual ID
```

### 4. Run Migrations

For local development:
```bash
bun run db:migrate
```

For production:
```bash
bun run db:migrate:prod
```

### 5. Run Locally

```bash
bun run dev
```

The server will start at `http://localhost:8787`

### 6. Deploy to Production

```bash
bun run deploy
```

Your backend will be deployed to `https://maccy-sync-backend.<your-subdomain>.workers.dev`

## API Endpoints

### Health Check

```http
GET /health
```

**Response:**
```json
{
  "status": "ok",
  "service": "maccy-sync-backend",
  "version": "1.0.0",
  "timestamp": 1699999999999
}
```

### Register Device

Create a new sync group and register a device.

```http
POST /api/sync/register
Content-Type: application/json

{
  "sync_group_id": "uuid-v4",
  "device_id": "uuid-v4",
  "device_name": "My MacBook Pro",
  "device_type": "macos"
}
```

**Response:**
```json
{
  "token": "secure-auth-token",
  "sync_group": {
    "id": "uuid",
    "created_at": 1699999999999,
    "last_activity": 1699999999999
  },
  "device": {
    "id": "uuid",
    "sync_group_id": "uuid",
    "device_name": "My MacBook Pro",
    "device_type": "macos",
    "registered_at": 1699999999999,
    "last_seen": 1699999999999,
    "is_active": 1
  }
}
```

### Push Items

Upload encrypted clipboard items.

```http
POST /api/sync/push
Authorization: Bearer <token>
Content-Type: application/json

{
  "items": [
    {
      "id": "item-uuid",
      "encrypted_payload": "base64-encrypted-data",
      "nonce": "base64-nonce",
      "created_at": 1699999999999,
      "updated_at": 1699999999999,
      "item_hash": "sha256-hash",
      "compressed": false,
      "size_bytes": 1024
    }
  ]
}
```

**Response:**
```json
{
  "accepted": 1,
  "rejected": 0,
  "conflicts": []
}
```

### Pull Items

Download encrypted clipboard items.

```http
GET /api/sync/pull?since=1699999999999&limit=100
Authorization: Bearer <token>
```

**Query Parameters:**
- `since` (optional): Unix timestamp in ms, returns items updated after this time
- `limit` (optional): Maximum number of items to return (default 100)

**Response:**
```json
{
  "items": [
    {
      "id": "item-uuid",
      "device_id": "source-device-uuid",
      "encrypted_payload": "base64-encrypted-data",
      "nonce": "base64-nonce",
      "created_at": 1699999999999,
      "updated_at": 1699999999999,
      "is_deleted": false,
      "item_hash": "sha256-hash",
      "compressed": false,
      "size_bytes": 1024
    }
  ],
  "has_more": false,
  "server_timestamp": 1699999999999
}
```

### Delete Items

Mark items as deleted (soft delete).

```http
POST /api/sync/delete
Authorization: Bearer <token>
Content-Type: application/json

{
  "item_ids": ["uuid1", "uuid2"]
}
```

**Response:**
```json
{
  "deleted": 2
}
```

### Sync Status

Get sync group statistics and device list.

```http
GET /api/sync/status
Authorization: Bearer <token>
```

**Response:**
```json
{
  "sync_group_id": "uuid",
  "device_count": 2,
  "item_count": 150,
  "total_size_bytes": 5242880,
  "last_activity": 1699999999999,
  "devices": [
    {
      "id": "uuid",
      "name": "My MacBook Pro",
      "type": "macos",
      "last_seen": 1699999999999,
      "is_active": true
    }
  ]
}
```

## Error Responses

All errors follow this format:

```json
{
  "error": "Human-readable error message",
  "code": "ERROR_CODE",
  "details": {}
}
```

**Common Error Codes:**
- `AUTH_MISSING`: No Authorization header
- `AUTH_INVALID`: Invalid or expired token
- `AUTH_REVOKED`: Token has been revoked
- `DEVICE_INACTIVE`: Device has been deactivated
- `RATE_LIMIT_EXCEEDED`: Too many requests
- `INVALID_BODY`: Malformed request body
- `NOT_FOUND`: Endpoint not found

## Rate Limits

- **Per device**: 100 requests per minute
- **Per sync group**: 1000 requests per hour

Rate limit headers are included in all responses:
- `X-RateLimit-Limit`: Maximum requests allowed
- `X-RateLimit-Remaining`: Requests remaining in current window
- `X-RateLimit-Reset`: Unix timestamp when the limit resets

## Security

### Encryption

- All clipboard data is encrypted client-side using **ChaCha20-Poly1305**
- Server only stores encrypted blobs + nonces
- Keys never leave client devices
- Each encrypted item has a unique nonce

### Authentication

- Bearer token authentication for all protected endpoints
- Tokens are 48-byte cryptographically random values
- Tokens are bound to specific device + sync group
- Token revocation supported

### Privacy

- No PII collected or stored
- No user accounts or emails required
- Sync groups are ephemeral and anonymous
- Server logs contain no plaintext content

## Testing

Run unit tests:

```bash
bun test
```

Run tests in watch mode:

```bash
bun test:watch
```

## Development

### Local D1 Database Console

Execute SQL commands against local database:

```bash
bun run db:console -- "SELECT COUNT(*) FROM encrypted_items"
```

### Environment Variables

Configure in `wrangler.toml`:

- `ENVIRONMENT`: `development` or `production`
- `MAX_ITEMS_PER_SYNC`: Maximum items per push/pull (default 100)
- `RATE_LIMIT_REQUESTS_PER_HOUR`: Hourly rate limit (default 1000)
- `RATE_LIMIT_REQUESTS_PER_MINUTE`: Per-minute rate limit (default 100)

### Logging

Structured JSON logs are sent to stdout:

```json
{
  "timestamp": "2024-11-12T12:00:00.000Z",
  "level": "info",
  "message": "Items pushed",
  "sync_group_id": "uuid",
  "device_id": "uuid",
  "accepted": 5,
  "rejected": 0
}
```

View logs in Cloudflare dashboard or via CLI:

```bash
wrangler tail
```

## Monitoring

### Cloudflare Dashboard

Monitor your Worker at:
https://dash.cloudflare.com/<account-id>/workers/services/view/maccy-sync-backend/production

**Metrics Available:**
- Requests per second
- Error rate
- CPU time
- D1 queries
- Durable Object requests

### Custom Metrics

The `sync_stats` table tracks:
- Operation type (push/pull/delete/register)
- Item counts
- Bytes transferred
- Duration

Query example:

```sql
SELECT operation, COUNT(*) as count, AVG(duration_ms) as avg_duration
FROM sync_stats
WHERE timestamp > (strftime('%s', 'now') - 86400) * 1000
GROUP BY operation;
```

## Cost Estimation

### Cloudflare Free Tier

- 100,000 requests/day
- 10 D1 databases
- 5GB D1 storage

**Sufficient for:**
- ~10 devices
- ~5000 clipboard items
- ~50 syncs per day per device

### Paid Tier ($5/month base)

- Unlimited requests ($0.50/million after free tier)
- Unlimited D1 storage ($0.75/GB)

**Example costs for heavy usage:**
- 10 devices, 100 syncs/day/device = ~30k requests/month = **Free**
- 50 devices, 1000 syncs/day/device = ~1.5M requests/month = **$5.75/month**
- Storage: 10k items @ 100KB avg = 1GB = **$0.75/month**

## Troubleshooting

### "Database not found" error

Make sure you've created the D1 database and run migrations:

```bash
bun run db:create
bun run db:migrate
```

### "Rate limit exceeded" locally

Clear your local Durable Object storage:

```bash
rm -rf .wrangler/state
```

### "Type error" during deployment

Ensure you're using the latest Wrangler and TypeScript:

```bash
bun update wrangler typescript
```

### Authentication always fails

Check that your `Authorization` header format is correct:

```
Authorization: Bearer <token>
```

Not:
```
Authorization: <token>
```

## License

Same as Maccy (MIT License)

## Support

- Issues: https://github.com/p0deje/Maccy/issues
- Discussions: https://github.com/p0deje/Maccy/discussions
