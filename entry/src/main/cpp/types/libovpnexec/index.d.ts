export interface OvpnNativeEvent {
  type: string;
  name: string;
  info: string;
  error: boolean;
  fatal: boolean;
}

export interface OvpnStartOptions {
  content: string;
  username: string;
  password: string;
}

export interface OvpnStartResult {
  ok: boolean;
  error: string;
}

export const attach: (callback: (event: OvpnNativeEvent) => void) => void;
export const startTunnel: (options: OvpnStartOptions) => OvpnStartResult;
export const stopTunnel: () => void;
export const resolveTunEstablish: (fd: number) => void;
