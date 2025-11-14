/**
 * Rate limiter using Cloudflare Durable Objects
 */

import type { RateLimitResult } from './types';

interface RateLimitWindow {
  count: number;
  resetAt: number;
}

export class RateLimiter {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  /**
   * Check and increment rate limit
   */
  async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      const key = url.searchParams.get('key');
      const limitType = url.searchParams.get('type') || 'minute'; // 'minute' or 'hour'
      const limit = parseInt(url.searchParams.get('limit') || '100');

      if (!key) {
        return new Response(JSON.stringify({ error: 'Missing key' }), { status: 400 });
      }

      const now = Date.now();
      const windowKey = `${key}:${limitType}`;

      // Get current window from storage
      const stored = await this.state.storage.get<RateLimitWindow>(windowKey);

      // Determine window duration
      const windowDuration = limitType === 'hour' ? 3600000 : 60000; // ms

      let window: RateLimitWindow;

      if (!stored || stored.resetAt <= now) {
        // Create new window
        window = {
          count: 1,
          resetAt: now + windowDuration,
        };
      } else {
        // Increment existing window
        window = {
          count: stored.count + 1,
          resetAt: stored.resetAt,
        };
      }

      // Store updated window
      await this.state.storage.put(windowKey, window);

      // Check if limit exceeded
      const allowed = window.count <= limit;
      const remaining = Math.max(0, limit - window.count);

      const result: RateLimitResult = {
        allowed,
        remaining,
        reset_at: window.resetAt,
      };

      return new Response(JSON.stringify(result), {
        status: allowed ? 200 : 429,
        headers: {
          'Content-Type': 'application/json',
          'X-RateLimit-Limit': limit.toString(),
          'X-RateLimit-Remaining': remaining.toString(),
          'X-RateLimit-Reset': window.resetAt.toString(),
        },
      });
    } catch (error) {
      console.error('Rate limiter error:', error);
      return new Response(JSON.stringify({ error: 'Rate limiter error' }), { status: 500 });
    }
  }
}

/**
 * Check rate limit using Durable Object
 */
export async function checkRateLimit(
  env: any,
  syncGroupId: string,
  limitType: 'minute' | 'hour'
): Promise<RateLimitResult> {
  try {
    // Get Durable Object ID
    const id = env.RATE_LIMITER.idFromName(syncGroupId);
    const stub = env.RATE_LIMITER.get(id);

    // Determine limit
    const limit =
      limitType === 'hour'
        ? parseInt(env.RATE_LIMIT_REQUESTS_PER_HOUR || '1000')
        : parseInt(env.RATE_LIMIT_REQUESTS_PER_MINUTE || '100');

    // Call Durable Object
    const url = `https://dummy.com/?key=${encodeURIComponent(syncGroupId)}&type=${limitType}&limit=${limit}`;
    const response = await stub.fetch(url);
    const result = (await response.json()) as RateLimitResult;

    return result;
  } catch (error) {
    console.error('Rate limit check failed:', error);
    // On error, allow the request (fail open)
    return {
      allowed: true,
      remaining: 0,
      reset_at: Date.now() + 60000,
    };
  }
}

/**
 * Fallback rate limiter using D1 (if Durable Objects unavailable)
 */
export async function checkRateLimitFallback(
  db: any,
  syncGroupId: string,
  limitType: 'minute' | 'hour',
  limit: number
): Promise<RateLimitResult> {
  try {
    const now = Date.now();
    const windowDuration = limitType === 'hour' ? 3600000 : 60000;
    const windowKey = `${syncGroupId}:${limitType}`;

    // Get current window
    const result = (await db
      .prepare(
        `SELECT request_count, window_start
         FROM rate_limits
         WHERE key = ?`
      )
      .bind(windowKey)
      .first()) as { request_count: number; window_start: number } | null;

    let count = 1;
    let resetAt = now + windowDuration;

    if (result) {
      if (result.window_start + windowDuration > now) {
        // Window is still valid
        count = result.request_count + 1;
        resetAt = result.window_start + windowDuration;

        // Update count
        await db
          .prepare(
            `UPDATE rate_limits
             SET request_count = ?, updated_at = ?
             WHERE key = ?`
          )
          .bind(count, now, windowKey)
          .run();
      } else {
        // Window expired, create new one
        await db
          .prepare(
            `UPDATE rate_limits
             SET request_count = 1, window_start = ?, updated_at = ?
             WHERE key = ?`
          )
          .bind(now, now, windowKey)
          .run();
      }
    } else {
      // Create new window
      await db
        .prepare(
          `INSERT INTO rate_limits (key, request_count, window_start, updated_at)
           VALUES (?, 1, ?, ?)`
        )
        .bind(windowKey, now, now)
        .run();
    }

    const allowed = count <= limit;
    const remaining = Math.max(0, limit - count);

    return {
      allowed,
      remaining,
      reset_at: resetAt,
    };
  } catch (error) {
    console.error('Fallback rate limit check failed:', error);
    // On error, allow the request
    return {
      allowed: true,
      remaining: 0,
      reset_at: Date.now() + 60000,
    };
  }
}
