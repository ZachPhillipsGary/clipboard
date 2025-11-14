# Maccy E2E Encrypted Sync Architecture

## Overview
This document outlines the architecture for end-to-end encrypted clipboard synchronization using Cloudflare Workers, D1 database, and native iOS/macOS apps.

## Security Principles

### Zero-Knowledge Architecture
- **Server never sees plaintext data**: All clipboard content is encrypted on the client before transmission
- **Client-side encryption only**: Encryption keys never leave the user's devices
- **No server-side decryption capability**: Cloudflare Workers only store and relay encrypted blobs

### Encryption Strategy
- **Algorithm**: ChaCha20-Poly1305 (AEAD - Authenticated Encryption with Associated Data)
- **Key Derivation**: HKDF-SHA256 for deriving encryption keys from master key
- **Key Storage**: iOS Keychain / macOS Keychain with `.afterFirstUnlock` accessibility
- **Key Rotation**: Master key per "sync group", rotatable on demand

### Device Pairing Protocol
1. **Primary Device (macOS)** generates:
   - 32-byte master encryption key (random)
   - Device ID (UUID)
   - Sync group ID (UUID)
   - API authentication token (random, for Cloudflare Workers)

2. **QR Code contains** (JSON, ephemeral display):
   ```json
   {
     "version": 1,
     "syncGroupId": "uuid",
     "masterKey": "base64-encoded-key",
     "apiEndpoint": "https://your-worker.workers.dev",
     "deviceId": "primary-device-uuid"
   }
   ```

3. **Secondary Device (iOS)** scans QR:
   - Stores master key in Keychain
   - Generates its own device ID
   - Registers with backend
   - Begins sync

### Threat Model Protections
- ✅ **Server compromise**: Encrypted data useless without keys
- ✅ **Network interception**: TLS + E2E encryption
- ✅ **Stolen database backup**: All data encrypted
- ✅ **Malicious Cloudflare Worker**: Cannot decrypt data
- ⚠️ **Device compromise**: If device keychain accessed, data readable (OS-level protection)
- ⚠️ **QR code interception**: Display QR only in secure environment (brief display)

---

## System Components

### 1. Cloudflare Worker Backend (`/backend`)

**Technology Stack**:
- Runtime: Cloudflare Workers (V8 isolate)
- Database: D1 (SQLite)
- Development: Bun + Wrangler CLI
- Language: TypeScript

**API Endpoints**:

```typescript
POST   /api/sync/register      // Register new device
POST   /api/sync/push          // Upload encrypted items
GET    /api/sync/pull          // Download encrypted items since timestamp
POST   /api/sync/delete        // Mark items as deleted
GET    /api/sync/status        // Get sync group status
POST   /api/sync/rotate-key    // Rotate encryption key (future)
```

**D1 Database Schema**:

```sql
-- Sync groups (one per user/QR pairing)
CREATE TABLE sync_groups (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    last_activity INTEGER NOT NULL
);

-- Registered devices
CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL,
    device_name TEXT NOT NULL,
    device_type TEXT NOT NULL, -- 'macos' | 'ios'
    registered_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL,
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE
);

-- Encrypted clipboard items
CREATE TABLE encrypted_items (
    id TEXT PRIMARY KEY,              -- UUID for item
    sync_group_id TEXT NOT NULL,
    device_id TEXT NOT NULL,          -- Source device
    encrypted_payload BLOB NOT NULL,  -- Encrypted HistoryItem JSON + contents
    nonce BLOB NOT NULL,              -- 12-byte ChaCha20-Poly1305 nonce
    created_at INTEGER NOT NULL,      -- Unix timestamp (ms)
    updated_at INTEGER NOT NULL,      -- For conflict resolution
    is_deleted INTEGER DEFAULT 0,     -- Soft delete flag
    item_hash TEXT NOT NULL,          -- SHA256 of plaintext (for dedup)
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX idx_items_sync_group ON encrypted_items(sync_group_id, updated_at);
CREATE INDEX idx_items_device ON encrypted_items(device_id);
CREATE INDEX idx_items_hash ON encrypted_items(sync_group_id, item_hash);

-- Authentication tokens (for API access)
CREATE TABLE auth_tokens (
    token TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    expires_at INTEGER,
    FOREIGN KEY (sync_group_id) REFERENCES sync_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE CASCADE
);

CREATE INDEX idx_tokens_device ON auth_tokens(device_id);
```

**Authentication**:
- Bearer token in `Authorization` header
- Token generated during device registration
- Token validates: sync_group_id + device_id

**Rate Limiting**:
- Per sync group: 1000 requests/hour
- Per device: 100 requests/minute
- Stored in Durable Objects for distributed rate limiting

---

### 2. macOS App Sync Module (`Maccy/Sync/`)

**New Files Structure**:
```
Maccy/Sync/
├── SyncService.swift          // Main sync orchestration
├── EncryptionService.swift    // CryptoKit E2E encryption
├── SyncAPIClient.swift        // Cloudflare Worker HTTP client
├── SyncModels.swift           // Encrypted payload models
├── SyncConflictResolver.swift // CRDT-style conflict resolution
├── QRCodeGenerator.swift      // QR code pairing
├── SyncSettings.swift         // User preferences
└── SyncStatus.swift           // Observable sync state
```

**Data Model Extensions**:

```swift
// Add to HistoryItem
extension HistoryItem {
    var syncId: String?           // UUID for sync
    var deviceId: String?         // Source device
    var lastSyncedAt: Date?       // Last upload timestamp
    var syncHash: String?         // SHA256 for deduplication
    var isSyncDeleted: Bool       // Tombstone for deletions
}
```

**Sync Flow**:

1. **Background Timer** (every 30 seconds, configurable):
   - Check for local changes since `lastSyncedAt`
   - Encrypt changed items
   - Push to Cloudflare Worker
   - Pull remote changes
   - Decrypt and merge

2. **Conflict Resolution**:
   - Use `lastCopiedAt` + `numberOfCopies` as vector clock
   - If timestamps equal, prefer item with higher `numberOfCopies`
   - If same, prefer item from current device (LWW - Last Write Wins)

3. **Encryption Process**:
   ```swift
   // Pseudocode
   func encryptItem(_ item: HistoryItem) -> EncryptedPayload {
       let json = encodeToJSON(item) // Include all contents
       let nonce = generateRandomNonce() // 12 bytes
       let ciphertext = ChaCha20Poly1305.seal(
           json,
           using: masterKey,
           nonce: nonce
       )
       let hash = SHA256.hash(json)
       return EncryptedPayload(
           id: item.syncId,
           ciphertext: ciphertext,
           nonce: nonce,
           hash: hash
       )
   }
   ```

**Keychain Storage**:
```swift
// Store master key
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "maccy-sync-master-key",
    kSecAttrService as String: "org.p0deje.Maccy.sync",
    kSecValueData as String: masterKey,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
]
SecItemAdd(query as CFDictionary, nil)
```

**Settings UI** (`Maccy/Settings/SyncSettingsView.swift`):
- Enable/disable sync toggle
- Show QR code button (modal with large QR)
- List paired devices
- Sync status indicator (last sync time, items synced)
- Manual sync button
- Clear sync data / unpair devices

---

### 3. iOS Companion App (`MaccyViewer/`)

**New Xcode Project**:
- Product Name: Maccy Viewer
- Bundle ID: `org.p0deje.MaccyViewer`
- Deployment Target: iOS 16.0+
- SwiftUI lifecycle

**App Structure**:
```
MaccyViewer/
├── MaccyViewerApp.swift       // App entry point
├── Views/
│   ├── OnboardingView.swift   // QR scanner for pairing
│   ├── ClipboardListView.swift // Main list of items
│   ├── ClipboardDetailView.swift // Detail/preview
│   ├── SearchView.swift       // Search interface
│   └── SettingsView.swift     // App settings
├── Models/
│   ├── ClipboardItem.swift    // Decoded HistoryItem
│   └── SyncState.swift        // @Observable sync state
├── Services/
│   ├── SyncService.swift      // Sync logic (shared with macOS)
│   ├── EncryptionService.swift // Decryption (shared)
│   └── APIClient.swift        // HTTP client (shared)
└── Utils/
    └── QRScanner.swift        // AVFoundation QR scanning
```

**Key Features**:
1. **QR Code Onboarding**:
   - Camera permission request
   - Scan QR from macOS app
   - Validate and store credentials in Keychain
   - Initiate first sync

2. **Clipboard List**:
   - SwiftUI List with search
   - Group by date
   - Preview text/images
   - Pull-to-refresh for manual sync
   - Tap to copy to iOS clipboard

3. **Search**:
   - Use Fuse.swift for fuzzy search (same as macOS)
   - Filter by type (text, images, etc.)
   - Search in decrypted content

4. **Sync**:
   - Background sync via Background Tasks framework
   - Foreground sync on app open
   - Real-time status indicator

**Code Sharing Strategy**:
- Extract sync/encryption logic into Swift Package
- Share between macOS app and iOS app
- Platform-specific UI only

---

## Implementation Plan

### Phase 1: Backend Foundation
1. Initialize Bun project with Wrangler
2. Create D1 database schema
3. Implement authentication middleware
4. Build core API endpoints
5. Add rate limiting
6. Write API integration tests

### Phase 2: macOS Encryption & Sync
1. Add network entitlement to `Maccy.entitlements`
2. Create `EncryptionService` with CryptoKit
3. Extend `HistoryItem` model with sync fields
4. Build `SyncAPIClient` with URLSession
5. Implement `SyncService` orchestration
6. Add `QRCodeGenerator` for pairing
7. Create `SyncSettingsView` UI
8. Write unit tests for encryption/sync

### Phase 3: iOS Companion App
1. Create new iOS Xcode project
2. Implement QR scanner with AVFoundation
3. Share sync/encryption code via Swift Package
4. Build SwiftUI views (list, detail, search)
5. Implement background sync
6. Add Keychain integration
7. Write UI tests

### Phase 4: Testing & Polish
1. End-to-end testing (macOS ↔ Worker ↔ iOS)
2. Security audit of encryption implementation
3. Performance testing (large clipboard histories)
4. Error handling and retry logic
5. Documentation
6. Beta testing

---

## Security Considerations

### Data Leakage Prevention
- ❌ **No plaintext logging**: Never log decrypted content or keys
- ❌ **No analytics on content**: Only sync metadata (count, size)
- ✅ **Memory wiping**: Zero out key buffers after use
- ✅ **Secure random**: Use `SecRandomCopyBytes` for nonces/keys

### Network Security
- ✅ **TLS 1.3 only**: Enforce modern TLS
- ✅ **Certificate pinning** (optional): Pin Cloudflare Workers cert
- ✅ **Request signing**: HMAC requests to prevent replay attacks

### Key Management
- ✅ **One-time QR display**: QR shown briefly, then cleared
- ✅ **No cloud key backup**: Users responsible for re-pairing if lost
- ✅ **Key rotation support**: Allow generating new master key
- ✅ **Device revocation**: Remove device from sync group

### Privacy
- ❌ **No user accounts**: No email, no PII
- ❌ **No server-side search**: All indexing client-side
- ✅ **Automatic expiration**: Option to auto-delete items after N days
- ✅ **Sync opt-in**: Disabled by default, explicit user choice

---

## Performance Optimizations

### Compression
- Use gzip on encrypted payloads before transmission
- Reduces bandwidth for large text content

### Delta Sync
- Only sync items changed since last pull
- Use `updated_at` timestamp for filtering

### Batching
- Upload/download in batches of 50 items
- Reduce HTTP request overhead

### Caching
- Cache decrypted items in memory
- Invalidate on remote changes

### Image Handling
- Compress images before encryption (lossy JPEG/HEIC)
- Option to exclude images from sync
- Progressive loading on iOS

---

## Deployment

### Cloudflare Worker
```bash
# Deploy from /backend
bun install
wrangler d1 create maccy-sync-db
wrangler deploy
```

### macOS App
- New build with network entitlement
- Distribute via existing channels (GitHub, Homebrew)
- Sparkle auto-update

### iOS App
- Submit to App Store
- App Store Connect configuration
- TestFlight beta

---

## Future Enhancements

1. **End-to-end encrypted backup**: Export encrypted backup file
2. **Multi-group support**: Separate work/personal sync groups
3. **Selective sync**: Choose which apps/types to sync
4. **Compression**: zstd compression before encryption
5. **WebSocket**: Real-time sync via Workers Durable Objects
6. **Desktop clients**: Windows/Linux Electron apps
7. **Browser extension**: Sync with Chrome/Firefox/Safari
8. **Audit log**: Client-side log of all sync operations

---

## Testing Strategy

### Unit Tests
- ✅ Encryption/decryption roundtrip
- ✅ Key derivation
- ✅ Conflict resolution logic
- ✅ API client error handling
- ✅ Model serialization

### Integration Tests
- ✅ Full sync flow (upload → download → decrypt)
- ✅ Multi-device conflict scenarios
- ✅ Network failure recovery
- ✅ Large clipboard history (1000+ items)

### Security Tests
- ✅ Verify ciphertext differs for same plaintext (nonce uniqueness)
- ✅ Tamper detection (modified ciphertext rejected)
- ✅ Key isolation (multiple sync groups don't share keys)
- ✅ Timing attack resistance

### Manual QA
- ✅ QR code scanning in various lighting
- ✅ Offline mode behavior
- ✅ Battery impact on iOS
- ✅ Large image sync
- ✅ App backgrounding/foregrounding

---

## Cost Estimation

### Cloudflare Workers (Free Tier)
- 100,000 requests/day
- 10 D1 databases
- 5GB D1 storage
- **Cost**: $0/month for most users

### Paid Tier (if needed)
- $5/month base
- $0.50/million requests after free tier
- $0.75/GB D1 storage
- **Estimated**: $5-10/month for heavy users (10+ devices, 10k+ items)

---

## Open Questions

1. **Clipboard image quality**: Compress lossy or lossless?
   - **Recommendation**: User preference, default lossy JPEG 85% quality

2. **Sync frequency**: 30 seconds or push-based?
   - **Recommendation**: 30 seconds for MVP, WebSocket for v2

3. **History size limit**: Cap synced items per device?
   - **Recommendation**: Sync last 1000 items, configurable

4. **Item retention**: Server-side TTL?
   - **Recommendation**: 90 days default, user configurable

5. **Conflict UI**: Show conflicts to user?
   - **Recommendation**: Auto-resolve silently, log to console

---

## Success Metrics

- ✅ **Security**: Zero plaintext data on server
- ✅ **Reliability**: 99.9% sync success rate
- ✅ **Performance**: < 2 seconds end-to-end sync latency
- ✅ **Battery**: < 5% battery impact on iOS per day
- ✅ **Adoption**: 20% of Maccy users enable sync within 6 months

---

*Document Version*: 1.0
*Last Updated*: 2025-11-12
*Author*: Claude (Anthropic)
