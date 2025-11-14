# Maccy E2E Encrypted Sync - Setup Guide

Complete guide to setting up end-to-end encrypted clipboard synchronization between your Mac and iOS devices.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Backend Setup (Cloudflare Workers)](#backend-setup)
4. [macOS App Setup](#macos-app-setup)
5. [iOS App Setup](#ios-app-setup)
6. [Security Best Practices](#security-best-practices)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

---

## Overview

### What is E2E Encrypted Sync?

Maccy's sync feature allows you to access your Mac's clipboard history on your iPhone or iPad. All clipboard data is encrypted on your Mac before transmission, ensuring that:

- ✅ **The server never sees your data** - Only encrypted blobs are stored
- ✅ **Keys never leave your devices** - Encryption keys are stored in device Keychains
- ✅ **You control your data** - Self-hosted backend on Cloudflare's free tier

### Architecture

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│             │         │                  │         │             │
│  macOS App  │◄───────►│ Cloudflare       │◄───────►│  iOS App    │
│  (Primary)  │  HTTPS  │ Worker + D1      │  HTTPS  │  (Viewer)   │
│             │         │ (Encrypted Data) │         │             │
└─────────────┘         └──────────────────┘         └─────────────┘
      │                                                      │
      │                                                      │
      ▼                                                      ▼
┌─────────────┐                                     ┌─────────────┐
│  Keychain   │                                     │  Keychain   │
│ Master Key  │                                     │ Master Key  │
└─────────────┘                                     └─────────────┘
```

**Components:**
1. **Cloudflare Worker**: Stateless API backend handling encrypted data
2. **D1 Database**: SQLite database storing encrypted clipboard items
3. **macOS App**: Primary device generating and syncing clipboard items
4. **iOS App**: Viewer app for accessing clipboard on mobile
5. **Keychain**: Secure storage for encryption keys on both platforms

---

## Prerequisites

### For Backend (Cloudflare Workers)

- Cloudflare account (free tier sufficient)
- [Bun](https://bun.sh) v1.0+ installed
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/)

### For macOS App

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later

### For iOS App

- iOS 16.0 or later
- Xcode 15.0 or later
- iPhone or iPad with camera (for QR scanning)

---

## Backend Setup

### Step 1: Install Bun and Wrangler

```bash
# Install Bun
curl -fsSL https://bun.sh/install | bash

# Install Wrangler
npm install -g wrangler
```

### Step 2: Login to Cloudflare

```bash
cd backend
wrangler login
```

This will open your browser for authentication.

### Step 3: Create D1 Database

```bash
bun run db:create
```

**Output:**
```
✅ Successfully created DB 'maccy-sync-db'
   Database ID: abc123def456...
```

Copy the **Database ID** from the output.

### Step 4: Update Configuration

Edit `backend/wrangler.toml` and replace the `database_id`:

```toml
[[d1_databases]]
binding = "DB"
database_name = "maccy-sync-db"
database_id = "abc123def456..."  # ← Replace with your DB ID
```

### Step 5: Run Migrations

```bash
# For local development
bun run db:migrate

# For production
bun run db:migrate:prod
```

### Step 6: Test Locally (Optional)

```bash
bun run dev
```

Access the health check at http://localhost:8787/health

### Step 7: Deploy to Production

```bash
bun run deploy
```

**Output:**
```
✨ Deployment complete
   URL: https://maccy-sync-backend.your-subdomain.workers.dev
```

**Save this URL** - you'll need it for the macOS app setup.

### Step 8: Verify Deployment

```bash
curl https://maccy-sync-backend.your-subdomain.workers.dev/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "maccy-sync-backend",
  "version": "1.0.0",
  "timestamp": 1699999999999
}
```

---

## macOS App Setup

### Step 1: Build the App

```bash
# Clone the repository
git clone https://github.com/p0deje/Maccy.git
cd Maccy

# Open in Xcode
open Maccy.xcodeproj
```

### Step 2: Build and Run

1. Select your Mac as the build target
2. Build the project (⌘B)
3. Run the app (⌘R)

### Step 3: Open Sync Settings

1. Click the Maccy menu bar icon
2. Select **Preferences** (⌘,)
3. Navigate to the **Sync** tab

### Step 4: Configure Sync

1. Enter your Cloudflare Worker URL:
   ```
   https://maccy-sync-backend.your-subdomain.workers.dev
   ```

2. Click **Generate QR Code**

   This will:
   - Generate a 256-bit master encryption key
   - Create a new sync group
   - Generate a unique device ID
   - Store the key securely in macOS Keychain

3. A QR code will appear - **keep this window open** for the next step

### Step 5: Verify Sync

1. Toggle **Enable Sync** to ON
2. Copy something to your clipboard
3. Wait 30 seconds (default sync interval)
4. Check the Sync Status - it should show "Synced X items"

**Sync is now active on your Mac! ✅**

---

## iOS App Setup

### Step 1: Build the iOS App

```bash
cd MaccyViewer
open MaccyViewer.xcodeproj
```

### Step 2: Configure Signing

1. Select the **MaccyViewer** target
2. Go to **Signing & Capabilities**
3. Select your Apple Developer team
4. Xcode will automatically create a bundle ID

### Step 3: Build and Deploy

**Option A: Run on Simulator**
1. Select an iPhone simulator
2. Build and run (⌘R)

**Option B: Run on Physical Device**
1. Connect your iPhone via USB
2. Select your device
3. Build and run (⌘R)

**Option C: TestFlight (Recommended)**
1. Archive the app (Product → Archive)
2. Upload to App Store Connect
3. Add to TestFlight
4. Install on your iPhone via TestFlight app

### Step 4: Pair Your Device

1. Open **Maccy Viewer** on your iPhone
2. Tap **Scan QR Code to Get Started**
3. Allow camera access
4. Point your camera at the QR code from the macOS app

**The pairing process:**
- Scans the QR code containing:
  - Sync group ID
  - Master encryption key (base64)
  - API endpoint URL
  - Primary device ID
- Stores the key in iOS Keychain
- Registers the iOS device with the backend
- Immediately starts syncing

### Step 5: Browse Your Clipboard

After pairing, you'll see:
- ✅ All clipboard items from your Mac
- 🔍 Search functionality
- 📋 Tap any item to view details
- ✂️ Swipe right to copy to iOS clipboard

---

## Security Best Practices

### Key Management

#### ✅ DO:
- Generate a new QR code for each device you want to pair
- Keep the QR code window open only while pairing
- Store the QR code screenshot securely if you need to re-pair
- Use a secure password manager to store backup keys

#### ❌ DON'T:
- Share QR codes via insecure channels (email, messaging apps)
- Display QR codes in public places or on streams
- Store QR codes unencrypted in cloud storage
- Reuse QR codes if a device is compromised

### Network Security

#### TLS Only
- The app enforces HTTPS for all connections
- Certificate validation is automatic via URLSession

#### Rate Limiting
- 100 requests per minute per device
- 1000 requests per hour per sync group
- Prevents abuse and DoS attacks

### Device Revocation

**If you lose a device:**

1. On Mac, go to **Sync Settings**
2. Click **Load Devices**
3. Identify the lost device
4. Click **Clear Sync Data** to revoke all devices
5. Re-pair remaining devices with a new QR code

**This ensures:**
- Old devices cannot decrypt new clipboard items
- Old encryption key is no longer valid
- Fresh start with a new master key

### Data Retention

**Server-side:**
- Encrypted items are stored indefinitely by default
- Consider implementing TTL (time-to-live) on the backend
- Delete old items regularly via the API

**Client-side:**
- Keys are stored in platform Keychains (not UserDefaults)
- Keys are marked non-synchronizable (won't sync via iCloud)
- Keychain accessibility: `afterFirstUnlock` (available when device is unlocked)

---

## Troubleshooting

### Backend Issues

#### Database not found

**Symptoms:**
```
Error: D1_ERROR: no such table: encrypted_items
```

**Solution:**
```bash
cd backend
bun run db:migrate:prod
```

#### Deployment fails

**Symptoms:**
```
Error: Could not deploy worker
```

**Solution:**
1. Check you're logged in: `wrangler whoami`
2. Verify database ID in `wrangler.toml`
3. Try: `wrangler d1 list` to see your databases

### macOS App Issues

#### "Failed to generate QR code"

**Causes:**
- Invalid API endpoint URL
- Network connectivity issues

**Solution:**
1. Verify URL format: `https://your-worker.workers.dev`
2. Test endpoint: `curl https://your-worker.workers.dev/health`
3. Check firewall settings

#### "Sync failed: Unauthorized"

**Causes:**
- Auth token expired or invalid
- Device was revoked

**Solution:**
1. Go to Sync Settings
2. Click **Clear Sync Data**
3. Generate a new QR code
4. Re-pair devices

#### "Rate limit exceeded"

**Causes:**
- Too many sync requests
- Multiple devices syncing simultaneously

**Solution:**
1. Increase sync interval in settings (e.g., 5 minutes)
2. Wait for rate limit to reset (shown in error message)
3. Adjust rate limits in `backend/wrangler.toml`

### iOS App Issues

#### Camera not working

**Symptoms:**
- Black screen when scanning QR
- "Camera Access Required" message

**Solution:**
1. Go to iOS Settings → Privacy → Camera
2. Enable camera access for Maccy Viewer
3. Restart the app

#### "Invalid QR code data"

**Causes:**
- Incorrect QR code
- Corrupted scan

**Solution:**
1. Ensure good lighting when scanning
2. Hold camera steady
3. Re-generate QR code on Mac

#### No clipboard items appearing

**Causes:**
- Sync hasn't run yet
- Network connectivity issues
- Decryption errors

**Solution:**
1. Pull down to refresh
2. Check Settings → Sync Status
3. Verify "Last Sync" timestamp
4. Check device is connected to internet

### Encryption Issues

#### "Decryption failed"

**Causes:**
- Mismatched encryption keys
- Corrupted data
- Version incompatibility

**Solution:**
1. Clear sync data on all devices
2. Start fresh with new QR code pairing
3. Ensure all apps are latest version

---

## FAQ

### General

**Q: Is my data really end-to-end encrypted?**

A: Yes. All clipboard content is encrypted on your Mac using ChaCha20-Poly1305 AEAD before transmission. The server only stores encrypted blobs + nonces. Without the master key (which never leaves your devices), the data is unreadable.

**Q: Can Cloudflare see my clipboard data?**

A: No. Cloudflare Workers receive only encrypted data. Even if Cloudflare were compromised, attackers would only see random encrypted bytes without the decryption key.

**Q: What happens if I lose my Mac?**

A: Your iOS device will continue to have access to already-synced items (they're decrypted and cached locally). However, new items won't sync. You'll need to set up sync again from another Mac or device.

### Technical

**Q: What encryption algorithm is used?**

A: ChaCha20-Poly1305, an Authenticated Encryption with Associated Data (AEAD) cipher. It provides both confidentiality and integrity protection.

**Q: How are encryption keys generated?**

A: Using `SecRandomCopyBytes` (macOS) or `CryptoKit`'s secure random number generator, which uses the system's cryptographically secure random source.

**Q: Can I use my own backend instead of Cloudflare?**

A: Yes! The backend is standard TypeScript. You can deploy it to any platform supporting:
- Node.js or Bun runtime
- SQLite database (or adapt to PostgreSQL/MySQL)
- HTTPS endpoint

Just change the API endpoint URL in the app settings.

**Q: Why ChaCha20-Poly1305 instead of AES-GCM?**

A: ChaCha20-Poly1305 is:
- Faster on mobile devices without AES hardware acceleration
- More resistant to timing attacks
- Approved by IETF (RFC 8439)
- Used by major protocols (TLS 1.3, WireGuard, Signal)

**Q: How is the master key exchanged?**

A: Via QR code containing a JSON payload with the base64-encoded key. This is an ephemeral exchange - the QR code should be displayed briefly and only in a trusted environment.

### Privacy

**Q: What data does the server collect?**

A: The server stores:
- Encrypted clipboard items (unreadable without key)
- Device IDs (UUIDs, no PII)
- Timestamps (for sync logic)
- Auth tokens (random strings)

The server does NOT collect:
- Device names
- IP addresses (Cloudflare may log these)
- User identifiers
- Analytics or telemetry

**Q: Is any data sent to third parties?**

A: No. The app only communicates with your Cloudflare Worker endpoint. No analytics, crash reporting, or third-party SDKs are included.

**Q: Can I audit the security?**

A: Yes! All code is open source:
- Backend: `backend/src/`
- macOS encryption: `Maccy/Sync/EncryptionService.swift`
- iOS encryption: `MaccyViewer/Services/SyncService.swift`

### Cost

**Q: How much does this cost?**

A: For typical usage (1-10 devices, moderate clipboard activity):

**Cloudflare Free Tier:**
- 100,000 requests/day
- 10 D1 databases
- 5GB D1 storage
- **Total: $0/month**

**Heavy Usage (>100k requests/day):**
- $5/month base (Workers Paid plan)
- $0.50/million requests after free tier
- $0.75/GB D1 storage
- **Estimated: $5-10/month**

**Q: What happens if I exceed free tier limits?**

A: Cloudflare will send you an email notification. Your Worker will continue to function, but you'll be charged for overage at the rates above.

### Compatibility

**Q: Does this work with macOS clipboard history?**

A: Yes! It syncs Maccy's clipboard history, which includes:
- Text (plain, rich, HTML)
- Images (PNG, JPEG, HEIC, TIFF)
- Files (paths)
- Mixed content

**Q: What iOS versions are supported?**

A: iOS 16.0 and later. The app uses:
- SwiftUI lifecycle
- async/await concurrency
- CryptoKit

**Q: Can I sync between multiple Macs?**

A: Currently, the architecture is designed for one primary Mac (source) and multiple iOS viewers. Multi-Mac bidirectional sync would require conflict resolution enhancements.

Future enhancement planned in v2.

---

## Next Steps

### Recommended Configuration

For optimal experience:

1. **macOS:**
   - Sync interval: 30 seconds
   - History size: 200 items (default)
   - Enable sync: ON

2. **iOS:**
   - Sync interval: 1 minute (longer to save battery)
   - Background refresh: OFF (pull-to-refresh instead)

3. **Backend:**
   - Rate limits: Default (100/min, 1000/hour)
   - Item retention: 90 days (requires custom script)

### Advanced Features (Planned)

- 🔄 Bidirectional sync (Mac ↔ Mac, iOS ↔ Mac)
- 📱 Background sync on iOS
- 🗜️ Compression for large items
- 🔔 Push notifications for new items
- 📊 Sync statistics dashboard
- 🌐 Browser extension

### Contributing

Contributions welcome! See:
- Main repo: https://github.com/p0deje/Maccy
- Architecture doc: `SYNC_ARCHITECTURE.md`
- Backend README: `backend/README.md`

---

## Support

- **Issues**: https://github.com/p0deje/Maccy/issues
- **Discussions**: https://github.com/p0deje/Maccy/discussions
- **Security**: Report via GitHub Security Advisories

---

## License

Same as Maccy - MIT License

Copyright (c) 2024 Alex Rodionov

---

**You're all set! 🎉**

Your clipboard is now securely synced across your devices.

For questions or issues, please open a GitHub issue.
