/**
 * Transient authentication challenge state and OpenVPN Access Server CRV1 helpers.
 *
 * Challenge data is intentionally process-memory only. This module does not use
 * files, preferences, profiles, logs, cookies, or response/OTP storage.
 */

import { util } from '@kit.ArkTS';

/** Challenge protocol/source kind. */
export type AuthChallengeKind = 'static' | 'dynamic' | 'cr_text' | 'auth_pending';

/** Short alias for callers that use the protocol name as the type. */
export type ChallengeKind = AuthChallengeKind;

/**
 * A challenge request kept by AuthChallengeManager.
 *
 * `state` is the protocol state identifier when a protocol supplies one. It is
 * not persisted and may contain an Access Server state value for the lifetime
 * of this request only.
 */
export interface AuthChallengeState {
  requestId: string;
  profileUuid?: string;
  source: string;
  kind: AuthChallengeKind;
  challengeText: string;
  echo: boolean;
  responseRequired: boolean;
  expiresAt: number;
  state?: string;
  username?: string;
  flags?: string;
}

/** Input used to create or replace a transient challenge. */
export interface AuthChallengeInput {
  kind: AuthChallengeKind;
  profileUuid?: string;
  source?: string;
  challengeText?: string;
  echo?: boolean;
  responseRequired?: boolean;
  expiresAt?: number;
  ttlMs?: number;
  state?: string;
  username?: string;
  flags?: string;
  requestId?: string;
}

/** Parsed OpenVPN Access Server CRV1 challenge. */
export interface AccessServerCrv1Challenge {
  /** CRV1 flags, for example `R,E`. */
  flags: string;
  /** Access Server state identifier used in the response. */
  state: string;
  /** Alias for state, matching Access Server terminology. */
  stateId: string;
  /** Username decoded from the CRV1 base64 field. */
  username: string;
  /** Human-readable challenge text. */
  challenge: string;
  /** Whether the server requested echoed input (`E`). */
  echo: boolean;
  /** Whether the server requested a response (`R`). */
  responseRequired: boolean;
}

/** Alias retained for callers that prefer the shorter protocol type name. */
export type AccessServerCrv1 = AccessServerCrv1Challenge;

/** Default lifetime for an authentication challenge. */
export const AUTH_CHALLENGE_DEFAULT_TTL_MS: number = 120000;

let requestCounter: number = 0;

function nextRequestId(): string {
  try {
    return util.generateRandomUUID(false);
  } catch (e) {
    // A request id is a correlation id, not an authentication secret. Keep a
    // deterministic fallback for runtimes without the ArkTS UUID helper.
    requestCounter += 1;
    return `auth-${Date.now().toString(36)}-${requestCounter.toString(36)}`;
  }
}

function copyChallenge(value: AuthChallengeState): AuthChallengeState {
  let copy: AuthChallengeState = {
    requestId: value.requestId,
    source: value.source,
    kind: value.kind,
    challengeText: value.challengeText,
    echo: value.echo,
    responseRequired: value.responseRequired,
    expiresAt: value.expiresAt
  };
  if (value.profileUuid !== undefined) {
    copy.profileUuid = value.profileUuid;
  }
  if (value.state !== undefined) {
    copy.state = value.state;
  }
  if (value.username !== undefined) {
    copy.username = value.username;
  }
  if (value.flags !== undefined) {
    copy.flags = value.flags;
  }
  return copy;
}

function isChallengeKind(value: string): boolean {
  return value === 'static' || value === 'dynamic' || value === 'cr_text' || value === 'auth_pending';
}

function isFiniteNumber(value: number): boolean {
  return value === value && value !== Infinity && value !== -Infinity;
}

/**
 * Memory-only challenge manager. Each instance has an independent store;
 * static methods below provide a process-wide convenience manager.
 */
export class AuthChallengeManager {
  static readonly DEFAULT_TTL_MS: number = AUTH_CHALLENGE_DEFAULT_TTL_MS;

  private static readonly shared: AuthChallengeManager = new AuthChallengeManager();
  private readonly challenges: Map<string, AuthChallengeState> = new Map<string, AuthChallengeState>();
  private readonly defaultTtlMs: number;

  constructor(defaultTtlMs: number = AUTH_CHALLENGE_DEFAULT_TTL_MS) {
    if (isFiniteNumber(defaultTtlMs) && defaultTtlMs > 0) {
      this.defaultTtlMs = defaultTtlMs;
    } else {
      this.defaultTtlMs = AUTH_CHALLENGE_DEFAULT_TTL_MS;
    }
  }

  /** Store a challenge and generate a request id unless one is supplied. */
  set(input: AuthChallengeInput): AuthChallengeState {
    if (input === undefined || input === null || !isChallengeKind(input.kind)) {
      throw new Error('Invalid authentication challenge kind');
    }

    this.removeExpired();
    let now = Date.now();
    let requestId = input.requestId === undefined || input.requestId.trim() === '' ?
      nextRequestId() : input.requestId.trim();

    let expiresAt: number;
    if (input.expiresAt !== undefined && isFiniteNumber(input.expiresAt)) {
      expiresAt = input.expiresAt;
    } else {
      let ttl = input.ttlMs;
      if (ttl === undefined || !isFiniteNumber(ttl) || ttl <= 0) {
        ttl = this.defaultTtlMs;
      }
      expiresAt = now + ttl;
    }

    let value: AuthChallengeState = {
      requestId: requestId,
      source: input.source === undefined ? 'unknown' : input.source,
      kind: input.kind,
      challengeText: input.challengeText === undefined ? '' : input.challengeText,
      echo: input.echo === undefined ? false : input.echo,
      responseRequired: input.responseRequired === undefined ? true : input.responseRequired,
      expiresAt: expiresAt
    };
    if (input.profileUuid !== undefined) {
      value.profileUuid = input.profileUuid;
    }
    if (input.state !== undefined) {
      value.state = input.state;
    }
    if (input.username !== undefined) {
      value.username = input.username;
    }
    if (input.flags !== undefined) {
      value.flags = input.flags;
    }

    // Store a private copy so callers cannot mutate manager state through the
    // object returned from set(). An already expired value is not retained.
    if (expiresAt > now) {
      this.challenges.set(requestId, copyChallenge(value));
    } else {
      this.challenges.delete(requestId);
    }
    return copyChallenge(value);
  }

  /** Return a defensive copy, or undefined for a missing/expired request. */
  get(requestId: string): AuthChallengeState | undefined {
    if (requestId === undefined || requestId === null || requestId === '') {
      return undefined;
    }
    let value = this.challenges.get(requestId);
    if (value === undefined) {
      return undefined;
    }
    if (value.expiresAt <= Date.now()) {
      this.challenges.delete(requestId);
      return undefined;
    }
    return copyChallenge(value);
  }

  /** Clear one request, or all requests when no id is supplied. */
  clear(requestId?: string): void {
    if (requestId === undefined) {
      this.challenges.clear();
      return;
    }
    this.challenges.delete(requestId);
  }

  /** Return whether a non-expired request exists. */
  has(requestId: string): boolean {
    return this.get(requestId) !== undefined;
  }

  /** Remove expired entries without exposing their contents. */
  private removeExpired(): void {
    let now = Date.now();
    this.challenges.forEach((value: AuthChallengeState, key: string) => {
      if (value.expiresAt <= now) {
        this.challenges.delete(key);
      }
    });
  }

  // Process-wide convenience API.
  static set(input: AuthChallengeInput): AuthChallengeState {
    return AuthChallengeManager.shared.set(input);
  }

  static get(requestId: string): AuthChallengeState | undefined {
    return AuthChallengeManager.shared.get(requestId);
  }

  static clear(requestId?: string): void {
    AuthChallengeManager.shared.clear(requestId);
  }

  static has(requestId: string): boolean {
    return AuthChallengeManager.shared.has(requestId);
  }
}

function decodeXmlEntities(value: string): string {
  let result = value;
  result = result.replace(/&lt;/gi, '<');
  result = result.replace(/&gt;/gi, '>');
  result = result.replace(/&quot;/gi, '"');
  result = result.replace(/&apos;/gi, '\'');
  result = result.replace(/&#39;/g, '\'');
  result = result.replace(/&amp;/gi, '&');
  return result;
}

function decodeBase64Username(value: string): string | undefined {
  let encoded = value.trim().replace(/-/g, '+').replace(/_/g, '/');
  if (encoded === '') {
    return '';
  }
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(encoded)) {
    return undefined;
  }
  let firstPadding = encoded.indexOf('=');
  if (firstPadding !== -1 && firstPadding < encoded.length - 2 &&
    encoded.substring(firstPadding).indexOf('=') !== 0) {
    return undefined;
  }
  let remainder = encoded.length % 4;
  if (remainder === 1) {
    return undefined;
  }
  if (remainder === 2) {
    encoded += '==';
  } else if (remainder === 3) {
    encoded += '=';
  }
  try {
    let bytes = new util.Base64Helper().decodeSync(encoded);
    return new util.TextDecoder('utf-8').decodeToString(new Uint8Array(bytes));
  } catch (e) {
    return undefined;
  }
}

/**
 * Parse an Access Server CRV1 challenge from a response body.
 *
 * The parser accepts the bare CRV1 record as well as records wrapped in an
 * HTML/XML `<Message>` element (including CDATA and common XML entities):
 * `CRV1:<flags>:<state>:<base64-user>:<challenge>`.
 */
export function parseAccessServerCrv1(raw: string): AccessServerCrv1Challenge | undefined {
  if (raw === undefined || raw === null || raw === '') {
    return undefined;
  }

  let text = decodeXmlEntities(raw);
  text = text.replace(/<!\[CDATA\[/gi, '').replace(/\]\]>/g, '');
  let marker = text.search(/CRV1\s*:/i);
  if (marker === -1) {
    return undefined;
  }

  let candidate = text.substring(marker);
  let closingMessage = candidate.search(/<\s*\/\s*Message\b/i);
  if (closingMessage !== -1) {
    candidate = candidate.substring(0, closingMessage);
  }
  let lineEnd = candidate.search(/[\r\n]/);
  if (lineEnd !== -1) {
    candidate = candidate.substring(0, lineEnd);
  }
  candidate = candidate.trim();
  if (candidate.length < 6) {
    return undefined;
  }

  let prefixEnd = candidate.indexOf(':');
  if (prefixEnd === -1 || candidate.substring(0, prefixEnd).trim().toUpperCase() !== 'CRV1') {
    return undefined;
  }
  let fields = candidate.substring(prefixEnd + 1).split(':');
  if (fields.length < 4) {
    return undefined;
  }

  let flags = fields[0].trim().toUpperCase();
  let state = fields[1].trim();
  let encodedUsername = fields[2].trim();
  let challenge = fields.slice(3).join(':').trim();
  if (state === '' || challenge === '') {
    return undefined;
  }

  let username = decodeBase64Username(encodedUsername);
  if (username === undefined) {
    return undefined;
  }

  return {
    flags: flags,
    state: state,
    stateId: state,
    username: username,
    challenge: challenge,
    echo: flags.indexOf('E') !== -1,
    responseRequired: flags.indexOf('R') !== -1
  };
}

/**
 * Build the Access Server CRV1 response record.
 *
 * Access Server expects the state and response in the empty-flags/empty-user
 * form: `CRV1::<state>::<response>`.
 */
export function buildAccessServerCrv1Response(state: string, response: string): string {
  if (state === undefined || state === null || response === undefined || response === null) {
    return '';
  }
  let normalizedState = state.trim();
  if (normalizedState === '' || /[\r\n:]/.test(normalizedState) || /[\r\n]/.test(response)) {
    return '';
  }
  return `CRV1::${normalizedState}::${response}`;
}
