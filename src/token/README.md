# ZST Token Module

This directory contains the implementation of the Zig Secure Token (ZST) module.

## Overview

ZST is a JWT-inspired token format with PASETO-style safety and built-in O(1) revocation. It uses XChaCha20-Poly1305 for authenticated encryption and BLAKE2b for key derivation.

## Files

| File | Purpose |
|------|---------|
| `src/token/zst.zig` | Core ZST sign/verify/decode logic |
| `src/token/claims.zig` | JSON claims serialization |
| `src/token/errors.zig` | Error types (ZstExpiredError, etc.) |
| `src/token/xchacha20.zig` | XChaCha20-Poly1305 implementation |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ZST Module                                                │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  sign(claims, key, options) → token_string            │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │  verify(token, key, options) → claims               │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │  decode(token) → header_info                          │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │  generateKey(length?) → Buffer                        │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Claims (sub, aud, exp, rev, iat, jti, iss, nbf)    │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │  Header (ver, typ, mode)                              │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │  Error Classes (ZstExpiredError, etc.)                │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Crypto Primitives                                    │ │
│  │  ├─ XChaCha20-Poly1305 (encrypt/decrypt)            │ │
│  │  ├─ BLAKE2b KDF (domain separation)                  │ │
│  │  └─ Random bytes (nonce generation)                  │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Security Design

### Why XChaCha20-Poly1305?

| Cipher | Nonce Size | Max Messages | Random Nonce Safe? |
|--------|-----------|-------------|-------------------|
| AES-256-GCM | 96-bit | ~2^32 | ❌ No |
| ChaCha20-Poly1305 | 96-bit | ~2^32 | ❌ No |
| **XChaCha20-Poly1305** | **192-bit** | **~2^64** | **✅ Yes** |

XChaCha20's 192-bit nonce makes random nonce collisions statistically impossible — critical for a stateless token library.

### Why BLAKE2b KDF?

Instead of using the raw key for encryption, a subkey is derived:

```zig
enc_key = BLAKE2b("zst-v1-local-encryption" || master_key)
```

Benefits:
- Same master key can derive different subkeys for different purposes
- Future versions can change KDF without breaking key format
- Defense in depth

### Why `rev` Counter Instead of Blocklists?

| Approach | Storage | Check Time | Granularity |
|----------|---------|-----------|-------------|
| Blocklist (jti) | O(n) tokens | O(n) scan | Per-token |
| Short expiry | None | O(1) | Time-based |
| `rev` counter | O(1) integer | O(1) compare | Per-user, per-time |

`rev` gives "logout everywhere" for free. No need to store individual token IDs.

## Implementation Phases

### Phase 1: Zig Core — Crypto Primitives

1. **XChaCha20-Poly1305** (`src/token/xchacha20.zig`)
   - Quarter round, double round, HChaCha20, XChaCha20
   - RFC 8439 test vectors
   - Nonce reuse demonstration

2. **BLAKE2b KDF** (`src/crypto/blake2b.zig`)
   - Domain separation for different purposes
   - 256-bit output for encryption

### Phase 2: Zig Core — Token Module

1. **Claims** (`src/token/claims.zig`)
   - JSON serialization without allocator
   - Required fields validation (sub, aud, exp, rev)

2. **Error Types** (`src/token/errors.zig`)
   - `ZstExpiredError`, `ZstRevokedError`, etc.

3. **ZST Core** (`src/token/zst.zig`)
   - `sign()`: encrypt claims + package into token
   - `verify()`: decrypt + validate claims
   - `decode()`: header only (no verification)
   - `generateKey()`: cryptographically secure key generation

### Phase 3: N-API Integration

1. Add ZST exports to `src/napi.zig`
2. Create `zst` namespace in `index.ts`
3. Add TypeScript definitions

### Phase 4: Benchmark & Polish

1. Performance benchmarks vs jsonwebtoken
2. Memory pressure tests
3. Documentation and examples

## API

```typescript
import { zst } from 'zig-crypto';

const secret = zst.generateKey(); // 32 bytes

// Sign
const token = zst.sign(
  { sub: 'user_123', aud: 'api.example.com', exp: Date.now()/1000 + 3600, rev: 5 },
  secret,
  { expiresIn: '1h', audience: 'api.example.com' }
);

// Verify
const claims = zst.verify(token, secret, {
  audience: 'api.example.com',
  currentRev: 5,
});

// Decode (no verification - debugging only)
const info = zst.decode(token);
```

## Security Considerations

### Key Management

- **Minimum key size**: 32 bytes (256 bits) enforced
- **Key derivation**: BLAKE2b with domain separation
- **Random generation**: `std.crypto.random` or OS-specific CSPRNG

### Token Format

```
zst_v1.local.<header_b64>.<nonce_b64>.<ciphertext_b64>.<tag_b64>
```

Parts:
- `zst_v1.local.`: Version and mode prefix
- `header_b64`: `{"ver":"1","typ":"ZST","mode":"local"}`
- `nonce_b64`: XChaCha20-Poly1305 nonce (192 bits)
- `ciphertext_b64`: Encrypted claims JSON
- `tag_b64`: Poly1305 authentication tag (128 bits)

### Revocation Pattern

```typescript
// Database schema
interface User {
  _id: string;
  rev: number;  // Monotonic counter
}

// Login — issue token at current rev
const user = await db.users.findOne({ _id: 'user_123' });
const token = zst.sign({ sub: user._id }, secret, {
  expiresIn: '7d',
  audience: 'api.example.com',
  rev: user.rev,
});

// Verify — check against current rev
const decoded = zst.verify(token, secret, {
  audience: 'api.example.com',
  currentRev: user.rev,
});

// Logout everywhere — bump rev
await db.users.updateOne(
  { _id: 'user_123' },
  { $inc: { rev: 1 } }
);
// All tokens with old rev are now invalid
```

## Error Handling

All ZST errors extend `ZstError`:

```typescript
class ZstError extends Error {
  name: 'ZstError';
}

class ZstExpiredError extends ZstError {
  name: 'ZstExpiredError';
  expiredAt: Date;
}

class ZstRevokedError extends ZstError {
  name: 'ZstRevokedError';
  // tokenRev: number;
  // currentRev: number;
}
```

## Testing

Run tests with:

```bash
zig test src/token/zst.zig
zig test src/token/claims.zig
zig test src/token/errors.zig
zig test src/token/xchacha20.zig
```

All tests pass (39 tests total).

## Future Plans

- `public` mode (signed, not encrypted) for debugging
- Key rotation via `kid` header
- Asymmetric mode (Ed25519)
- Benchmarks vs `jsonwebtoken`

## References

- [RFC 8439: ChaCha20 and Poly1305](https://tools.ietf.org/html/rfc8439)
- [draft-irtf-cfrg-xchacha: XChaCha20](https://tools.ietf.org/html/draft-irtf-cfrg-xchacha)
- [PASETO](https://paseto.io) — Token format design
- [jsonwebtoken](https://github.com/auth0/node-jsonwebtoken) — API compatibility
