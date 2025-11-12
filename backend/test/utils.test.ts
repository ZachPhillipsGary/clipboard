/**
 * Unit tests for utility functions
 */

import { describe, test, expect } from 'bun:test';
import {
  generateToken,
  isValidUUID,
  isValidBase64,
  arrayBufferToBase64,
  base64ToArrayBuffer,
  sanitizeDeviceName,
  sha256,
} from '../src/utils';

describe('Utility Functions', () => {
  describe('generateToken', () => {
    test('should generate token of default length', () => {
      const token = generateToken();
      expect(token).toBeDefined();
      expect(token.length).toBeGreaterThan(0);
    });

    test('should generate unique tokens', () => {
      const token1 = generateToken();
      const token2 = generateToken();
      expect(token1).not.toBe(token2);
    });

    test('should generate URL-safe tokens', () => {
      const token = generateToken();
      expect(token).toMatch(/^[A-Za-z0-9_-]+$/);
    });
  });

  describe('isValidUUID', () => {
    test('should accept valid UUIDs', () => {
      expect(isValidUUID('123e4567-e89b-12d3-a456-426614174000')).toBe(true);
      expect(isValidUUID('00000000-0000-0000-0000-000000000000')).toBe(true);
    });

    test('should reject invalid UUIDs', () => {
      expect(isValidUUID('not-a-uuid')).toBe(false);
      expect(isValidUUID('123e4567-e89b-12d3-a456')).toBe(false);
      expect(isValidUUID('')).toBe(false);
      expect(isValidUUID('123e4567-e89b-12d3-a456-42661417400g')).toBe(false);
    });
  });

  describe('isValidBase64', () => {
    test('should accept valid base64 strings', () => {
      expect(isValidBase64('SGVsbG8gV29ybGQ=')).toBe(true);
      expect(isValidBase64('YWJjZGVmZ2g=')).toBe(true);
    });

    test('should reject invalid base64 strings', () => {
      expect(isValidBase64('not base64!')).toBe(false);
      expect(isValidBase64('')).toBe(false);
    });
  });

  describe('base64 conversion', () => {
    test('should convert ArrayBuffer to base64 and back', () => {
      const original = new TextEncoder().encode('Hello, World!');
      const base64 = arrayBufferToBase64(original.buffer);
      const decoded = base64ToArrayBuffer(base64);
      const result = new TextDecoder().decode(decoded);

      expect(result).toBe('Hello, World!');
    });

    test('should handle empty buffer', () => {
      const empty = new ArrayBuffer(0);
      const base64 = arrayBufferToBase64(empty);
      const decoded = base64ToArrayBuffer(base64);

      expect(decoded.byteLength).toBe(0);
    });
  });

  describe('sanitizeDeviceName', () => {
    test('should remove XSS characters', () => {
      expect(sanitizeDeviceName('My<script>alert("xss")</script>Device')).toBe(
        'MyscriptalertxssscriptDevice'
      );
      expect(sanitizeDeviceName('Device "Name" Test')).toBe('Device Name Test');
    });

    test('should trim whitespace', () => {
      expect(sanitizeDeviceName('  Device Name  ')).toBe('Device Name');
    });

    test('should limit length to 100 characters', () => {
      const longName = 'a'.repeat(150);
      const sanitized = sanitizeDeviceName(longName);
      expect(sanitized.length).toBe(100);
    });

    test('should handle empty string', () => {
      expect(sanitizeDeviceName('')).toBe('');
    });
  });

  describe('sha256', () => {
    test('should hash strings consistently', async () => {
      const hash1 = await sha256('test');
      const hash2 = await sha256('test');
      expect(hash1).toBe(hash2);
    });

    test('should produce different hashes for different inputs', async () => {
      const hash1 = await sha256('test1');
      const hash2 = await sha256('test2');
      expect(hash1).not.toBe(hash2);
    });

    test('should produce 64-character hex string', async () => {
      const hash = await sha256('test');
      expect(hash.length).toBe(64);
      expect(hash).toMatch(/^[a-f0-9]{64}$/);
    });

    test('should match known SHA-256 hash', async () => {
      // "hello" -> SHA-256
      const hash = await sha256('hello');
      expect(hash).toBe('2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
    });
  });
});
