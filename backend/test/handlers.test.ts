/**
 * Tests for API handlers
 */

import { describe, test, expect, beforeEach } from 'bun:test';
import { handleRegister, handlePush, handlePull } from '../src/handlers';

describe('API Handlers', () => {
  let mockEnv: any;
  let mockDB: any;
  let mockAuthContext: any;

  beforeEach(() => {
    // Mock D1 database
    mockDB = {
      prepare: (query: string) => ({
        bind: (...args: any[]) => ({
          first: async () => null,
          all: async () => ({ results: [] }),
          run: async () => ({ success: true, meta: { changes: 1 } }),
        }),
      }),
      batch: async (statements: any[]) => {
        return statements.map(() => ({ success: true, meta: { changes: 1 } }));
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

    mockAuthContext = {
      token: 'test-token',
      sync_group_id: 'group-1',
      device_id: 'device-1',
      device: {
        id: 'device-1',
        sync_group_id: 'group-1',
        device_name: 'Test Device',
        device_type: 'macos',
        registered_at: Date.now(),
        last_seen: Date.now(),
        is_active: 1,
      },
    };
  });

  describe('handleRegister', () => {
    test('should reject request without body', async () => {
      const request = new Request('https://example.com/register', {
        method: 'POST',
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('INVALID_BODY');
    });

    test('should reject invalid sync_group_id', async () => {
      const request = new Request('https://example.com/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sync_group_id: 'invalid-uuid',
          device_id: '123e4567-e89b-12d3-a456-426614174000',
          device_name: 'Test',
          device_type: 'macos',
        }),
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('INVALID_SYNC_GROUP_ID');
    });

    test('should reject invalid device_id', async () => {
      const request = new Request('https://example.com/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sync_group_id: '123e4567-e89b-12d3-a456-426614174000',
          device_id: 'invalid-uuid',
          device_name: 'Test',
          device_type: 'macos',
        }),
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('INVALID_DEVICE_ID');
    });

    test('should reject missing device_name', async () => {
      const request = new Request('https://example.com/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sync_group_id: '123e4567-e89b-12d3-a456-426614174000',
          device_id: '123e4567-e89b-12d3-a456-426614174001',
          device_name: '',
          device_type: 'macos',
        }),
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('MISSING_DEVICE_NAME');
    });

    test('should reject invalid device_type', async () => {
      const request = new Request('https://example.com/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sync_group_id: '123e4567-e89b-12d3-a456-426614174000',
          device_id: '123e4567-e89b-12d3-a456-426614174001',
          device_name: 'Test',
          device_type: 'invalid',
        }),
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('INVALID_DEVICE_TYPE');
    });

    test('should register device successfully', async () => {
      // Mock DB responses
      mockDB.prepare = (query: string) => ({
        bind: (...args: any[]) => ({
          run: async () => ({ success: true }),
          first: async () => {
            if (query.includes('sync_groups')) {
              return {
                id: args[0] || 'group-1',
                created_at: Date.now(),
                last_activity: Date.now(),
              };
            } else if (query.includes('devices')) {
              return {
                id: args[0] || 'device-1',
                sync_group_id: 'group-1',
                device_name: 'Test Device',
                device_type: 'macos',
                registered_at: Date.now(),
                last_seen: Date.now(),
                is_active: 1,
              };
            }
            return null;
          },
        }),
      });

      const request = new Request('https://example.com/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          sync_group_id: '123e4567-e89b-12d3-a456-426614174000',
          device_id: '123e4567-e89b-12d3-a456-426614174001',
          device_name: 'Test Device',
          device_type: 'macos',
        }),
      });

      const response = await handleRegister(request, mockEnv);
      expect(response.status).toBe(201);

      const body = await response.json();
      expect(body).toHaveProperty('token');
      expect(body).toHaveProperty('sync_group');
      expect(body).toHaveProperty('device');
    });
  });

  describe('handlePush', () => {
    test('should reject request without body', async () => {
      const request = new Request('https://example.com/push', {
        method: 'POST',
      });

      const response = await handlePush(request, mockEnv, mockAuthContext);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('INVALID_BODY');
    });

    test('should reject too many items', async () => {
      const items = Array(101).fill({
        id: '123e4567-e89b-12d3-a456-426614174000',
        encrypted_payload: 'dGVzdA==',
        nonce: 'dGVzdG5vbmNl',
        created_at: Date.now(),
        updated_at: Date.now(),
        item_hash: 'a'.repeat(64),
        compressed: false,
        size_bytes: 100,
      });

      const request = new Request('https://example.com/push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items }),
      });

      const response = await handlePush(request, mockEnv, mockAuthContext);
      expect(response.status).toBe(400);

      const body = await response.json();
      expect(body.code).toBe('TOO_MANY_ITEMS');
    });

    test('should push items successfully', async () => {
      const items = [
        {
          id: '123e4567-e89b-12d3-a456-426614174000',
          encrypted_payload: 'dGVzdA==',
          nonce: 'dGVzdG5vbmNl',
          created_at: Date.now(),
          updated_at: Date.now(),
          item_hash: 'a'.repeat(64),
          compressed: false,
          size_bytes: 100,
        },
      ];

      const request = new Request('https://example.com/push', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items }),
      });

      const response = await handlePush(request, mockEnv, mockAuthContext);
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body).toHaveProperty('accepted');
      expect(body).toHaveProperty('rejected');
      expect(body).toHaveProperty('conflicts');
    });
  });

  describe('handlePull', () => {
    test('should pull items successfully', async () => {
      // Mock DB to return items
      mockDB.prepare = () => ({
        bind: () => ({
          all: async () => ({
            results: [
              {
                id: '123e4567-e89b-12d3-a456-426614174000',
                device_id: 'device-2',
                encrypted_payload: new ArrayBuffer(10),
                nonce: new ArrayBuffer(12),
                created_at: Date.now(),
                updated_at: Date.now(),
                is_deleted: 0,
                item_hash: 'a'.repeat(64),
                compressed: 0,
                size_bytes: 100,
              },
            ],
          }),
          run: async () => ({ success: true }),
        }),
      });

      const request = new Request('https://example.com/pull?since=0&limit=100');

      const response = await handlePull(request, mockEnv, mockAuthContext);
      expect(response.status).toBe(200);

      const body = await response.json();
      expect(body).toHaveProperty('items');
      expect(body).toHaveProperty('has_more');
      expect(body).toHaveProperty('server_timestamp');
      expect(Array.isArray(body.items)).toBe(true);
    });

    test('should respect limit parameter', async () => {
      mockDB.prepare = () => ({
        bind: () => ({
          all: async () => ({ results: [] }),
          run: async () => ({ success: true }),
        }),
      });

      const request = new Request('https://example.com/pull?limit=50');

      const response = await handlePull(request, mockEnv, mockAuthContext);
      expect(response.status).toBe(200);
    });
  });
});
