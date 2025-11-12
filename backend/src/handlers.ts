/**
 * API endpoint handlers for Maccy sync backend
 */

import type {
  Env,
  AuthContext,
  RegisterDeviceRequest,
  RegisterDeviceResponse,
  PushItemsRequest,
  PushItemsResponse,
  PullItemsRequest,
  PullItemsResponse,
  DeleteItemsRequest,
  DeleteItemsResponse,
  SyncStatusResponse,
} from './types';
import {
  generateToken,
  isValidUUID,
  isValidBase64,
  now,
  errorResponse,
  jsonResponse,
  parseJSON,
  sanitizeDeviceName,
  base64ToArrayBuffer,
  arrayBufferToBase64,
  log,
} from './utils';
import { updateDeviceLastSeen, updateSyncGroupActivity } from './auth';

/**
 * Register a new device and create sync group if needed
 */
export async function handleRegister(request: Request, env: Env): Promise<Response> {
  const body = await parseJSON<RegisterDeviceRequest>(request);

  if (!body) {
    return errorResponse('Invalid JSON body', 'INVALID_BODY', 400);
  }

  const { sync_group_id, device_id, device_name, device_type } = body;

  // Validate inputs
  if (!isValidUUID(sync_group_id)) {
    return errorResponse('Invalid sync_group_id format', 'INVALID_SYNC_GROUP_ID', 400);
  }

  if (!isValidUUID(device_id)) {
    return errorResponse('Invalid device_id format', 'INVALID_DEVICE_ID', 400);
  }

  if (!device_name || device_name.length === 0) {
    return errorResponse('device_name is required', 'MISSING_DEVICE_NAME', 400);
  }

  if (!['macos', 'ios', 'android', 'windows', 'linux'].includes(device_type)) {
    return errorResponse('Invalid device_type', 'INVALID_DEVICE_TYPE', 400);
  }

  try {
    const timestamp = now();

    // Start transaction
    const batch = [
      // Create sync group if it doesn't exist
      env.DB.prepare(
        `INSERT OR IGNORE INTO sync_groups (id, created_at, last_activity)
         VALUES (?, ?, ?)`
      ).bind(sync_group_id, timestamp, timestamp),

      // Create or update device
      env.DB.prepare(
        `INSERT INTO devices (id, sync_group_id, device_name, device_type, registered_at, last_seen, is_active)
         VALUES (?, ?, ?, ?, ?, ?, 1)
         ON CONFLICT(id) DO UPDATE SET
           device_name = excluded.device_name,
           device_type = excluded.device_type,
           last_seen = excluded.last_seen,
           is_active = 1`
      ).bind(device_id, sync_group_id, sanitizeDeviceName(device_name), device_type, timestamp, timestamp),
    ];

    await env.DB.batch(batch);

    // Generate auth token
    const token = generateToken(48);
    await env.DB.prepare(
      `INSERT INTO auth_tokens (token, sync_group_id, device_id, created_at)
       VALUES (?, ?, ?, ?)`
    ).bind(token, sync_group_id, device_id, timestamp)
      .run();

    // Fetch the created sync group and device
    const syncGroup = await env.DB.prepare(
      'SELECT * FROM sync_groups WHERE id = ?'
    ).bind(sync_group_id).first();

    const device = await env.DB.prepare(
      'SELECT * FROM devices WHERE id = ?'
    ).bind(device_id).first();

    log('info', 'Device registered', {
      sync_group_id,
      device_id,
      device_type,
    });

    const response: RegisterDeviceResponse = {
      token,
      sync_group: syncGroup as any,
      device: device as any,
    };

    return jsonResponse(response, 201);
  } catch (error) {
    log('error', 'Device registration failed', { error: String(error) });
    return errorResponse('Failed to register device', 'REGISTRATION_FAILED', 500);
  }
}

/**
 * Push encrypted items to server
 */
export async function handlePush(
  request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  const body = await parseJSON<PushItemsRequest>(request);

  if (!body || !Array.isArray(body.items)) {
    return errorResponse('Invalid request body', 'INVALID_BODY', 400);
  }

  const maxItems = parseInt(env.MAX_ITEMS_PER_SYNC || '100');
  if (body.items.length > maxItems) {
    return errorResponse(
      `Too many items. Maximum ${maxItems} per request`,
      'TOO_MANY_ITEMS',
      400
    );
  }

  try {
    const timestamp = now();
    const statements = [];
    let accepted = 0;
    let rejected = 0;
    const conflicts: string[] = [];

    for (const item of body.items) {
      // Validate item
      if (!isValidUUID(item.id)) {
        rejected++;
        continue;
      }

      if (!isValidBase64(item.encrypted_payload) || !isValidBase64(item.nonce)) {
        rejected++;
        continue;
      }

      if (!item.item_hash || item.item_hash.length !== 64) {
        rejected++;
        continue;
      }

      // Check for existing item (conflict detection)
      const existing = await env.DB.prepare(
        'SELECT id, updated_at, device_id FROM encrypted_items WHERE id = ? AND sync_group_id = ?'
      )
        .bind(item.id, auth.sync_group_id)
        .first<{ id: string; updated_at: number; device_id: string }>();

      if (existing) {
        // Conflict resolution: Keep newer item (Last Write Wins)
        if (existing.updated_at > item.updated_at) {
          conflicts.push(item.id);
          rejected++;
          continue;
        }
      }

      // Convert base64 to blob
      const encryptedPayload = base64ToArrayBuffer(item.encrypted_payload);
      const nonce = base64ToArrayBuffer(item.nonce);

      // Prepare insert/update statement
      statements.push(
        env.DB.prepare(
          `INSERT INTO encrypted_items (
            id, sync_group_id, device_id, encrypted_payload, nonce,
            created_at, updated_at, is_deleted, item_hash, compressed, size_bytes
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            encrypted_payload = excluded.encrypted_payload,
            nonce = excluded.nonce,
            updated_at = excluded.updated_at,
            device_id = excluded.device_id,
            item_hash = excluded.item_hash,
            compressed = excluded.compressed,
            size_bytes = excluded.size_bytes`
        ).bind(
          item.id,
          auth.sync_group_id,
          auth.device_id,
          encryptedPayload,
          nonce,
          item.created_at || timestamp,
          item.updated_at || timestamp,
          item.item_hash,
          item.compressed ? 1 : 0,
          item.size_bytes || 0
        )
      );

      accepted++;
    }

    // Execute batch
    if (statements.length > 0) {
      await env.DB.batch(statements);
    }

    // Update activity timestamps
    await updateDeviceLastSeen(env, auth.device_id);
    await updateSyncGroupActivity(env, auth.sync_group_id);

    log('info', 'Items pushed', {
      sync_group_id: auth.sync_group_id,
      device_id: auth.device_id,
      accepted,
      rejected,
      conflicts: conflicts.length,
    });

    const response: PushItemsResponse = {
      accepted,
      rejected,
      conflicts,
    };

    return jsonResponse(response);
  } catch (error) {
    log('error', 'Push failed', { error: String(error) });
    return errorResponse('Failed to push items', 'PUSH_FAILED', 500);
  }
}

/**
 * Pull encrypted items from server
 */
export async function handlePull(
  request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  const url = new URL(request.url);
  const since = parseInt(url.searchParams.get('since') || '0');
  const limit = Math.min(
    parseInt(url.searchParams.get('limit') || '100'),
    parseInt(env.MAX_ITEMS_PER_SYNC || '100')
  );

  try {
    // Query items updated since timestamp
    const query = `
      SELECT
        id, device_id, encrypted_payload, nonce,
        created_at, updated_at, is_deleted, item_hash,
        compressed, size_bytes
      FROM encrypted_items
      WHERE sync_group_id = ?
        AND updated_at > ?
      ORDER BY updated_at ASC
      LIMIT ?
    `;

    const results = await env.DB.prepare(query)
      .bind(auth.sync_group_id, since, limit + 1)
      .all();

    const hasMore = results.results && results.results.length > limit;
    const items = (results.results || []).slice(0, limit).map((row: any) => ({
      id: row.id,
      device_id: row.device_id,
      encrypted_payload: arrayBufferToBase64(row.encrypted_payload),
      nonce: arrayBufferToBase64(row.nonce),
      created_at: row.created_at,
      updated_at: row.updated_at,
      is_deleted: Boolean(row.is_deleted),
      item_hash: row.item_hash,
      compressed: Boolean(row.compressed),
      size_bytes: row.size_bytes || 0,
    }));

    // Update activity timestamps
    await updateDeviceLastSeen(env, auth.device_id);

    log('info', 'Items pulled', {
      sync_group_id: auth.sync_group_id,
      device_id: auth.device_id,
      count: items.length,
      since,
    });

    const response: PullItemsResponse = {
      items,
      has_more: hasMore,
      server_timestamp: now(),
    };

    return jsonResponse(response);
  } catch (error) {
    log('error', 'Pull failed', { error: String(error) });
    return errorResponse('Failed to pull items', 'PULL_FAILED', 500);
  }
}

/**
 * Mark items as deleted (soft delete)
 */
export async function handleDelete(
  request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  const body = await parseJSON<DeleteItemsRequest>(request);

  if (!body || !Array.isArray(body.item_ids)) {
    return errorResponse('Invalid request body', 'INVALID_BODY', 400);
  }

  if (body.item_ids.length === 0) {
    return jsonResponse({ deleted: 0 });
  }

  try {
    const timestamp = now();
    const placeholders = body.item_ids.map(() => '?').join(',');

    const result = await env.DB.prepare(
      `UPDATE encrypted_items
       SET is_deleted = 1, updated_at = ?
       WHERE id IN (${placeholders})
         AND sync_group_id = ?
         AND is_deleted = 0`
    )
      .bind(timestamp, ...body.item_ids, auth.sync_group_id)
      .run();

    // Update activity timestamps
    await updateDeviceLastSeen(env, auth.device_id);
    await updateSyncGroupActivity(env, auth.sync_group_id);

    log('info', 'Items deleted', {
      sync_group_id: auth.sync_group_id,
      device_id: auth.device_id,
      count: result.meta.changes || 0,
    });

    const response: DeleteItemsResponse = {
      deleted: result.meta.changes || 0,
    };

    return jsonResponse(response);
  } catch (error) {
    log('error', 'Delete failed', { error: String(error) });
    return errorResponse('Failed to delete items', 'DELETE_FAILED', 500);
  }
}

/**
 * Get sync group status and statistics
 */
export async function handleStatus(
  request: Request,
  env: Env,
  auth: AuthContext
): Promise<Response> {
  try {
    // Get device count
    const deviceCount = await env.DB.prepare(
      'SELECT COUNT(*) as count FROM devices WHERE sync_group_id = ? AND is_active = 1'
    )
      .bind(auth.sync_group_id)
      .first<{ count: number }>();

    // Get item count (non-deleted)
    const itemCount = await env.DB.prepare(
      'SELECT COUNT(*) as count FROM encrypted_items WHERE sync_group_id = ? AND is_deleted = 0'
    )
      .bind(auth.sync_group_id)
      .first<{ count: number }>();

    // Get total size
    const totalSize = await env.DB.prepare(
      'SELECT SUM(size_bytes) as total FROM encrypted_items WHERE sync_group_id = ? AND is_deleted = 0'
    )
      .bind(auth.sync_group_id)
      .first<{ total: number }>();

    // Get sync group info
    const syncGroup = await env.DB.prepare(
      'SELECT * FROM sync_groups WHERE id = ?'
    )
      .bind(auth.sync_group_id)
      .first<{ last_activity: number }>();

    // Get devices
    const devices = await env.DB.prepare(
      'SELECT id, device_name, device_type, last_seen, is_active FROM devices WHERE sync_group_id = ?'
    )
      .bind(auth.sync_group_id)
      .all();

    const response: SyncStatusResponse = {
      sync_group_id: auth.sync_group_id,
      device_count: deviceCount?.count || 0,
      item_count: itemCount?.count || 0,
      total_size_bytes: totalSize?.total || 0,
      last_activity: syncGroup?.last_activity || 0,
      devices: (devices.results || []).map((d: any) => ({
        id: d.id,
        name: d.device_name,
        type: d.device_type,
        last_seen: d.last_seen,
        is_active: Boolean(d.is_active),
      })),
    };

    return jsonResponse(response);
  } catch (error) {
    log('error', 'Status check failed', { error: String(error) });
    return errorResponse('Failed to get status', 'STATUS_FAILED', 500);
  }
}
