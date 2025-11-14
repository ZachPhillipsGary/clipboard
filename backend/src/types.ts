/**
 * Type definitions for Maccy E2E encrypted sync backend
 */

export interface Env {
  DB: D1Database;
  RATE_LIMITER: DurableObjectNamespace;
  ENVIRONMENT: string;
  MAX_ITEMS_PER_SYNC: string;
  RATE_LIMIT_REQUESTS_PER_HOUR: string;
  RATE_LIMIT_REQUESTS_PER_MINUTE: string;
}

// Database models
export interface SyncGroup {
  id: string;
  created_at: number;
  last_activity: number;
}

export interface Device {
  id: string;
  sync_group_id: string;
  device_name: string;
  device_type: 'macos' | 'ios' | 'android' | 'windows' | 'linux';
  registered_at: number;
  last_seen: number;
  is_active: number;
}

export interface EncryptedItem {
  id: string;
  sync_group_id: string;
  device_id: string;
  encrypted_payload: ArrayBuffer;
  nonce: ArrayBuffer;
  created_at: number;
  updated_at: number;
  is_deleted: number;
  item_hash: string;
  compressed: number;
  size_bytes: number;
}

export interface AuthToken {
  token: string;
  sync_group_id: string;
  device_id: string;
  created_at: number;
  expires_at: number | null;
  last_used_at: number | null;
  is_revoked: number;
}

export interface SyncStats {
  id?: number;
  sync_group_id: string;
  device_id: string | null;
  operation: 'push' | 'pull' | 'delete' | 'register';
  item_count: number;
  bytes_transferred: number;
  duration_ms: number;
  timestamp: number;
}

// API Request/Response types
export interface RegisterDeviceRequest {
  sync_group_id: string;
  device_id: string;
  device_name: string;
  device_type: Device['device_type'];
}

export interface RegisterDeviceResponse {
  token: string;
  sync_group: SyncGroup;
  device: Device;
}

export interface PushItemsRequest {
  items: {
    id: string;
    encrypted_payload: string; // base64
    nonce: string; // base64
    created_at: number;
    updated_at: number;
    item_hash: string;
    compressed?: boolean;
    size_bytes?: number;
  }[];
}

export interface PushItemsResponse {
  accepted: number;
  rejected: number;
  conflicts: string[]; // Item IDs with conflicts
}

export interface PullItemsRequest {
  since?: number; // Unix timestamp (ms), omit for full sync
  limit?: number;
}

export interface PullItemsResponse {
  items: {
    id: string;
    device_id: string;
    encrypted_payload: string; // base64
    nonce: string; // base64
    created_at: number;
    updated_at: number;
    is_deleted: boolean;
    item_hash: string;
    compressed: boolean;
    size_bytes: number;
  }[];
  has_more: boolean;
  server_timestamp: number;
}

export interface DeleteItemsRequest {
  item_ids: string[];
}

export interface DeleteItemsResponse {
  deleted: number;
}

export interface SyncStatusResponse {
  sync_group_id: string;
  device_count: number;
  item_count: number;
  total_size_bytes: number;
  last_activity: number;
  devices: {
    id: string;
    name: string;
    type: Device['device_type'];
    last_seen: number;
    is_active: boolean;
  }[];
}

export interface ErrorResponse {
  error: string;
  code: string;
  details?: any;
}

// Authentication context
export interface AuthContext {
  token: string;
  sync_group_id: string;
  device_id: string;
  device: Device;
}

// Rate limiting
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  reset_at: number;
}
