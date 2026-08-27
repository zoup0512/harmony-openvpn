/**
 * Port of de.blinkt.openvpn.core.ConfigParser
 * OpenVPN config file (.ovpn/.conf) parser, faithful port of the Java version.
 */

import { VpnProfile } from './VpnProfile';
import { CIDRIP } from './CIDRIP';
import { Connection, ProxyType } from './Connection';

export class ConfigParseError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'ConfigParseError';
  }
}

enum LineState {
  INITIAL,
  READIN_SINGLE_QUOTE,
  READING_QUOTED,
  READING_UNQUOTED,
  DONE
}

export class ConnResult {
  first: Connection;
  second: Connection[];

  constructor(first: Connection, second: Connection[]) {
    this.first = first;
    this.second = second;
  }
}

export class ConfigParser {
  static readonly CONVERTED_PROFILE: string = 'converted Profile';

  static readonly unsupportedOptions: string[] = ['config', 'tls-server'];

  static readonly ignoreOptions: string[] = [
    'tls-client', 'allow-recursive-routing', 'askpass', 'auth-nocache', 'up', 'down', 'route-up',
    'ipchange', 'route-pre-down', 'auth-user-pass-verify', 'block-outside-dns',
    'client-cert-not-required', 'dhcp-release', 'dhcp-renew', 'dh', 'group', 'ip-win32',
    'ifconfig-nowarn', 'management-hold', 'management', 'management-client',
    'management-query-remote', 'management-query-passwords', 'management-query-proxy',
    'management-external-key', 'management-forget-disconnect', 'management-signal',
    'management-log-cache', 'management-up-down', 'management-client-user',
    'management-client-group', 'pause-exit', 'preresolve', 'plugin', 'machine-readable-output',
    'persist-key', 'push', 'register-dns', 'route-delay', 'route-gateway', 'route-metric',
    'route-method', 'status', 'script-security', 'show-net-up', 'suppress-timestamps',
    'tap-sleep', 'tmp-dir', 'tun-ipv6', 'topology', 'user', 'win-sys'
  ];

  static readonly ignoreOptionsWithArg: string[][] = [
    ['setenv', 'IV_GUI_VER'],
    ['setenv', 'IV_SSO'],
    ['setenv', 'IV_PLAT_VER'],
    ['setenv', 'IV_OPENVPN_GUI_VERSION'],
    ['engine', 'dynamic'],
    ['setenv', 'CLIENT_CERT'],
    ['resolv-retry', '60']
  ];

  static readonly connectionOptions: string[] = [
    'local', 'remote', 'float', 'port', 'connect-retry', 'connect-timeout', 'connect-retry-max',
    'link-mtu', 'tun-mtu', 'tun-mtu-extra', 'fragment', 'mtu-disc', 'local-port', 'remote-port',
    'bind', 'nobind', 'proto', 'http-proxy', 'http-proxy-retry', 'http-proxy-timeout',
    'http-proxy-option', 'socks-proxy', 'socks-proxy-retry', 'http-proxy-user-pass',
    'explicit-exit-notify'
  ];

  private connectionOptionsSet: Set<string> = new Set<string>(ConfigParser.connectionOptions);

  private options: Map<string, string[][]> = new Map<string, string[][]>();
  private meta: Map<string, string[]> = new Map<string, string[]>();
  private authUserPassFile?: string;

  static useEmbbedUserAuth(np: VpnProfile, inlinedata: string): void {
    let data = VpnProfile.getEmbeddedContent(inlinedata);
    let parts = data.split('\n');
    if (parts.length >= 2) {
      np.mUsername = parts[0];
      np.mPassword = parts[1];
    }
  }

  static useEmbbedHttpAuth(c: Connection, inlinedata: string): void {
    let data = VpnProfile.getEmbeddedContent(inlinedata);
    let parts = data.split('\n');
    if (parts.length >= 2) {
      c.mProxyAuthUser = parts[0];
      c.mProxyAuthPassword = parts[1];
      c.mUseProxyAuth = true;
    }
  }

  getAuthUserPassFile(): string {
    return this.authUserPassFile as string;
  }

  parseConfig(lines: string[]): void {
    let optionAliases: Map<string, string> = new Map<string, string>();
    optionAliases.set('server-poll-timeout', 'timeout-connect');

    let lineno = 0;
    let i = 0;
    while (i < lines.length) {
      let line = lines[i];
      i++;
      lineno++;

      if (lineno === 1) {
        if (line.startsWith('PK\u0003\u0004') || line.startsWith('PK\u0007\u0008')) {
          throw new ConfigParseError(
            'Input looks like a ZIP Archive. Import is only possible for OpenVPN config files (.ovpn/.conf)');
        }
        if (line.startsWith('﻿')) {
          line = line.substring(1);
        }
      }

      // Check for OpenVPN Access Server Meta information
      if (line.startsWith('# OVPN_ACCESS_SERVER_')) {
        let metaarg = this.parsemeta(line);
        this.meta.set(metaarg[0], metaarg);
        continue;
      }

      let args = this.parseline(line);
      if (args.length === 0) {
        continue;
      }

      if (args[0].startsWith('--')) {
        args[0] = args[0].substring(2);
      }

      args = this.checkinlinefile(args, lines, i);
      // update consumed position
      i = this.lastInlineIndex;

      let optionname = args[0];
      let alias = optionAliases.get(optionname);
      if (alias !== undefined) {
        optionname = alias;
      }

      let list = this.options.get(optionname);
      if (list === undefined) {
        list = [];
        this.options.set(optionname, list);
      }
      list.push(args);
    }
  }

  private lastInlineIndex: number = 0;

  private parsemeta(line: string): string[] {
    // Java: line.split("#\\sOVPN_ACCESS_SERVER_", 2)[1].split("=", 2)
    let m = line.split(/#\sOVPN_ACCESS_SERVER_/);
    if (m.length < 2) {
      return ['unknownmeta', ''];
    }
    let rest = m[1];
    let idx = rest.indexOf('=');
    if (idx === -1) {
      return [rest];
    }
    return [rest.substring(0, idx), rest.substring(idx + 1)];
  }

  private checkinlinefile(args: string[], lines: string[], startPos: number): string[] {
    this.lastInlineIndex = startPos;
    let arg0 = args[0].trim();
    // Check for <foo>
    if (arg0.startsWith('<') && arg0.endsWith('>')) {
      let argname = arg0.substring(1, arg0.length - 1);
      let inlinefile = VpnProfile.INLINE_TAG;
      let endtag = `</${argname}>`;
      let j = startPos;
      let foundEnd = false;
      while (j < lines.length) {
        let line = lines[j];
        j++;
        if (line.trim() === endtag) {
          foundEnd = true;
          break;
        } else {
          inlinefile += line;
          inlinefile += '\n';
        }
      }
      if (!foundEnd) {
        throw new ConfigParseError(`No endtag </${argname}> for starttag <${argname}> found`);
      }
      if (inlinefile.endsWith('\n')) {
        inlinefile = inlinefile.substring(0, inlinefile.length - 1);
      }
      this.lastInlineIndex = j;
      args = [argname, inlinefile];
    }
    return args;
  }

  private isSpace(c: string): boolean {
    return /\s/.test(c) || c === '\0';
  }

  // adapted openvpn's parse function
  private parseline(line: string): string[] {
    let parameters: string[] = [];
    if (line.length === 0) {
      return parameters;
    }

    let state = LineState.INITIAL;
    let backslash = false;
    let out = '';

    let pos = 0;
    let currentarg = '';

    do {
      let ch: string;
      if (pos < line.length) {
        ch = line.charAt(pos);
      } else {
        ch = '\0';
      }

      if (!backslash && ch === '\\' && state !== LineState.READIN_SINGLE_QUOTE) {
        backslash = true;
      } else {
        if (state === LineState.INITIAL) {
          if (!this.isSpace(ch)) {
            if (ch === ';' || ch === '#') {
              break;
            }
            if (!backslash && ch === '"') {
              state = LineState.READING_QUOTED;
            } else if (!backslash && ch === '\'') {
              state = LineState.READIN_SINGLE_QUOTE;
            } else {
              out = ch;
              state = LineState.READING_UNQUOTED;
            }
          }
        } else if (state === LineState.READING_UNQUOTED) {
          if (!backslash && this.isSpace(ch)) {
            state = LineState.DONE;
          } else {
            out = ch;
          }
        } else if (state === LineState.READING_QUOTED) {
          if (!backslash && ch === '"') {
            state = LineState.DONE;
          } else {
            out = ch;
          }
        } else if (state === LineState.READIN_SINGLE_QUOTE) {
          if (ch === '\'') {
            state = LineState.DONE;
          } else {
            out = ch;
          }
        }

        if (state === LineState.DONE) {
          state = LineState.INITIAL;
          parameters.push(currentarg);
          currentarg = '';
          out = '';
        }

        if (backslash && out !== '') {
          if (!(out === '\\' || out === '"' || this.isSpace(out))) {
            throw new ConfigParseError("Options warning: Bad backslash ('\\') usage");
          }
        }
        backslash = false;
      }

      // store parameter character
      if (out !== '') {
        currentarg += out;
      }
      pos++;
    } while (pos <= line.length);

    return parameters;
  }

  // This method is far too long
  convertProfile(): VpnProfile {
    let noauthtypeset = true;
    let np = new VpnProfile(ConfigParser.CONVERTED_PROFILE);
    // Pull, client, tls-client
    np.clearDefaults();

    if (this.options.has('client') || this.options.has('pull')) {
      np.mUsePull = true;
      this.options.delete('pull');
      this.options.delete('client');
    }

    let secret = this.getOption('secret', 1, 2);
    if (secret !== undefined) {
      np.mAuthenticationType = VpnProfile.TYPE_STATICKEYS;
      noauthtypeset = false;
      np.mUseTLSAuth = true;
      np.mTLSAuthFilename = secret[1];
      if (secret.length === 3) {
        np.mTLSAuthDirection = secret[2];
      }
    }

    let routes = this.getAllOption('route', 1, 4);
    if (routes !== undefined) {
      let routeopt = '';
      let routeExcluded = '';
      for (let route of routes) {
        let netmask = '255.255.255.255';
        let gateway = 'vpn_gateway';

        if (route.length >= 3) {
          netmask = route[2];
        }
        if (route.length >= 4) {
          gateway = route[3];
        }

        let net = route[1];
        let cidr: CIDRIP;
        try {
          cidr = CIDRIP.fromNetmask(net, netmask);
        } catch (e) {
          throw new ConfigParseError(`Could not parse netmask of route ${netmask}`);
        }
        if (gateway === 'net_gateway') {
          routeExcluded += cidr.toString() + ' ';
        } else {
          routeopt += cidr.toString() + ' ';
        }
      }
      np.mCustomRoutes = routeopt;
      np.mExcludedRoutes = routeExcluded;
    }

    let routesV6 = this.getAllOption('route-ipv6', 1, 4);
    if (routesV6 !== undefined) {
      let customIPv6Routes = '';
      for (let route of routesV6) {
        customIPv6Routes += route[1] + ' ';
      }
      np.mCustomRoutesv6 = customIPv6Routes;
    }

    let routeNoPull = this.getOption('route-nopull', 0, 0);
    if (routeNoPull !== undefined) {
      np.mRoutenopull = true;
    }

    // Also recognize tls-auth [inline] direction ...
    let tlsauthoptions = this.getAllOption('tls-auth', 1, 2);
    if (tlsauthoptions !== undefined) {
      for (let tlsauth of tlsauthoptions) {
        if (tlsauth !== undefined) {
          if (tlsauth[1] !== '[inline]') {
            np.mTLSAuthFilename = tlsauth[1];
            np.mUseTLSAuth = true;
          }
          if (tlsauth.length === 3) {
            np.mTLSAuthDirection = tlsauth[2];
          }
        }
      }
    }

    let direction = this.getOption('key-direction', 1, 1);
    if (direction !== undefined) {
      np.mTLSAuthDirection = direction[1];
    }

    let crypts = ['tls-crypt', 'tls-crypt-v2'];
    for (let crypt of crypts) {
      let tlscrypt = this.getOption(crypt, 1, 1);
      if (tlscrypt !== undefined) {
        np.mUseTLSAuth = true;
        np.mTLSAuthFilename = tlscrypt[1];
        np.mTLSAuthDirection = crypt;
      }
    }

    let defgw = this.getAllOption('redirect-gateway', 0, 7);
    if (defgw !== undefined) {
      this.checkRedirectParameters(np, defgw, true);
    }

    let redirectPrivate = this.getAllOption('redirect-private', 0, 5);
    if (redirectPrivate !== undefined) {
      this.checkRedirectParameters(np, redirectPrivate, false);
    }

    let dev = this.getOption('dev', 1, 1);
    let devtype = this.getOption('dev-type', 1, 1);

    if ((devtype !== undefined && devtype[1] === 'tun') ||
      (dev !== undefined && dev[1].startsWith('tun')) ||
      (devtype === undefined && dev === undefined)) {
      // everything okay
    } else {
      throw new ConfigParseError('Sorry. Only tun mode is supported. See the FAQ for more detail');
    }

    let mssfix = this.getOption('mssfix', 0, 2);
    if (mssfix !== undefined) {
      if (mssfix.length >= 2) {
        let v = parseInt(mssfix[1]);
        if (isNaN(v)) {
          throw new ConfigParseError('Argument to --mssfix has to be an integer');
        }
        np.mMssFix = v;
      } else {
        np.mMssFix = 1450; // OpenVPN default size
      }
      // Ignore mtu argument of OpenVPN3 and report error otherwise
      if (mssfix.length >= 3 && mssfix[2] !== 'mtu') {
        throw new ConfigParseError('Second argument to --mssfix unkonwn');
      }
    }

    let tunmtu = this.getOption('tun-mtu', 1, 1);
    if (tunmtu !== undefined) {
      let v = parseInt(tunmtu[1]);
      if (isNaN(v)) {
        throw new ConfigParseError('Argument to --tun-mtu has to be an integer');
      }
      np.mTunMtu = v;
    }

    let mode = this.getOption('mode', 1, 1);
    if (mode !== undefined) {
      if (mode[1] !== 'p2p') {
        throw new ConfigParseError('Invalid mode for --mode specified, need p2p');
      }
    }

    let dhcpoptions = this.getAllOption('dhcp-option', 2, 2);
    if (dhcpoptions !== undefined) {
      for (let dhcpoption of dhcpoptions) {
        let type = dhcpoption[1];
        let arg = dhcpoption[2];
        if (type === 'DOMAIN') {
          np.mSearchDomain = dhcpoption[2];
        } else if (type === 'DNS') {
          np.mOverrideDNS = true;
          if (np.mDNS1 === VpnProfile.DEFAULT_DNS1) {
            np.mDNS1 = arg;
            np.mDNS2 = '';
          } else {
            np.mDNS2 = arg;
          }
        }
      }
    }

    let ifconfig = this.getOption('ifconfig', 2, 2);
    if (ifconfig !== undefined) {
      let cidr: CIDRIP;
      try {
        cidr = CIDRIP.fromNetmask(ifconfig[1], ifconfig[2]);
      } catch (e) {
        throw new ConfigParseError('Could not pase ifconfig IP address');
      }
      np.mIPv4Address = cidr.toString();
    }

    if (this.getOption('remote-random-hostname', 0, 0) !== undefined) {
      np.mUseRandomHostname = true;
    }

    if (this.getOption('float', 0, 0) !== undefined) {
      np.mUseFloat = true;
    }

    if (this.getOption('comp-lzo', 0, 1) !== undefined) {
      np.mUseLzo = true;
    }

    let ncpCiphers = this.getOption('ncp-ciphers', 1, 1);
    let dataCiphers = this.getOption('data-ciphers', 1, 1);
    let cipher = this.getOption('cipher', 1, 1);

    if (cipher !== undefined) {
      np.mCipher = cipher[1];
    }

    if (dataCiphers !== undefined) {
      np.mDataCiphers = dataCiphers[1];
    } else if (ncpCiphers !== undefined) {
      np.mDataCiphers = ncpCiphers[1];
    }

    let tlsCertProfile = this.getOption('tls-cert-profile', 1, 1);
    if (tlsCertProfile !== undefined) {
      let profile = tlsCertProfile[1];
      let choices = ['insecure', 'preferred', 'legacy', 'suiteb'];
      for (let choice of choices) {
        if (choice === profile) {
          np.mTlSCertProfile = profile;
          break;
        }
      }
      if (profile !== np.mTlSCertProfile) {
        throw new ConfigParseError(`Invalid tls-cert-profile '${profile}'`);
      }
    }

    let provider = this.getOption('provider', 1, 9);
    if (provider !== undefined) {
      let providers = provider[1].toLowerCase();
      if (providers === 'legacy:default' || providers === 'default:legacy') {
        np.mUseLegacyProvider = true;
      }
      for (let prov of provider) {
        if ('legacy' === prov.toLowerCase()) {
          np.mUseLegacyProvider = true;
        }
      }
    }

    let compatmode = this.getOption('compat-mode', 1, 1);
    if (compatmode !== undefined) {
      let parts = compatmode[1].split('.');
      if (parts.length < 3) {
        throw new ConfigParseError('Invalid compat-mode version');
      }
      let major = parseInt(parts[0]);
      let minor = parseInt(parts[1]);
      let patch = parseInt(parts[2]);
      if (isNaN(major) || isNaN(minor) || isNaN(patch)) {
        throw new ConfigParseError('Invalid compat-mode version');
      }
      np.mCompatMode = major * 10000 + minor * 100 + patch;
    }

    let auth = this.getOption('auth', 1, 1);
    if (auth !== undefined) {
      np.mAuth = auth[1];
    }

    let ca = this.getOption('ca', 1, 1);
    if (ca !== undefined) {
      np.mCaFilename = ca[1];
    }

    let peerfp = this.getAllOption('peer-fingerprint', 1, 1);
    if (peerfp !== undefined) {
      np.mCheckPeerFingerprint = true;
      for (let fp of peerfp) {
        if (fp[1].startsWith(VpnProfile.INLINE_TAG)) {
          np.mPeerFingerPrints += fp[1].substring(VpnProfile.INLINE_TAG.length) + '\n';
        } else {
          np.mPeerFingerPrints += fp[1] + '\n';
        }
      }
    }

    let cert = this.getOption('cert', 1, 1);
    if (cert !== undefined) {
      np.mClientCertFilename = cert[1];
      np.mAuthenticationType = VpnProfile.TYPE_CERTIFICATES;
      noauthtypeset = false;
    }
    let key = this.getOption('key', 1, 1);
    if (key !== undefined) {
      np.mClientKeyFilename = key[1];
    }

    let pkcs12 = this.getOption('pkcs12', 1, 1);
    if (pkcs12 !== undefined) {
      np.mPKCS12Filename = pkcs12[1];
      np.mAuthenticationType = VpnProfile.TYPE_KEYSTORE;
      noauthtypeset = false;
    }

    let cryptoapicert = this.getOption('cryptoapicert', 1, 1);
    if (cryptoapicert !== undefined) {
      np.mAuthenticationType = VpnProfile.TYPE_KEYSTORE;
      noauthtypeset = false;
    }

    let compatnames = this.getOption('compat-names', 1, 2);
    let nonameremapping = this.getOption('no-name-remapping', 1, 1);
    let tlsremote = this.getOption('tls-remote', 1, 1);
    if (tlsremote !== undefined) {
      np.mRemoteCN = tlsremote[1];
      np.mCheckRemoteCN = true;
      np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE;

      if ((compatnames !== undefined && compatnames.length > 2) || nonameremapping !== undefined) {
        np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING;
      }
    }

    let verifyx509name = this.getOption('verify-x509-name', 1, 2);
    if (verifyx509name !== undefined) {
      np.mRemoteCN = verifyx509name[1];
      np.mCheckRemoteCN = true;
      if (verifyx509name.length > 2) {
        if (verifyx509name[2] === 'name') {
          np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE_RDN;
        } else if (verifyx509name[2] === 'subject') {
          np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE_DN;
        } else if (verifyx509name[2] === 'name-prefix') {
          np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE_RDN_PREFIX;
        } else {
          throw new ConfigParseError(`Unknown parameter to verify-x509-name: ${verifyx509name[2]}`);
        }
      } else {
        np.mX509AuthType = VpnProfile.X509_VERIFY_TLSREMOTE_DN;
      }
    }

    let x509usernamefield = this.getOption('x509-username-field', 1, 1);
    if (x509usernamefield !== undefined) {
      np.mx509UsernameField = x509usernamefield[1];
    }

    let verb = this.getOption('verb', 1, 1);
    if (verb !== undefined) {
      np.mVerb = verb[1];
    }

    if (this.getOption('nobind', 0, 0) !== undefined) {
      np.mNobind = true;
    }

    if (this.getOption('persist-tun', 0, 0) !== undefined) {
      np.mPersistTun = true;
    }

    if (this.getOption('push-peer-info', 0, 0) !== undefined) {
      np.mPushPeerInfo = true;
    }

    let connectretry = this.getOption('connect-retry', 1, 2);
    if (connectretry !== undefined) {
      np.mConnectRetry = connectretry[1];
      if (connectretry.length > 2) {
        np.mConnectRetryMaxTime = connectretry[2];
      }
    }

    let connectretrymax = this.getOption('connect-retry-max', 1, 1);
    if (connectretrymax !== undefined) {
      np.mConnectRetryMax = connectretrymax[1];
    }

    let remotetls = this.getAllOption('remote-cert-tls', 1, 1);
    if (remotetls !== undefined) {
      if (remotetls[0][1] === 'server') {
        np.mExpectTLSCert = true;
      } else {
        this.options.set('remotetls', remotetls);
      }
    }

    let authuser = this.getOption('auth-user-pass', 0, 1);
    if (authuser !== undefined) {
      if (noauthtypeset) {
        np.mAuthenticationType = VpnProfile.TYPE_USERPASS;
      } else if (np.mAuthenticationType === VpnProfile.TYPE_CERTIFICATES) {
        np.mAuthenticationType = VpnProfile.TYPE_USERPASS_CERTIFICATES;
      } else if (np.mAuthenticationType === VpnProfile.TYPE_KEYSTORE) {
        np.mAuthenticationType = VpnProfile.TYPE_USERPASS_KEYSTORE;
      }
      if (authuser.length > 1) {
        if (!authuser[1].startsWith(VpnProfile.INLINE_TAG)) {
          this.authUserPassFile = authuser[1];
        }
        np.mUsername = undefined;
        ConfigParser.useEmbbedUserAuth(np, authuser[1]);
      }
    }

    let staticChallenge = this.getOption('static-challenge', 1, 2);
    if (staticChallenge !== undefined) {
      np.mStaticChallenge = staticChallenge[1];
      np.mStaticChallengeEcho = staticChallenge.length > 2 && staticChallenge[2] === '1';
      this.options.delete('static-challenge');
    }

    let authretry = this.getOption('auth-retry', 1, 1);
    if (authretry !== undefined) {
      if (authretry[1] === 'none') {
        np.mAuthRetry = VpnProfile.AUTH_RETRY_NONE_FORGET;
      } else if (authretry[1] === 'nointeract') {
        np.mAuthRetry = VpnProfile.AUTH_RETRY_NOINTERACT;
      } else if (authretry[1] === 'interact') {
        np.mAuthRetry = VpnProfile.AUTH_RETRY_INTERACT;
      } else {
        throw new ConfigParseError(`Unknown parameter to auth-retry: ${authretry[2]}`);
      }
    }

    let crlfile = this.getOption('crl-verify', 1, 2);
    if (crlfile !== undefined) {
      // If the 'dir' parameter is present just add it as custom option ..
      if (crlfile.length === 3 && crlfile[2] === 'dir') {
        np.mCustomConfigOptions += crlfile.join(' ') + '\n';
      } else {
        np.mCrlFilename = crlfile[1];
      }
    }

    let conns = this.parseConnectionOptions(undefined);
    np.mConnections = conns.second;

    let connectionBlocks = this.getAllOption('connection', 1, 1);
    if (np.mConnections.length > 0 && connectionBlocks !== undefined) {
      throw new ConfigParseError('Using a <connection> block and --remote is not allowed.');
    }

    if (connectionBlocks !== undefined) {
      np.mConnections = [];
      for (let conn of connectionBlocks) {
        let connectionBlockConnection = this.parseConnectionBlock(conn[1], conns.first);
        if (connectionBlockConnection.second.length !== 1) {
          throw new ConfigParseError('A <connection> block must have exactly one remote');
        }
        np.mConnections.push(connectionBlockConnection.second[0]);
      }
    }

    if (this.getOption('remote-random', 0, 0) !== undefined) {
      np.mRemoteRandom = true;
    }

    let protoforce = this.getOption('proto-force', 1, 1);
    if (protoforce !== undefined) {
      let disableUDP: boolean;
      let protoToDisable = protoforce[1];
      if (protoToDisable === 'udp') {
        disableUDP = true;
      } else if (protoToDisable === 'tcp') {
        disableUDP = false;
      } else {
        throw new ConfigParseError(`Unknown protocol ${protoToDisable} in proto-force`);
      }
      for (let conn of np.mConnections) {
        if (conn.mUseUdp === disableUDP) {
          conn.mEnabled = false;
        }
      }
    }

    // Parse OpenVPN Access Server extra
    let asNames = ['PROFILE', 'FRIENDLY_NAME'];
    for (let asNameDirective of asNames) {
      let friendlyname = this.meta.get(asNameDirective);
      if (friendlyname !== undefined && friendlyname.length > 1) {
        np.mName = friendlyname[1];
      }
    }

    let ocusername = this.meta.get('USERNAME');
    if (ocusername !== undefined && ocusername.length > 1) {
      np.mUsername = ocusername[1];
    }

    this.checkIgnoreAndInvalidOptions(np);
    this.fixup(np);

    return np;
  }

  private parseConnectionBlock(connection: string, defaultValues: Connection): ConnResult {
    // Parse a connection block as a new configuration file
    let connectionParser = new ConfigParser();
    let content = connection.substring(VpnProfile.INLINE_TAG.length);
    connectionParser.parseConfig(content.split('\n'));
    return connectionParser.parseConnectionOptions(defaultValues);
  }

  private parseConnectionOptions(connDefault?: Connection): ConnResult {
    let conn: Connection;
    if (connDefault !== undefined && connDefault !== null) {
      conn = connDefault.clone();
    } else {
      conn = new Connection();
    }

    let port = this.getOption('port', 1, 1);
    if (port !== undefined) {
      conn.mServerPort = port[1];
    }

    let rport = this.getOption('rport', 1, 1);
    if (rport !== undefined) {
      conn.mServerPort = rport[1];
    }

    let proto = this.getOption('proto', 1, 1);
    if (proto !== undefined) {
      conn.mUseUdp = ConfigParser.isUdpProto(proto[1]);
    }

    let connectTimeout = this.getOption('connect-timeout', 1, 1);
    if (connectTimeout !== undefined) {
      let v = parseInt(connectTimeout[1]);
      if (isNaN(v)) {
        throw new ConfigParseError(`Argument to connect-timeout (${connectTimeout[1]}) must to be an integer`);
      }
      conn.mConnectTimeout = v;
    }

    let proxy = this.getOption('socks-proxy', 1, 2);
    if (proxy === undefined) {
      proxy = this.getOption('http-proxy', 2, 2);
    }

    if (proxy !== undefined) {
      if (proxy[0] === 'socks-proxy') {
        conn.mProxyType = ProxyType.SOCKS5;
        // socks defaults to 1080, http always sets port
        conn.mProxyPort = '1080';
      } else {
        conn.mProxyType = ProxyType.HTTP;
      }
      conn.mProxyName = proxy[1];
      if (proxy.length >= 3) {
        conn.mProxyPort = proxy[2];
      }
    }

    let httpproxyauthhttp = this.getOption('http-proxy-user-pass', 1, 1);
    if (httpproxyauthhttp !== undefined) {
      ConfigParser.useEmbbedHttpAuth(conn, httpproxyauthhttp[1]);
    }

    // Parse remote config
    let remotes = this.getAllOption('remote', 1, 3);

    let optionsToRemove: string[] = [];
    // Assume that we need custom options if connectionDefault are set or in the connection specific set
    this.options.forEach((value: string[][], key: string) => {
      if (connDefault !== undefined || this.connectionOptionsSet.has(key)) {
        conn.mCustomConfiguration += ConfigParser.getOptionStrings(value);
        optionsToRemove.push(key);
      }
    });
    for (let o of optionsToRemove) {
      this.options.delete(o);
    }

    if (!(conn.mCustomConfiguration === undefined || conn.mCustomConfiguration.trim() === '')) {
      conn.mUseCustomConfig = true;
    }

    // Make remotes empty to simplify code
    if (remotes === undefined) {
      remotes = [];
    }

    let connections: Connection[] = [];
    for (let remote of remotes) {
      let c = conn.clone();
      if (remote.length >= 4) {
        c.mUseUdp = ConfigParser.isUdpProto(remote[3]);
      }
      if (remote.length >= 3) {
        c.mServerPort = remote[2];
      }
      if (remote.length >= 2) {
        c.mServerName = remote[1];
      }
      connections.push(c);
    }

    return new ConnResult(conn, connections);
  }

  private checkRedirectParameters(np: VpnProfile, defgw: string[][], defaultRoute: boolean): void {
    let noIpv4 = false;
    if (defaultRoute) {
      for (let redirect of defgw) {
        for (let i = 1; i < redirect.length; i++) {
          if (redirect[i] === 'block-local') {
            np.mAllowLocalLAN = false;
          } else if (redirect[i] === 'unblock-local') {
            np.mAllowLocalLAN = true;
          } else if (redirect[i] === '!ipv4') {
            noIpv4 = true;
          } else if (redirect[i] === 'ipv6') {
            np.mUseDefaultRoutev6 = true;
          }
        }
      }
    }
    if (defaultRoute && !noIpv4) {
      np.mUseDefaultRoute = true;
    }
  }

  static isUdpProto(proto: string): boolean {
    let isudp: boolean;
    if (proto === 'udp' || proto === 'udp4' || proto === 'udp6') {
      isudp = true;
    } else if (proto === 'tcp-client' || proto === 'tcp' || proto === 'tcp4' ||
      proto.endsWith('tcp4-client') || proto === 'tcp6' || proto.endsWith('tcp6-client')) {
      isudp = false;
    } else {
      throw new ConfigParseError(`Unsupported option to --proto ${proto}`);
    }
    return isudp;
  }

  private checkIgnoreAndInvalidOptions(np: VpnProfile): void {
    for (let option of ConfigParser.unsupportedOptions) {
      if (this.options.has(option)) {
        throw new ConfigParseError(`Unsupported Option ${option} encountered in config file. Aborting`);
      }
    }

    for (let option of ConfigParser.ignoreOptions) {
      this.options.delete(option);
    }

    let customOptions = false;
    this.options.forEach((value: string[][]) => {
      for (let optionsline of value) {
        if (!this.ignoreThisOption(optionsline)) {
          customOptions = true;
        }
      }
    });
    if (customOptions) {
      np.mCustomConfigOptions = '# These options found in the config file do not map to config settings:\n' +
        np.mCustomConfigOptions;
      this.options.forEach((value: string[][]) => {
        np.mCustomConfigOptions += ConfigParser.getOptionStrings(value);
      });
      np.mUseCustomConfig = true;
    }
  }

  ignoreThisOption(option: string[]): boolean {
    for (let ignoreOption of ConfigParser.ignoreOptionsWithArg) {
      if (option.length < ignoreOption.length) {
        continue;
      }
      let ignore = true;
      for (let i = 0; i < ignoreOption.length; i++) {
        if (ignoreOption[i] !== option[i]) {
          ignore = false;
        }
      }
      if (ignore) {
        return true;
      }
    }
    return false;
  }

  static getOptionStrings(option: string[][]): string {
    let custom = '';
    for (let optionsline of option) {
      let ignoreThis = false;
      for (let io of ConfigParser.ignoreOptionsWithArg) {
        if (optionsline.length < io.length) {
          continue;
        }
        let ignore = true;
        for (let i = 0; i < io.length; i++) {
          if (io[i] !== optionsline[i]) {
            ignore = false;
          }
        }
        if (ignore) {
          ignoreThis = true;
          break;
        }
      }
      if (!ignoreThis) {
        // Check if option had been inlined and inline again
        if (optionsline.length === 2 && optionsline[0] === 'extra-certs') {
          custom += VpnProfile.insertFileData(optionsline[0], optionsline[1]);
        } else {
          for (let arg of optionsline) {
            custom += VpnProfile.openVpnEscape(arg) + ' ';
          }
          custom += '\n';
        }
      }
    }
    return custom;
  }

  private fixup(np: VpnProfile): void {
    if (np.mRemoteCN === np.mServerName) {
      np.mRemoteCN = '';
    }
  }

  private getOption(option: string, minarg: number, maxarg: number): string[] | undefined {
    let alloptions = this.getAllOption(option, minarg, maxarg);
    if (alloptions === undefined) {
      return undefined;
    } else {
      return alloptions[alloptions.length - 1];
    }
  }

  private getAllOption(option: string, minarg: number, maxarg: number): string[][] | undefined {
    let args = this.options.get(option);
    if (args === undefined) {
      return undefined;
    }
    for (let optionline of args) {
      if (optionline.length < (minarg + 1) || optionline.length > maxarg + 1) {
        throw new ConfigParseError(
          `Option ${option} has ${optionline.length - 1} parameters, expected between ${minarg} and ${maxarg}`);
      }
    }
    this.options.delete(option);
    return args;
  }
}
