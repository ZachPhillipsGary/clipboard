/**
 * Maccy E2E Encrypted Sync Backend
 * Cloudflare Workers entry point
 */

import type { Env, AuthContext } from './types';
import { errorResponse, jsonResponse, log } from './utils';
import { authenticate, updateDeviceLastSeen } from './auth';
import { checkRateLimit, RateLimiter } from './rate-limiter';
import {
  handleRegister,
  handlePush,
  handlePull,
  handleDelete,
  handleStatus,
} from './handlers';

// Export Durable Object class
export { RateLimiter };

/**
 * Main request handler
 */
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      });
    }

    try {
      // Health check endpoint
      if (path === '/health' || path === '/') {
        return jsonResponse({
          status: 'ok',
          service: 'maccy-sync-backend',
          version: '1.0.0',
          timestamp: Date.now(),
        });
      }

      // Public endpoint: Register device (no auth required)
      if (path === '/api/sync/register' && request.method === 'POST') {
        return await handleRegister(request, env);
      }

      // All other endpoints require authentication
      const authResult = await authenticate(request, env);
      if (authResult instanceof Response) {
        return authResult; // Authentication failed
      }

      const auth = authResult as AuthContext;

      // Rate limiting (check both minute and hour limits)
      const minuteLimit = await checkRateLimit(env, auth.sync_group_id, 'minute');
      if (!minuteLimit.allowed) {
        return errorResponse(
          'Rate limit exceeded. Please try again later.',
          'RATE_LIMIT_EXCEEDED',
          429,
          {
            reset_at: minuteLimit.reset_at,
            limit_type: 'minute',
          }
        );
      }

      const hourLimit = await checkRateLimit(env, auth.sync_group_id, 'hour');
      if (!hourLimit.allowed) {
        return errorResponse(
          'Rate limit exceeded. Please try again later.',
          'RATE_LIMIT_EXCEEDED',
          429,
          {
            reset_at: hourLimit.reset_at,
            limit_type: 'hour',
          }
        );
      }

      // Route to appropriate handler
      if (path === '/api/sync/push' && request.method === 'POST') {
        return await handlePush(request, env, auth);
      }

      if (path === '/api/sync/pull' && request.method === 'GET') {
        return await handlePull(request, env, auth);
      }

      if (path === '/api/sync/delete' && request.method === 'POST') {
        return await handleDelete(request, env, auth);
      }

      if (path === '/api/sync/status' && request.method === 'GET') {
        return await handleStatus(request, env, auth);
      }

      // Route not found
      return errorResponse('Endpoint not found', 'NOT_FOUND', 404);
    } catch (error) {
      log('error', 'Unhandled error', {
        error: String(error),
        path: url.pathname,
        method: request.method,
      });

      return errorResponse(
        'Internal server error',
        'INTERNAL_ERROR',
        500,
        env.ENVIRONMENT === 'development' ? String(error) : undefined
      );
    }
  },
};
