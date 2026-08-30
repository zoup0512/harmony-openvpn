import vpnExtension from '@ohos.net.vpnExtension';
import * as ovpnexec from 'libovpnexec.so';
import type { OvpnNativeEvent, OvpnStartResult, OvpnTunStats } from 'libovpnexec.so';
import { AuthChallengeManager, parseAccessServerCrv1 } from '../core/AuthChallenge';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';
import { VpnStatus } from '../core/VpnStatus';
import { LogLevel, ConnectionStatus } from '../core/LogItem';

interface TunRequest {
  addresses?: string;
  routes?: string;
  excludeRoutes?: string;
  dnsServers?: string;
  searchDomains?: string;
  mtu?: number;
  rerouteGw?: boolean;
}

class NativeDynamicChallenge {
  challenge: string = '';
  echo: boolean = false;
  responseRequired: boolean = false;
  stateID: string = '';
  cookie: string = '';
}

interface NativeDynamicChallengeEvent extends OvpnNativeEvent {
  dynamicChallenge?: NativeDynamicChallenge;
}

class CrTextResponseOptions {
  response: string = '';
}

export class EngineOptions {
  content: string = '';
  username: string = '';
  password: string = '';
  response: string = '';
  dynamicChallengeCookie: string = '';
  ssoMethods: string = '';
  connTimeout: number = 120;
  info: boolean = false;
}

class CidrInfo {
  address: string = '';
  prefix: number = 0;
}

class DynamicChallengeDetails {
  challenge: string = '';
  echo: boolean = false;
  responseRequired: boolean = false;
  stateIdPresent: boolean = false;
  cookiePresent: boolean = false;
  structured: boolean = false;
}

export class OvpnEngine {
  private connection?: vpnExtension.VpnConnection;
  private stopped: boolean = false;
  private preserveChallengeOnDone: boolean = false;
  private vpnContext: vpnExtension.VpnExtensionContext;
  private onDone?: () => void;
  private statsTimer: number = -1;

  constructor(context: vpnExtension.VpnExtensionContext, onDone?: () => void) {
    this.vpnContext = context;
    this.onDone = onDone;
  }

  async start(profile: EngineOptions): Promise<void> {
    this.stopped = false;
    ovpnexec.attach((event: OvpnNativeEvent): void => {
      if (event.type === 'log') {
        VpnStatus.logMessage(LogLevel.DEBUG, `[OpenVPN3] ${event.info}`);
      } else if (event.type === 'event') {
        this.handleNativeEvent(event);
      } else if (event.type === 'tun_establish_req') {
        this.establishTun(event.info).catch((err: Error) => {
          console.error(`[OpenVPN3] TUN creation failed: ${err.message}`);
          ovpnexec.resolveTunEstablish(-1);
        });
      } else if (event.type === 'done') {
        let finishedInfo: string = this.preserveChallengeOnDone ? 'authentication challenge pending' : event.info;
        VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.INFO,
          `[OpenVPN3] finished: ${event.name} ${finishedInfo}`);
        this.stopStatsPolling();
        if (this.preserveChallengeOnDone) {
          this.preserveChallengeOnDone = false;
          return;
        }
        AuthChallengeManager.clear();
        // Keep the first authentication failure reason as the terminal status.
        // OpenVPN3 may report DISCONNECTED/EXITING and a final connect status
        // after AUTH_FAILED; those messages are usually generic or empty.
        if (!this.isAuthenticationFailureState()) {
          VpnStatus.updateStateString('NOPROCESS', event.info === '' ? 'Disconnected' : event.info);
        }
        // The core stopped itself (server disconnect, transport error, auth
        // failure): nobody calls stop() for this engine, so the system VPN
        // connection must be destroyed here. Leaving it alive keeps the TUN
        // registered and the status bar VPN icon shows a disconnected tunnel.
        this.destroyVpnConnection();
        if (this.onDone !== undefined) {
          this.onDone();
        }
      }
    });

    this.connection = vpnExtension.createVpnConnection(this.vpnContext);
    await this.connection.protectProcessNet();
    let result: OvpnStartResult = ovpnexec.startTunnel(profile);
    if (!result.ok) {
      throw new Error(result.error);
    }
    this.startStatsPolling();
  }

  respondCrText(response: string): void {
    let options = new CrTextResponseOptions();
    options.response = response;
    let result: OvpnStartResult = ovpnexec.respondCrText(options);
    if (!result.ok) {
      throw new Error(result.error);
    }
    this.preserveChallengeOnDone = false;
    AuthChallengeManager.clear();
    VpnController.clearPendingAuthChallenge();
  }

  async stop(): Promise<void> {
    this.stopped = true;
    this.preserveChallengeOnDone = false;
    this.stopStatsPolling();
    ovpnexec.stopTunnel();
    AuthChallengeManager.clear();
    await this.destroyVpnConnection();
  }

  /**
   * Destroy the system-side VPN connection (TUN) owned by this engine and
   * drop the reference. Harmless when no TUN was ever established (failure
   * during authentication).
   */
  private async destroyVpnConnection(): Promise<void> {
    let conn = this.connection;
    this.connection = undefined;
    if (conn === undefined) {
      return;
    }
    VpnStatus.logMessage(LogLevel.DEBUG, 'Destroying system VPN connection (TUN teardown).');
    try {
      await conn.destroy();
    } catch (e) {
      // No TUN exists yet — nothing to tear down.
      VpnStatus.logMessage(LogLevel.DEBUG, 'TUN destroy found no active VPN connection (expected before connect).');
    }
  }

  private startStatsPolling(): void {
    this.stopStatsPolling();
    this.statsTimer = setInterval(() => {
      if (this.stopped) {
        return;
      }
      try {
        let stats: OvpnTunStats = ovpnexec.getTunStats();
        if (stats.ok) {
          VpnStatus.updateByteCount(stats.bytesIn, stats.bytesOut);
        }
      } catch (e) {
        VpnStatus.logMessage(LogLevel.DEBUG, '[OpenVPN3] failed to read TUN statistics');
      }
    }, 1000) as number;
  }

  private stopStatsPolling(): void {
    if (this.statsTimer !== -1) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
    }
  }

  private handleNativeEvent(event: OvpnNativeEvent): void {
    if (event.name === 'DYNAMIC_CHALLENGE') {
      this.handleDynamicChallenge(event);
      return;
    }
    if (event.name === 'INFO') {
      this.handleInfoEvent(event);
      return;
    }
    VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.INFO,
      `[OpenVPN3 event] ${event.name}: ${this.eventInfoForLog(event)}`);
    this.applyEventState(event);
  }

  private eventInfoForLog(event: OvpnNativeEvent): string {
    if (event.name === 'SESSION_EXPIRED') {
      return 'Authentication session expired';
    }
    return event.info;
  }

  private handleDynamicChallenge(event: OvpnNativeEvent): void {
    let details = this.readDynamicChallenge(event);
    this.preserveChallengeOnDone = true;
    AuthChallengeManager.set({
      kind: 'dynamic',
      source: 'openvpn3:DYNAMIC_CHALLENGE',
      challengeText: details.challenge,
      echo: details.echo,
      responseRequired: details.responseRequired,
      flags: `structured=${details.structured},stateIdPresent=${details.stateIdPresent},` +
        `cookiePresent=${details.cookiePresent}`
    });
    let nativeEvent = event as NativeDynamicChallengeEvent;
    if (nativeEvent.dynamicChallenge !== undefined) {
      let pending = new PendingAuthChallenge();
      pending.uuid = VpnStatus.getLastConnectedVPNProfile();
      pending.kind = 'dynamic';
      pending.challenge = details.challenge;
      pending.echo = details.echo;
      pending.responseRequired = details.responseRequired;
      pending.cookie = nativeEvent.dynamicChallenge.cookie;
      pending.expiresAt = Date.now() + 120000;
      VpnController.writePendingAuthChallenge(pending);
    }

    VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.WARNING,
      `[OpenVPN3 event] DYNAMIC_CHALLENGE: ${this.challengeSummaryText(details)}`);
    // The challenge text is shown to the user in the dialog anyway; log it
    // (truncated) so captures reveal what the server actually asked for.
    if (details.challenge !== '') {
      let text = details.challenge.length > 120 ?
        details.challenge.substring(0, 117) + '...' : details.challenge;
      VpnStatus.logMessage(LogLevel.INFO, `[OpenVPN3] challenge text: ${text}`);
    }
    VpnStatus.updateStateString('USER_INPUT', 'Waiting for dynamic authentication challenge response',
      ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT);
  }

  private readDynamicChallenge(event: OvpnNativeEvent): DynamicChallengeDetails {
    let nativeEvent = event as NativeDynamicChallengeEvent;
    let details = new DynamicChallengeDetails();
    let structured = nativeEvent.dynamicChallenge;
    if (structured !== undefined) {
      details.challenge = structured.challenge;
      details.echo = structured.echo;
      details.responseRequired = structured.responseRequired;
      details.stateIdPresent = structured.stateID !== '';
      details.cookiePresent = structured.cookie !== '';
      details.structured = true;
      return details;
    }
    if (event.info !== '') {
      let parsed = parseAccessServerCrv1(event.info);
      if (parsed !== undefined) {
        details.challenge = parsed.challenge;
        details.echo = parsed.echo;
        details.responseRequired = parsed.responseRequired;
        details.stateIdPresent = parsed.stateId !== '';
        details.cookiePresent = true;
      } else {
        details.cookiePresent = true;
      }
    }
    return details;
  }

  private challengeSummaryText(details: DynamicChallengeDetails): string {
    return `structured=${details.structured}, challengePresent=${details.challenge !== ''}, ` +
      `echo=${details.echo}, responseRequired=${details.responseRequired}, ` +
      `stateIdPresent=${details.stateIdPresent}, cookiePresent=${details.cookiePresent}`;
  }

  private handleInfoEvent(event: OvpnNativeEvent): void {
    if (!event.info.startsWith('CR_TEXT:')) {
      VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.INFO,
        `[OpenVPN3 event] INFO: ${event.info}`);
      this.applyEventState(event);
      return;
    }
    let prompt: string = event.info.substring('CR_TEXT:'.length);
    let responseApiAvailable: boolean = true;
    this.preserveChallengeOnDone = true;
    AuthChallengeManager.set({
      kind: 'cr_text',
      source: 'openvpn3:INFO',
      challengeText: prompt,
      echo: false,
      responseRequired: true
    });
    let pending = new PendingAuthChallenge();
    pending.uuid = VpnStatus.getLastConnectedVPNProfile();
    pending.kind = 'cr_text';
    pending.challenge = prompt;
    pending.echo = false;
    pending.responseRequired = true;
    pending.expiresAt = Date.now() + 120000;
    VpnController.writePendingAuthChallenge(pending);
    VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.WARNING,
      `[OpenVPN3 event] INFO CR_TEXT: responseApiAvailable=${responseApiAvailable}, promptPresent=${prompt !== ''}`);
    VpnStatus.updateStateString('USER_INPUT', 'Waiting for text authentication challenge response',
      ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT);
  }

  private isAuthenticationFailureState(): boolean {
    return VpnStatus.lastState === 'AUTH_FAILED' || VpnStatus.lastState === 'SESSION_EXPIRED';
  }

  private applyEventState(event: OvpnNativeEvent): void {
    if (event.name === 'AUTH_PENDING') {
      AuthChallengeManager.set({
        kind: 'auth_pending',
        source: 'openvpn3:AUTH_PENDING',
        challengeText: '',
        responseRequired: false,
        ttlMs: 120000
      });
    }
    switch (event.name) {
      case 'CONNECTED':
        this.preserveChallengeOnDone = false;
        AuthChallengeManager.clear();
        VpnStatus.updateStateString('CONNECTED', event.info, ConnectionStatus.LEVEL_CONNECTED);
        break;
      case 'AUTH_FAILED':
        this.preserveChallengeOnDone = false;
        AuthChallengeManager.clear();
        VpnStatus.updateStateString('AUTH_FAILED', event.info === '' ? 'Authentication failed' : event.info,
          ConnectionStatus.LEVEL_AUTH_FAILED);
        break;
      case 'CONNECTING':
      case 'WAITING_FOR_CONNECTION':
        VpnStatus.updateStateString('CONNECTING', event.info, ConnectionStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET);
        break;
      case 'WAIT':
      case 'RECONNECTING':
        VpnStatus.updateStateString(event.name, event.info, ConnectionStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET);
        break;
      case 'AUTH_PENDING':
        this.preserveChallengeOnDone = true;
        VpnStatus.updateStateString(event.name, event.info, ConnectionStatus.LEVEL_CONNECTING_SERVER_REPLIED);
        break;
      case 'GET_CONFIG':
        VpnStatus.updateStateString(event.name, event.info, ConnectionStatus.LEVEL_CONNECTING_SERVER_REPLIED);
        break;
      case 'SESSION_EXPIRED':
        this.preserveChallengeOnDone = false;
        AuthChallengeManager.clear();
        VpnStatus.updateStateString('SESSION_EXPIRED', 'Authentication session expired',
          ConnectionStatus.LEVEL_AUTH_FAILED);
        break;
      case 'CONNECTION_TIMEOUT':
      case 'INACTIVE_TIMEOUT':
      case 'TRANSPORT_ERROR':
      case 'TUN_ERROR':
      case 'TUN_SETUP_FAILED':
      case 'PROXY_ERROR':
      case 'CERT_VERIFY_FAIL':
      case 'CLIENT_HALT':
      case 'CLIENT_SETUP':
        this.preserveChallengeOnDone = false;
        AuthChallengeManager.clear();
        if (!this.isAuthenticationFailureState()) {
          VpnStatus.updateStateString('NOPROCESS', event.info === '' ? event.name : event.info,
            ConnectionStatus.LEVEL_NOTCONNECTED);
        }
        break;
      case 'DISCONNECTED':
      case 'EXITING':
        // openvpn3 always follows a dynamic challenge with DISCONNECTED +
        // done (the auth attempt ended, the user has not answered yet).
        // Keep preserveChallengeOnDone so the done handler does not wipe the
        // session credentials the OTP round depends on, and keep the
        // USER_INPUT status instead of flipping to NOPROCESS.
        AuthChallengeManager.clear();
        if (!this.isAuthenticationFailureState() && !this.preserveChallengeOnDone) {
          VpnStatus.updateStateString('NOPROCESS', event.info, ConnectionStatus.LEVEL_NOTCONNECTED);
        }
        break;
      default:
        break;
    }
  }

  private parseCidrs(value: string | undefined): Array<CidrInfo> {
    let result: Array<CidrInfo> = [];
    if (value === undefined || value === '') {
      return result;
    }
    for (let item of value.split(',')) {
      let parts = item.split('/');
      if (parts.length === 0 || parts[0] === '') {
        continue;
      }
      let prefix = parts.length > 1 ? Number(parts[1]) : 32;
      if (isNaN(prefix)) {
        prefix = 32;
      }
      let cidr = new CidrInfo();
      cidr.address = parts[0];
      cidr.prefix = prefix;
      result.push(cidr);
    }
    return result;
  }

  private async establishTun(json: string): Promise<void> {
    let request = JSON.parse(json) as TunRequest;
    let addresses = this.parseCidrs(request.addresses);
    let routes = this.parseCidrs(request.routes);
    let excludedRoutes = this.parseCidrs(request.excludeRoutes);
    if (addresses.length === 0) {
      throw new Error('OpenVPN3 did not provide a TUN address');
    }
    VpnStatus.logMessage(LogLevel.DEBUG,
      `TUN request: addresses=${request.addresses ?? ''}, routes=${request.routes ?? ''}, ` +
      `excludeRoutes=${request.excludeRoutes ?? ''}, dns=${request.dnsServers ?? ''}, ` +
      `searchDomains=${request.searchDomains ?? ''}, mtu=${request.mtu ?? 0}, ` +
      `rerouteGw=${request.rerouteGw === true}`);

    let linkAddresses: Array<vpnExtension.LinkAddress> = [];
    for (let item of addresses) {
      linkAddresses.push({
        address: { address: item.address, family: item.address.indexOf(':') >= 0 ? 2 : 1 },
        prefixLength: item.prefix
      });
    }
    // An IPv6 route on an IPv4-only TUN would make create() fail; the core
    // normally does not request v6 routes without a v6 address, this filter
    // just makes that guarantee explicit.
    let ipv6Accepted = addresses.some((item) => item.address.indexOf(':') >= 0);
    let routeInfos: Array<vpnExtension.RouteInfo> = [];
    for (let item of routes) {
      let isV6 = item.address.indexOf(':') >= 0;
      if (isV6 && !ipv6Accepted) {
        continue;
      }
      routeInfos.push({
        interface: '',
        destination: {
          address: { address: item.address, family: isV6 ? 2 : 1 },
          prefixLength: item.prefix
        },
        gateway: { address: isV6 ? '::' : '0.0.0.0', family: isV6 ? 2 : 1 },
        hasGateway: false,
        isDefaultRoute: item.prefix === 0,
        isExcludedRoute: false
      });
    }
    for (let item of excludedRoutes) {
      let isV6 = item.address.indexOf(':') >= 0;
      if (isV6 && !ipv6Accepted) {
        continue;
      }
      routeInfos.push({
        interface: '',
        destination: {
          address: { address: item.address, family: isV6 ? 2 : 1 },
          prefixLength: item.prefix
        },
        gateway: { address: isV6 ? '::' : '0.0.0.0', family: isV6 ? 2 : 1 },
        hasGateway: false,
        isDefaultRoute: item.prefix === 0,
        isExcludedRoute: true
      });
    }

    let dnsAddresses = request.dnsServers === undefined || request.dnsServers === ''
      ? [] : request.dnsServers.split(',').filter((value: string) => value !== '');
    let searchDomains = request.searchDomains === undefined || request.searchDomains === ''
      ? [] : request.searchDomains.split(',').filter((value: string) => value !== '');
    let config: vpnExtension.VpnConfig = {
      addresses: linkAddresses,
      routes: routeInfos,
      dnsAddresses: dnsAddresses,
      searchDomains: searchDomains,
      mtu: request.mtu !== undefined && request.mtu > 0 ? request.mtu : 1400,
      isIPv4Accepted: true,
      isIPv6Accepted: ipv6Accepted,
      isBlocking: true
    };
    // Capture the connection object: a concurrent stop() nulls this.connection
    // while create() below is still in flight, and the just-created TUN must
    // stay reachable so the stopped branch below can tear it down.
    let conn = this.connection;
    if (conn === undefined) {
      throw new Error('VPN connection object is not initialized');
    }
    // A reconnect re-runs the whole builder sequence; destroy the TUN left
    // over from the previous session before creating the new one.
    try {
      await conn.destroy();
    } catch (e) {
      // no TUN exists on the first connect
    }
    let fd = await conn.create(config);
    if (this.stopped) {
      // stop() ran while create() was pending; its destroy() found no TUN and
      // this one must not leak (status bar VPN icon would outlive the tunnel).
      try {
        await conn.destroy();
      } catch (e) {
      }
      ovpnexec.resolveTunEstablish(-1);
      return;
    }
    VpnStatus.logMessage(LogLevel.INFO, `TUN established (fd=${fd}, ${routeInfos.length} routes).`);
    ovpnexec.resolveTunEstablish(fd);
  }

}
