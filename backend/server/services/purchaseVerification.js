const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { z } = require('zod');
const {
  APPLE_BUNDLE_ID,
  APPLE_ISSUER_ID,
  APPLE_KEY_ID,
  APPLE_PRIVATE_KEY,
  APPLE_PRIVATE_KEY_BASE64,
} = require('../config/env');

const purchaseVerificationSchema = z.object({
  platform: z.enum(['ios', 'android']),
  productId: z.string().min(1).max(100),
  transactionId: z.string().min(1).max(255),
  receiptData: z.string().optional(),
});

function normalizeConfigValue(value) {
  return String(value || '')
    .replace(/\r\n/g, '\n')
    .trim();
}

function hasOuterWhitespace(value) {
  const raw = String(value || '');
  return raw.trim() !== raw;
}

function maskValue(value, prefix = 4, suffix = 4) {
  const normalized = normalizeConfigValue(value);
  if (!normalized) return '<missing>';
  if (normalized.length <= prefix + suffix) {
    return `${normalized.slice(0, 1)}***${normalized.slice(-1)}`;
  }
  return `${normalized.slice(0, prefix)}***${normalized.slice(-suffix)}`;
}

function looksLikeUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(normalizeConfigValue(value));
}

function looksLikeAppleKeyId(value) {
  return /^[A-Z0-9]{10}$/.test(normalizeConfigValue(value));
}

function fingerprint(value) {
  const normalized = normalizeConfigValue(value);
  if (!normalized) return null;
  return crypto.createHash('sha256').update(normalized).digest('hex').slice(0, 16);
}

function getApplePrivateKey() {
  if (APPLE_PRIVATE_KEY) {
    return normalizeConfigValue(APPLE_PRIVATE_KEY.replace(/\\n/g, '\n'));
  }
  if (APPLE_PRIVATE_KEY_BASE64) {
    return normalizeConfigValue(Buffer.from(normalizeConfigValue(APPLE_PRIVATE_KEY_BASE64), 'base64').toString('utf8'));
  }
  return '';
}

function getNormalizedAppleConfig() {
  const issuerId = normalizeConfigValue(APPLE_ISSUER_ID);
  const keyId = normalizeConfigValue(APPLE_KEY_ID);
  const bundleId = normalizeConfigValue(APPLE_BUNDLE_ID);
  const privateKey = getApplePrivateKey();

  return {
    issuerId,
    keyId,
    bundleId,
    privateKey,
  };
}

function getPrivateKeyHeaderType(privateKey) {
  if (privateKey.includes('BEGIN EC PRIVATE KEY')) {
    return 'BEGIN EC PRIVATE KEY';
  }
  if (privateKey.includes('BEGIN PRIVATE KEY')) {
    return 'BEGIN PRIVATE KEY';
  }
  return 'UNKNOWN_OR_INVALID';
}

function decodeJwtSection(token, index) {
  const parts = String(token || '').split('.');
  if (parts.length < index + 1) return null;
  try {
    return JSON.parse(Buffer.from(parts[index], 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

function buildAppleJwtDebugSummary() {
  try {
    const token = generateAppleServerApiToken();
    const header = decodeJwtSection(token, 0) || {};
    const payload = decodeJwtSection(token, 1) || {};

    return {
      generated: true,
      header: {
        alg: header.alg || null,
        kid: maskValue(header.kid || ''),
        typ: header.typ || null,
      },
      payload: {
        iss: maskValue(payload.iss || ''),
        aud: payload.aud || null,
        bid: payload.bid || null,
        iat: payload.iat || null,
        exp: payload.exp || null,
      },
      ttlSeconds:
        typeof payload.iat === 'number' && typeof payload.exp === 'number'
          ? payload.exp - payload.iat
          : null,
    };
  } catch (error) {
    return {
      generated: false,
      error: readableError(error, 'JWT_GENERATION_FAILED'),
    };
  }
}

function getAppleVerificationWarnings(summary) {
  const warnings = [];

  if (!summary.issuerIdLooksLikeUuid) {
    warnings.push('APPLE_ISSUER_ID format invalid');
  }
  if (summary.issuerIdHasWhitespace) {
    warnings.push('APPLE_ISSUER_ID has leading or trailing whitespace');
  }
  if (!summary.keyIdLooksValidFormat) {
    warnings.push('APPLE_KEY_ID format invalid');
  }
  if (summary.keyIdHasWhitespace) {
    warnings.push('APPLE_KEY_ID has leading or trailing whitespace');
  }
  if (summary.bundleIdHasWhitespace) {
    warnings.push('APPLE_BUNDLE_ID has leading or trailing whitespace');
  }
  if (!summary.privateKeyDecoded) {
    warnings.push('APPLE private key did not decode into a valid PEM');
  }
  if (summary.jwt.generated && typeof summary.jwt.ttlSeconds === 'number' && summary.jwt.ttlSeconds > 1200) {
    warnings.push('JWT ttlSeconds exceeds Apple guidance');
  }

  return warnings;
}

function getAppleVerificationConfigSummary() {
  const { issuerId, keyId, bundleId, privateKey } = getNormalizedAppleConfig();
  const summary = {
    issuerIdPresent: Boolean(issuerId),
    issuerIdMasked: maskValue(issuerId),
    issuerIdLooksLikeUuid: looksLikeUuid(issuerId),
    issuerIdHasWhitespace: hasOuterWhitespace(APPLE_ISSUER_ID),
    keyIdPresent: Boolean(keyId),
    keyIdMasked: maskValue(keyId),
    keyIdLooksValidFormat: looksLikeAppleKeyId(keyId),
    keyIdHasWhitespace: hasOuterWhitespace(APPLE_KEY_ID),
    bundleId: bundleId || '<missing>',
    bundleIdNormalized: bundleId || '<missing>',
    bundleIdHasWhitespace: hasOuterWhitespace(APPLE_BUNDLE_ID),
    privateKeySource: APPLE_PRIVATE_KEY_BASE64
      ? 'base64'
      : APPLE_PRIVATE_KEY
        ? 'plain'
        : 'missing',
    privateKeyDecoded: Boolean(
      privateKey &&
      (privateKey.includes('BEGIN PRIVATE KEY') || privateKey.includes('BEGIN EC PRIVATE KEY'))
    ),
    privateKeyHeaderType: getPrivateKeyHeaderType(privateKey),
    privateKeyFingerprint: fingerprint(privateKey),
    isConfigured: Boolean(
      issuerId &&
      keyId &&
      bundleId &&
      privateKey
    ),
  };

  summary.jwt = buildAppleJwtDebugSummary();
  summary.warnings = getAppleVerificationWarnings(summary);
  return summary;
}

function hasAppleVerificationConfig() {
  return getAppleVerificationConfigSummary().isConfigured;
}

function generateAppleServerApiToken() {
  const { issuerId, keyId, bundleId, privateKey } = getNormalizedAppleConfig();
  return jwt.sign(
    {
      iss: issuerId,
      iat: Math.floor(Date.now() / 1000),
      exp: Math.floor(Date.now() / 1000) + 300,
      aud: 'appstoreconnect-v1',
      bid: bundleId,
    },
    privateKey,
    {
      algorithm: 'ES256',
      header: {
        alg: 'ES256',
        kid: keyId,
        typ: 'JWT',
      },
    }
  );
}

function decodeJWSPayload(jws) {
  const parts = jws.split('.');
  if (parts.length < 2) {
    throw new Error('Malformed JWS response from Apple');
  }
  return JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
}

function readableError(error, fallback) {
  if (!error) return fallback;
  if (typeof error === 'string' && error.trim()) return error;
  if (error instanceof Error && error.message.trim()) return error.message;
  return fallback;
}

function appleLookupFailureMessage({ environment, status, body }, debugSummary = getAppleVerificationConfigSummary()) {
  const normalizedBody = typeof body === 'string' && body.trim()
    ? body.trim()
    : 'EMPTY_APPLE_ERROR_BODY';

  if (status === 401) {
    return `${environment}:401:APPLE_AUTH_FAILED(kid=${debugSummary.keyIdMasked}, issuerUuid=${debugSummary.issuerIdLooksLikeUuid}, bundle=${debugSummary.bundleIdNormalized}, ttl=${debugSummary.jwt?.ttlSeconds ?? 'unknown'}, keyType=${debugSummary.privateKeyHeaderType})`;
  }

  return `${environment ?? 'unknown'}:${status ?? 'no-status'}:${normalizedBody}`;
}

async function fetchAppleTransaction(transactionId, environment) {
  const baseUrl =
    environment === 'sandbox'
      ? 'https://api.storekit-sandbox.itunes.apple.com'
      : 'https://api.storekit.itunes.apple.com';

  let token;
  try {
    token = generateAppleServerApiToken();
  } catch (error) {
    return {
      ok: false,
      status: 500,
      body: `APPLE_API_TOKEN_GENERATION_FAILED: ${readableError(error, 'Token could not be generated')}`,
    };
  }

  let response;
  try {
    response = await fetch(`${baseUrl}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`, {
      method: 'GET',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
    });
  } catch (error) {
    return {
      ok: false,
      status: 502,
      body: `APPLE_TRANSACTION_LOOKUP_EXCEPTION: ${readableError(error, 'Apple lookup request failed')}`,
    };
  }

  if (!response.ok) {
    const errorText = await response.text();
    return {
      ok: false,
      environment,
      status: response.status,
      body: errorText || 'EMPTY_APPLE_ERROR_BODY',
    };
  }

  return {
    ok: true,
    environment,
    data: await response.json(),
  };
}

async function verifyApplePurchase(data) {
  if (!hasAppleVerificationConfig()) {
    return {
      isValid: false,
      reason: 'APPLE_VERIFICATION_NOT_CONFIGURED',
    };
  }
  try {
    const debugSummary = getAppleVerificationConfigSummary();
    const productionResult = await fetchAppleTransaction(data.transactionId, 'production');
    const sandboxResult = productionResult.ok
      ? null
      : await fetchAppleTransaction(data.transactionId, 'sandbox');
    const result = productionResult.ok ? productionResult : sandboxResult;

    if (!result?.ok) {
      return {
        isValid: false,
        reason: 'APPLE_TRANSACTION_LOOKUP_FAILED',
        details: [
          productionResult ? appleLookupFailureMessage(productionResult, debugSummary) : null,
          sandboxResult ? appleLookupFailureMessage(sandboxResult, debugSummary) : null,
        ].filter(Boolean).join(' | '),
      };
    }

    const signedTransactionInfo = result.data?.signedTransactionInfo;
    if (!signedTransactionInfo) {
      return {
        isValid: false,
        reason: 'APPLE_SIGNED_TRANSACTION_MISSING',
      };
    }

    const payload = decodeJWSPayload(signedTransactionInfo);
    const productMatches = payload.productId === data.productId;
    const transactionMatches = String(payload.transactionId) === String(data.transactionId);
    const bundleMatches = payload.bundleId === getNormalizedAppleConfig().bundleId;

    if (!productMatches || !transactionMatches || !bundleMatches) {
      return {
        isValid: false,
        reason: 'APPLE_TRANSACTION_MISMATCH',
        details: `expected bundle=${getNormalizedAppleConfig().bundleId}, got bundle=${payload.bundleId}, expected product=${data.productId}, got product=${payload.productId}`,
        payload,
      };
    }

    return {
      isValid: true,
      platform: 'ios',
      productId: payload.productId,
      transactionId: String(payload.transactionId),
      environment: payload.environment || 'production',
      rawPayload: payload,
    };
  } catch (error) {
    return {
      isValid: false,
      reason: 'APPLE_VERIFICATION_EXCEPTION',
      details: readableError(error, 'Unknown Apple verification exception'),
    };
  }
}

async function verifyPurchaseWithStore(payload) {
  const data = purchaseVerificationSchema.parse(payload);

  if (data.platform === 'ios') {
    return verifyApplePurchase(data);
  }

  return {
    isValid: false,
    reason: 'ANDROID_VERIFICATION_NOT_IMPLEMENTED',
  };
}

async function runAppleLookupDebug(transactionId) {
  const normalizedTransactionId = normalizeConfigValue(transactionId);
  const debug = {
    config: getAppleVerificationConfigSummary(),
    lookup: null,
  };

  if (!normalizedTransactionId) {
    return debug;
  }

  const productionResult = await fetchAppleTransaction(normalizedTransactionId, 'production');
  const sandboxResult = productionResult.ok
    ? null
    : await fetchAppleTransaction(normalizedTransactionId, 'sandbox');

  debug.lookup = {
    transactionIdMasked: maskValue(normalizedTransactionId, 6, 4),
    production: productionResult
      ? {
          ok: productionResult.ok,
          status: productionResult.status ?? 200,
          body: productionResult.ok ? null : productionResult.body ?? null,
        }
      : null,
    sandbox: sandboxResult
      ? {
          ok: sandboxResult.ok,
          status: sandboxResult.status ?? 200,
          body: sandboxResult.ok ? null : sandboxResult.body ?? null,
        }
      : null,
  };

  return debug;
}

module.exports = {
  getAppleVerificationConfigSummary,
  runAppleLookupDebug,
  verifyPurchaseWithStore,
  purchaseVerificationSchema,
};
