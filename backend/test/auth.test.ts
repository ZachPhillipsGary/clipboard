/**
 * Tests for authentication middleware
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import { authenticate, updateDeviceLastSeen } from '../src/auth';

describe('Authentication', () => {
  let mockEnv: any;
  let mockDB: any;

  beforeEach(() => {
    // Mock D1 database
    const mockResults = new Map<string, any>();

    mockDB = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          first: async () => mockResults.get('first'),
          all: async () => ({ results: mockResults.get('all') || [] }),
          run: async () => ({ success: true, meta: { changes: 1 } }),
        }),
      }),
      batch: async (statements: any[]) => {
        return statements.map(() => ({ success: true }));
      },
    };

    mockEnv = {
      DB: mockDB,
      RATE_LIMITER: {},
      ENVIRONMENT: 'test',
      MAX_ITEMS_PER_SYNC: '100',
      RATE_LIMIT_REQUESTS_PER_HOUR: '1000',
      RATE_LIMIT_REQUESTS_PER_MINUTE: '100',
    };
  });

  test('should reject request without Authorization header', async () => {
    const request = new Request('https://example.com/test');
    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
      const body = await result.json();
      expect(body.code).toBe('AUTH_MISSING');
    }
  });

  test('should reject request with invalid token format', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'InvalidFormat' },
    });
    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
    }
  });

  test('should reject request with non-existent token', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'Bearer invalid-token' },
    });

    // Mock DB to return no results
    mockDB.prepare = () => ({
      bind: () => ({
        first: async () => null,
      }),
    });

    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
      const body = await result.json();
      expect(body.code).toBe('AUTH_INVALID');
    }
  });

  test('should reject revoked token', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'Bearer valid-token' },
    });

    // Mock DB to return revoked token
    mockDB.prepare = () => ({
      bind: () => ({
        first: async () => ({
          token: 'valid-token',
          sync_group_id: 'group-1',
          device_id: 'device-1',
          expires_at: null,
          is_revoked: 1, // REVOKED
          device_name: 'Test Device',
          device_type: 'macos',
          registered_at: Date.now(),
          last_seen: Date.now(),
          is_active: 1,
        }),
      }),
    });

    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
      const body = await result.json();
      expect(body.code).toBe('AUTH_REVOKED');
    }
  });

  test('should reject expired token', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'Bearer valid-token' },
    });

    // Mock DB to return expired token
    mockDB.prepare = () => ({
      bind: () => ({
        first: async () => ({
          token: 'valid-token',
          sync_group_id: 'group-1',
          device_id: 'device-1',
          expires_at: Date.now() - 1000, // EXPIRED
          is_revoked: 0,
          device_name: 'Test Device',
          device_type: 'macos',
          registered_at: Date.now(),
          last_seen: Date.now(),
          is_active: 1,
        }),
      }),
    });

    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(401);
      const body = await result.json();
      expect(body.code).toBe('AUTH_EXPIRED');
    }
  });

  test('should reject inactive device', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'Bearer valid-token' },
    });

    // Mock DB to return inactive device
    mockDB.prepare = () => ({
      bind: () => ({
        first: async () => ({
          token: 'valid-token',
          sync_group_id: 'group-1',
          device_id: 'device-1',
          expires_at: null,
          is_revoked: 0,
          device_name: 'Test Device',
          device_type: 'macos',
          registered_at: Date.now(),
          last_seen: Date.now(),
          is_active: 0, // INACTIVE
        }),
      }),
    });

    const result = await authenticate(request, mockEnv);

    expect(result).toBeInstanceOf(Response);
    if (result instanceof Response) {
      expect(result.status).toBe(403);
      const body = await result.json();
      expect(body.code).toBe('DEVICE_INACTIVE');
    }
  });

  test('should accept valid token', async () => {
    const request = new Request('https://example.com/test', {
      headers: { Authorization: 'Bearer valid-token' },
    });

    // Mock DB to return valid token
    mockDB.prepare = () => ({
      bind: () => ({
        first: async () => ({
          token: 'valid-token',
          sync_group_id: 'group-1',
          device_id: 'device-1',
          expires_at: null,
          is_revoked: 0,
          device_name: 'Test Device',
          device_type: 'macos',
          registered_at: Date.now(),
          last_seen: Date.now(),
          is_active: 1,
        }),
        run: async () => ({ success: true }),
      }),
    });

    const result = await authenticate(request, mockEnv);

    expect(result).not.toBeInstanceOf(Response);
    expect(result).toHaveProperty('token', 'valid-token');
    expect(result).toHaveProperty('sync_group_id', 'group-1');
    expect(result).toHaveProperty('device_id', 'device-1');
  });
});
