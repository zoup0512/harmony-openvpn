/**
 * Port of de.blinkt.openvpn.core.Connection
 */

export enum ProxyType {
  NONE,
  HTTP,
  SOCKS5,
  ORBOT
}

export class Connection {
  static readonly CONNECTION_DEFAULT_TIMEOUT: number = 120;

  mServerName: string = 'openvpn.example.com';
  mServerPort: string = '1194';
  mUseUdp: boolean = true;
  mCustomConfiguration: string = '';
  mUseCustomConfig: boolean = false;
  mEnabled: boolean = true;
  mConnectTimeout: number = 0;
  mProxyType: ProxyType = ProxyType.NONE;
  mProxyName: string = 'proxy.example.com';
  mProxyPort: string = '8080';
  mUseProxyAuth: boolean = false;
  mProxyAuthUser?: string;
  mProxyAuthPassword?: string;

  clone(): Connection {
    let c = new Connection();
    c.mServerName = this.mServerName;
    c.mServerPort = this.mServerPort;
    c.mUseUdp = this.mUseUdp;
    c.mCustomConfiguration = this.mCustomConfiguration;
    c.mUseCustomConfig = this.mUseCustomConfig;
    c.mEnabled = this.mEnabled;
    c.mConnectTimeout = this.mConnectTimeout;
    c.mProxyType = this.mProxyType;
    c.mProxyName = this.mProxyName;
    c.mProxyPort = this.mProxyPort;
    c.mUseProxyAuth = this.mUseProxyAuth;
    c.mProxyAuthUser = this.mProxyAuthUser;
    c.mProxyAuthPassword = this.mProxyAuthPassword;
    return c;
  }

  usesExtraProxyOptions(): boolean {
    return this.mUseCustomConfig && this.mCustomConfiguration.indexOf('http-proxy-option ') !== -1;
  }

  isOnlyRemote(): boolean {
    return this.mCustomConfiguration === '' || !this.mUseCustomConfig;
  }

  getTimeout(): number {
    if (this.mConnectTimeout <= 0) {
      return Connection.CONNECTION_DEFAULT_TIMEOUT;
    }
    return this.mConnectTimeout;
  }

  getConnectionBlock(isOpenVPN3: boolean, serverNameOverride?: string): string {
    let cfg = '';
    let serverName = serverNameOverride === undefined || serverNameOverride === '' ?
      this.mServerName : serverNameOverride;

    // Server Address
    cfg += 'remote ';
    cfg += serverName;
    cfg += ' ';
    cfg += this.mServerPort;
    if (this.mUseUdp) {
      cfg += ' udp\n';
    } else {
      cfg += ' tcp-client\n';
    }

    if (this.mConnectTimeout !== 0) {
      cfg += ` connect-timeout  ${this.mConnectTimeout}\n`;
    }

    // OpenVPN 2.x manages proxy connection via management interface
    if ((isOpenVPN3 || this.usesExtraProxyOptions()) && this.mProxyType === ProxyType.HTTP) {
      cfg += `http-proxy ${this.mProxyName} ${this.mProxyPort}\n`;
      if (this.mUseProxyAuth) {
        cfg += '<http-proxy-user-pass>\n';
        cfg += `${this.mProxyAuthUser ? this.mProxyAuthUser : ''}\n`;
        cfg += `${this.mProxyAuthPassword ? this.mProxyAuthPassword : ''}\n`;
        cfg += '</http-proxy-user-pass>\n';
      }
    }
    if (this.usesExtraProxyOptions() && this.mProxyType === ProxyType.SOCKS5) {
      cfg += `socks-proxy ${this.mProxyName} ${this.mProxyPort}\n`;
    }

    if (this.mCustomConfiguration !== '' && this.mUseCustomConfig) {
      cfg += this.mCustomConfiguration;
      cfg += '\n';
    }

    return cfg;
  }

  static proxyTypeToString(t: ProxyType): string {
    switch (t) {
      case ProxyType.NONE:
        return 'NONE';
      case ProxyType.HTTP:
        return 'HTTP';
      case ProxyType.SOCKS5:
        return 'SOCKS5';
      case ProxyType.ORBOT:
        return 'ORBOT';
      default:
        return 'NONE';
    }
  }

  static proxyTypeFromString(t: string): ProxyType {
    switch (t) {
      case 'HTTP':
        return ProxyType.HTTP;
      case 'SOCKS5':
        return ProxyType.SOCKS5;
      case 'ORBOT':
        return ProxyType.ORBOT;
      default:
        return ProxyType.NONE;
    }
  }

  toJson(): Record<string, Object> {
    let o: Record<string, Object> = {
      'mServerName': this.mServerName,
      'mServerPort': this.mServerPort,
      'mUseUdp': this.mUseUdp,
      'mCustomConfiguration': this.mCustomConfiguration,
      'mUseCustomConfig': this.mUseCustomConfig,
      'mEnabled': this.mEnabled,
      'mConnectTimeout': this.mConnectTimeout,
      'mProxyType': Connection.proxyTypeToString(this.mProxyType),
      'mProxyName': this.mProxyName,
      'mProxyPort': this.mProxyPort,
      'mUseProxyAuth': this.mUseProxyAuth
    };
    if (this.mProxyAuthUser !== undefined) {
      o['mProxyAuthUser'] = this.mProxyAuthUser;
    }
    if (this.mProxyAuthPassword !== undefined) {
      o['mProxyAuthPassword'] = this.mProxyAuthPassword;
    }
    return o;
  }

  static fromJson(o: Record<string, Object>): Connection {
    let c = new Connection();
    let serverName = o['mServerName'];
    c.mServerName = typeof serverName === 'string' ? serverName : '';
    c.mServerPort = (o['mServerPort'] as string) ?? '1194';
    c.mUseUdp = (o['mUseUdp'] as boolean) ?? true;
    c.mCustomConfiguration = (o['mCustomConfiguration'] as string) ?? '';
    c.mUseCustomConfig = (o['mUseCustomConfig'] as boolean) ?? false;
    c.mEnabled = (o['mEnabled'] as boolean) ?? true;
    c.mConnectTimeout = (o['mConnectTimeout'] as number) ?? 0;
    c.mProxyType = Connection.proxyTypeFromString((o['mProxyType'] as string) ?? 'NONE');
    c.mProxyName = (o['mProxyName'] as string) ?? 'proxy.example.com';
    c.mProxyPort = (o['mProxyPort'] as string) ?? '8080';
    c.mUseProxyAuth = (o['mUseProxyAuth'] as boolean) ?? false;
    c.mProxyAuthUser = o['mProxyAuthUser'] as string;
    c.mProxyAuthPassword = o['mProxyAuthPassword'] as string;
    return c;
  }
}
