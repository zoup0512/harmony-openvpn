export interface OvpnDynamicChallenge {
  challenge: string;
  echo: boolean;
  responseRequired: boolean;
  stateID: string;
  /** Transient CRV1 cookie; do not persist or log. */
  cookie: string;
}

export interface OvpnNativeEvent {
  type: string;
  name: string;
  info: string;
  error: boolean;
  fatal: boolean;
  dynamicChallenge?: OvpnDynamicChallenge;
}

export interface OvpnStartOptions {
  content: string;
  username: string;
  password: string;
  response?: string;
  /** Transient CRV1 cookie; do not persist or log. */
  dynamicChallengeCookie?: string;
  /** Defaults to "webauth,crtext" when omitted or empty. */
  ssoMethods?: string;
  /** Overall connection timeout in seconds; zero means no timeout. */
  connTimeout?: number;
  /** Defaults to true when omitted. */
  info?: boolean;
}

export interface OvpnStartResult {
  ok: boolean;
  error: string;
}

export interface OvpnTunStats {
  ok: boolean;
  error: string;
  bytesIn: number;
  bytesOut: number;
  packetsIn: number;
  packetsOut: number;
  errorsIn: number;
  errorsOut: number;
}

export const attach: (callback: (event: OvpnNativeEvent) => void) => void;
export const startTunnel: (options: OvpnStartOptions) => OvpnStartResult;
export const stopTunnel: () => void;
export const getTunStats: () => OvpnTunStats;
export const respondCrText: (options: { response: string }) => OvpnStartResult;
export const resolveTunEstablish: (fd: number) => void;
