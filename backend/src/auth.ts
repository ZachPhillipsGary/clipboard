/**
 * Authentication middleware for Maccy sync backend
 */

import type { Env, AuthContext, Device } from './types';
import { extractBearerToken, errorResponse, now } from './utils';

/**
 * Authenticate request and return auth context
 */
export async function authenticate(
  request: Request,
  env: Env
): Promise<AuthContext | Response> {
  const token = extractBearerToken(request);

  if (!token) {
    return errorResponse('Missing or invalid Authorization header', 'AUTH_MISSING', 401);
  }

  try {
    // Look up token in database
    const result = await env.DB.prepare(
      `SELECT
        t.token,
        t.sync_group_id,
        t.device_id,
        t.expires_at,
        t.is_revoked,
        d.id as device_id,
        d.device_name,
        d.device_type,
        d.registered_at,
        d.last_seen,
        d.is_active
      FROM auth_tokens t
      JOIN devices d ON t.device_id = d.id
      WHERE t.token = ?`
    )
      .bind(token)
      .first<{
        token: string;
        sync_group_id: string;
        device_id: string;
        expires_at: number | null;
        is_revoked: number;
        device_name: string;
        device_type: Device['device_type'];
        registered_at: number;
        last_seen: number;
        is_active: number;
      }>();

    if (!result) {
      return errorResponse('Invalid authentication token', 'AUTH_INVALID', 401);
    }

    // Check if token is revoked
    if (result.is_revoked) {
      return errorResponse('Authentication token has been revoked', 'AUTH_REVOKED', 401);
    }

    // Check if token is expired
    if (result.expires_at && result.expires_at < now()) {
      return errorResponse('Authentication token has expired', 'AUTH_EXPIRED', 401);
    }

    // Check if device is active
    if (!result.is_active) {
      return errorResponse('Device has been deactivated', 'DEVICE_INACTIVE', 403);
    }

    // Update last_used_at for the token (fire and forget)
    env.DB.prepare('UPDATE auth_tokens SET last_used_at = ? WHERE token = ?')
      .bind(now(), token)
      .run()
      .catch(() => {}); // Ignore errors for async update

    // Return auth context
    return {
      token: result.token,
      sync_group_id: result.sync_group_id,
      device_id: result.device_id,
      device: {
        id: result.device_id,
        sync_group_id: result.sync_group_id,
        device_name: result.device_name,
        device_type: result.device_type,
        registered_at: result.registered_at,
        last_seen: result.last_seen,
        is_active: result.is_active,
      },
    };
  } catch (error) {
    console.error('Authentication error:', error);
    return errorResponse('Authentication failed', 'AUTH_ERROR', 500);
  }
}

/**
 * Update device last_seen timestamp
 */
export async function updateDeviceLastSeen(
  env: Env,
  deviceId: string
): Promise<void> {
  try {
    await env.DB.prepare('UPDATE devices SET last_seen = ? WHERE id = ?')
      .bind(now(), deviceId)
      .run();
  } catch (error) {
    console.error('Failed to update device last_seen:', error);
    // Don't throw - this is not critical
  }
}

/**
 * Update sync group last_activity timestamp
 */
export async function updateSyncGroupActivity(
  env: Env,
  syncGroupId: string
): Promise<void> {
  try {
    await env.DB.prepare('UPDATE sync_groups SET last_activity = ? WHERE id = ?')
      .bind(now(), syncGroupId)
      .run();
  } catch (error) {
    console.error('Failed to update sync_groups last_activity:', error);
    // Don't throw - this is not critical
  }
}
