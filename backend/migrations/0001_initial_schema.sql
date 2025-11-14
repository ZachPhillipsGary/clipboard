-- Initial database schema for Maccy E2E encrypted sync
-- Version: 1.0
-- Created: 2025-11-12

-- Sync groups (one per user/QR pairing)
CREATE TABLE IF NOT EXISTS sync_groups (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    last_activity INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_sync_groups_activity ON sync_groups(last_activity);

-- Registered devices
CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL CHECK(device_type IN ('macos', 'ios', 'android', 'windows', 'linux')),
    registered_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    is_active INTEGER DEFAULT 1,
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_devices_sync_group ON devices(sync_group_id);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen);

-- Encrypted clipboard items
CREATE TABLE IF NOT EXISTS encrypted_items (
    id TEXT PRIMARY KEY,              -- UUID for item
    sync_group_id TEXT NOT NULL,
    device_id TEXT NOT NULL,          -- Source device
    encrypted_payload BLOB NOT NULL,  -- Encrypted HistoryItem JSON + contents
    nonce BLOB NOT NULL,              -- 12-byte ChaCha20-Poly1305 nonce
    created_at INTEGER NOT NULL,      -- Unix timestamp (ms)
    updated_at INTEGER NOT NULL,      -- For conflict resolution and sync
    is_deleted INTEGER DEFAULT 0,     -- Soft delete flag
    item_hash TEXT NOT NULL,          -- SHA256 of plaintext (for dedup)
    compressed INTEGER DEFAULT 0,     -- Whether payload is gzip compressed
    size_bytes INTEGER DEFAULT 0,     -- Original payload size
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_items_sync_group_updated ON encrypted_items(sync_group_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_items_device ON encrypted_items(device_id);
CREATE INDEX IF NOT EXISTS idx_items_hash ON encrypted_items(sync_group_id, item_hash);
CREATE INDEX IF NOT EXISTS idx_items_deleted ON encrypted_items(is_deleted, updated_at);

-- Authentication tokens (for API access)
CREATE TABLE IF NOT EXISTS auth_tokens (
    token TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER,               -- NULL = never expires
    last_used_at INTEGER,
    is_revoked INTEGER DEFAULT 0,
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_tokens_device ON auth_tokens(device_id);
CREATE INDEX IF NOT EXISTS idx_tokens_sync_group ON auth_tokens(sync_group_id);
CREATE INDEX IF NOT EXISTS idx_tokens_expires ON auth_tokens(expires_at) WHERE expires_at IS NOT NULL;

-- Rate limiting tracking (fallback if Durable Objects unavailable)
CREATE TABLE IF NOT EXISTS rate_limits (
    key TEXT PRIMARY KEY,             -- Format: "sync_group_id:minute" or "sync_group_id:hour"
    request_count INTEGER DEFAULT 0,
    window_start INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_limits_window ON rate_limits(window_start);

-- Sync statistics (for monitoring)
CREATE TABLE IF NOT EXISTS sync_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_group_id TEXT NOT NULL,
    device_id TEXT,
    operation TEXT NOT NULL,          -- 'push', 'pull', 'delete', 'register'
    item_count INTEGER DEFAULT 0,
    bytes_transferred INTEGER DEFAULT 0,
    duration_ms INTEGER DEFAULT 0,
    timestamp INTEGER NOT NULL,
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_sync_stats_group_time ON sync_stats(sync_group_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_sync_stats_timestamp ON sync_stats(timestamp);
