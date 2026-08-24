import vpnExtension from '@ohos.net.vpnExtension';
import * as ovpnexec from 'libovpnexec.so';
import type { OvpnNativeEvent, OvpnStartResult } from 'libovpnexec.so';
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

export class EngineOptions {
  content: string = '';
  username: string = '';
  password: string = '';
}

class CidrInfo {
  address: string = '';
  prefix: number = 0;
}

export class OvpnEngine {
  private connection?: vpnExtension.VpnConnection;
  private stopped: boolean = false;
  private vpnContext: vpnExtension.VpnExtensionContext;

  constructor(context: vpnExtension.VpnExtensionContext) {
    this.vpnContext = context;
  }

  async start(profile: EngineOptions): Promise<void> {
    this.stopped = false;
    ovpnexec.attach((event: OvpnNativeEvent): void => {
      if (event.type === 'log') {
        VpnStatus.logMessage(LogLevel.DEBUG, `[OpenVPN3] ${event.info}`);
      } else if (event.type === 'event') {
        VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.INFO,
          `[OpenVPN3 event] ${event.name}: ${event.info}`);
        this.applyEventState(event);
      } else if (event.type === 'tun_establish_req') {
        this.establishTun(event.info).catch((err: Error) => {
          console.error(`[OpenVPN3] TUN creation failed: ${err.message}`);
          ovpnexec.resolveTunEstablish(-1);
        });
      } else if (event.type === 'done') {
        VpnStatus.logMessage(event.error ? LogLevel.ERROR : LogLevel.INFO,
          `[OpenVPN3] finished: ${event.name} ${event.info}`);
        VpnStatus.updateStateString('NOPROCESS', event.info === '' ? 'Disconnected' : event.info);
      }
    });

    this.connection = vpnExtension.createVpnConnection(this.vpnContext);
    await this.connection.protectProcessNet();
    let result: OvpnStartResult = ovpnexec.startTunnel(profile);
    if (!result.ok) {
      throw new Error(result.error);
    }
  }

  async stop(): Promise<void> {
    this.stopped = true;
    ovpnexec.stopTunnel();
    if (this.connection !== undefined) {
      try {
        await this.connection.destroy();
      } catch (e) {
        console.warn('[OpenVPN3] destroy TUN failed');
      }
      this.connection = undefined;
    }
  }

  private applyEventState(event: OvpnNativeEvent): void {
    switch (event.name) {
      case 'CONNECTED':
        VpnStatus.updateStateString('CONNECTED', event.info, ConnectionStatus.LEVEL_CONNECTED);
        break;
      case 'AUTH_FAILED':
        VpnStatus.updateStateString('AUTH_FAILED', event.info, ConnectionStatus.LEVEL_AUTH_FAILED);
        break;
      case 'CONNECTING':
      case 'WAITING_FOR_CONNECTION':
        VpnStatus.updateStateString('CONNECTING', event.info, ConnectionStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET);
        break;
      case 'DISCONNECTED':
      case 'EXITING':
        VpnStatus.updateStateString('NOPROCESS', event.info, ConnectionStatus.LEVEL_NOTCONNECTED);
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

    let linkAddresses: Array<vpnExtension.LinkAddress> = [];
    for (let item of addresses) {
      linkAddresses.push({
        address: { address: item.address, family: item.address.indexOf(':') >= 0 ? 2 : 1 },
        prefixLength: item.prefix
      });
    }
    let routeInfos: Array<vpnExtension.RouteInfo> = [];
    for (let item of routes) {
      routeInfos.push({
        interface: '',
        destination: {
          address: { address: item.address, family: item.address.indexOf(':') >= 0 ? 2 : 1 },
          prefixLength: item.prefix
        },
        gateway: { address: '0.0.0.0', family: 1 },
        hasGateway: false,
        isDefaultRoute: item.prefix === 0,
        isExcludedRoute: false
      });
    }
    for (let item of excludedRoutes) {
      routeInfos.push({
        interface: '',
        destination: {
          address: { address: item.address, family: item.address.indexOf(':') >= 0 ? 2 : 1 },
          prefixLength: item.prefix
        },
        gateway: { address: '0.0.0.0', family: 1 },
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
      isIPv6Accepted: addresses.some((item) => item.address.indexOf(':') >= 0),
      isBlocking: true
    };
    if (this.connection === undefined) {
      throw new Error('VPN connection object is not initialized');
    }
    let fd = await this.connection.create(config);
    if (this.stopped) {
      try {
        await this.connection.destroy();
      } catch (e) {
      }
      ovpnexec.resolveTunEstablish(-1);
      return;
    }
    ovpnexec.resolveTunEstablish(fd);
  }

}
