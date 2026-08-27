/**
 * Port of de.blinkt.openvpn.VpnProfile (data model part).
 * Serialization uses explicit JSON instead of Java object serialization.
 */

import { Connection, ProxyType } from './Connection';
import { CIDRIP } from './CIDRIP';
import { util } from '@kit.ArkTS';

export enum ProfileError {
  NO_ERROR = 0,
  NO_KEYSTORE_CERT_SELECTED = 1,
  NO_CA_CERT_SELECTED = 2,
  DEPRECATED_TLS_REMOTE = 3,
  IPV4_FORMAT_ERROR = 4,
  CUSTOM_ROUTE_FORMAT_ERROR = 5,
  MISSING_TLSAUTH = 6,
  MISSING_CERTIFICATES = 7,
  REMOTE_NO_SERVER_SELECTED = 8,
  OPENVPN3_NOSTATICKEYS = 9,
  OPENVPN3_PKCS12 = 10,
  OPENVPN3_SOCKSPROXY = 11,
  NO_ORBOTFOUND = 12,
  ERROR_ORBOT_AND_PROXY_OPTIONS = 13,
  BF_CBC_REQUIRES_LEGACY = 14
}

export class ChangeLogEntry {
  time: number;
  message: string;

  constructor(time: number, message: string) {
    this.time = time;
    this.message = message;
  }
}

export class VpnProfile {
  // Authentication types
  static readonly TYPE_CERTIFICATES: number = 0;
  static readonly TYPE_PKCS12: number = 1;
  static readonly TYPE_KEYSTORE: number = 2;
  static readonly TYPE_USERPASS: number = 3;
  static readonly TYPE_STATICKEYS: number = 4;
  static readonly TYPE_USERPASS_CERTIFICATES: number = 5;
  static readonly TYPE_USERPASS_PKCS12: number = 6;
  static readonly TYPE_USERPASS_KEYSTORE: number = 7;
  static readonly TYPE_EXTERNAL_APP: number = 8;

  // X509 verification types
  static readonly X509_VERIFY_TLSREMOTE: number = 0;
  static readonly X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING: number = 1;
  static readonly X509_VERIFY_TLSREMOTE_DN: number = 2;
  static readonly X509_VERIFY_TLSREMOTE_RDN: number = 3;
  static readonly X509_VERIFY_TLSREMOTE_RDN_PREFIX: number = 4;

  // Auth retry behaviour
  static readonly AUTH_RETRY_NONE_FORGET: number = 0;
  static readonly AUTH_RETRY_NONE_KEEP: number = 1;
  static readonly AUTH_RETRY_NOINTERACT: number = 2;
  static readonly AUTH_RETRY_INTERACT: number = 3;

  static readonly MAX_EMBED_FILE_SIZE: number = 2048 * 1024;
  static readonly INLINE_TAG: string = '[[INLINE]]';
  static readonly DISPLAYNAME_TAG: string = '[[NAME]]';
  static readonly MAXLOGLEVEL: number = 4;
  static readonly CURRENT_PROFILE_VERSION: number = 10;
  static readonly DEFAULT_MSSFIX_SIZE: number = 1280;
  static readonly DEFAULT_DNS1: string = '9.9.9.9';
  static readonly DEFAULT_DNS2: string = '2620:fe::fe';
  static readonly MIN_CHECKBOX_PROFILE_ERC = 0;

  mAuthenticationType: number = VpnProfile.TYPE_KEYSTORE;
  mName: string = '';
  mAlias?: string;
  mClientCertFilename?: string;
  mTLSAuthDirection: string = '';
  mTLSAuthFilename?: string;
  mClientKeyFilename?: string;
  mCaFilename?: string;
  mUseLzo: boolean = false;
  mPKCS12Filename?: string;
  mPKCS12Password?: string;
  mUseTLSAuth: boolean = false;
  mDNS1: string = VpnProfile.DEFAULT_DNS1;
  mDNS2: string = VpnProfile.DEFAULT_DNS2;
  mIPv4Address?: string;
  mIPv6Address?: string;
  mOverrideDNS: boolean = false;
  mSearchDomain: string = 'blinkt.de';
  mUseDefaultRoute: boolean = true;
  mUsePull: boolean = true;
  mCustomRoutes?: string;
  mCheckRemoteCN: boolean = true;
  mExpectTLSCert: boolean = false;
  mRemoteCN: string = '';
  mPassword?: string;
  mUsername?: string;
  mRoutenopull: boolean = false;
  mUseRandomHostname: boolean = false;
  mUseFloat: boolean = false;
  mUseCustomConfig: boolean = false;
  mCustomConfigOptions: string = '';
  mVerb: string = '1';
  mCipher: string = '';
  mNobind: boolean = true;
  mUseDefaultRoutev6: boolean = true;
  mCustomRoutesv6: string = '';
  mKeyPassword?: string;
  mPersistTun: boolean = false;
  mConnectRetryMax: string = '-1';
  mConnectRetry: string = '2';
  mConnectRetryMaxTime: string = '300';
  mUserEditable: boolean = true;
  mAuth: string = '';
  mX509AuthType: number = VpnProfile.X509_VERIFY_TLSREMOTE_RDN;
  mx509UsernameField?: string;
  mAllowLocalLAN: boolean = false;
  mExcludedRoutes?: string;
  mExcludedRoutesv6?: string;
  mMssFix: number = 0;
  mConnections: Connection[] = [];
  mServerOverride: string = '';
  mStaticChallenge: string = '';
  mStaticChallengeEcho: boolean = false;
  mRemoteRandom: boolean = false;
  mAllowedAppsVpn: Set<string> = new Set<string>();
  mAllowedAppsVpnAreDisallowed: boolean = true;
  mAllowAppVpnBypass: boolean = false;
  mCrlFilename?: string;
  mProfileCreator?: string;
  mExternalAuthenticator?: string;
  mAuthRetry: number = VpnProfile.AUTH_RETRY_NONE_FORGET;
  mTunMtu: number = 0;
  mPushPeerInfo: boolean = false;
  mVersion: number = 0;
  mLastUsed: number = 0;
  importedProfileHash?: string;
  // Legacy field kept for ConfigParser fixup
  mServerName: string = '';
  mUseUdp: boolean = true;
  mTemporaryProfile: boolean = false;
  mDataCiphers: string = '';
  mBlockUnusedAddressFamilies: boolean = true;
  mCheckPeerFingerprint: boolean = false;
  mPeerFingerPrints: string = '';
  mCompatMode: number = 0;
  mUseLegacyProvider: boolean = false;
  mTlSCertProfile: string = '';
  mCreationDate: number = 0;
  changesLog: ChangeLogEntry[] = [];
  mUuid: string = '';
  mProfileVersion: number = VpnProfile.CURRENT_PROFILE_VERSION;

  constructor(name: string) {
    this.mUuid = VpnProfile.genUuid();
    this.mName = name;
    this.mProfileVersion = VpnProfile.CURRENT_PROFILE_VERSION;
    this.mConnections = [new Connection()];
    let now = Date.now();
    this.mLastUsed = now;
    this.mCreationDate = now;
  }

  static genUuid(): string {
    try {
      return util.generateRandomUUID(false);
    } catch (e) {
      return `${Date.now()}-${Math.floor(Math.random() * 1e9)}`;
    }
  }

  getUUID(): string {
    return this.mUuid;
  }

  getName(): string {
    if (this.mName === '' || this.mName === undefined) {
      return 'No profile name';
    }
    return this.mName;
  }

  clearDefaults(): void {
    this.mServerName = 'unknown';
    this.mUsePull = false;
    this.mUseLzo = false;
    this.mUseDefaultRoute = false;
    this.mUseDefaultRoutev6 = false;
    this.mExpectTLSCert = false;
    this.mCheckRemoteCN = false;
    this.mPersistTun = false;
    this.mAllowLocalLAN = true;
    this.mPushPeerInfo = false;
    this.mMssFix = 0;
    this.mNobind = false;
  }

  addChangeLogEntry(message: string): void {
    let entry = new ChangeLogEntry(Date.now(), message);
    this.changesLog.push(entry);
    // Keep a maximum of 50 entries like the original
    while (this.changesLog.length > 50) {
      this.changesLog.shift();
    }
  }

  // ---------------------------------------------------------------------
  // Static helpers (ported verbatim from VpnProfile.java)
  // ---------------------------------------------------------------------

  static isEmpty(s?: string): boolean {
    return s === undefined || s === null || s === '';
  }

  static openVpnEscape(unescaped?: string): string {
    if (unescaped === undefined || unescaped === null) {
      return '';
    }
    let escapedString = unescaped.split('\\').join('\\\\');
    escapedString = escapedString.split('"').join('\\"');
    escapedString = escapedString.split('\n').join('\\n');

    if (escapedString === unescaped && escapedString.indexOf(' ') === -1 &&
      escapedString.indexOf('#') === -1 && escapedString.indexOf(';') === -1 &&
      escapedString !== '' && escapedString.indexOf("'") === -1) {
      return unescaped;
    } else {
      return '"' + escapedString + '"';
    }
  }

  static insertFileData(cfgentry: string, filedata?: string): string {
    if (filedata === undefined || filedata === null) {
      return `${cfgentry} file missing in config profile\n`;
    } else if (VpnProfile.isEmbedded(filedata)) {
      let dataWithOutHeader = VpnProfile.getEmbeddedContent(filedata);
      return `<${cfgentry}>\n${dataWithOutHeader}\n</${cfgentry}>\n`;
    } else {
      return `${cfgentry} ${VpnProfile.openVpnEscape(filedata)}\n`;
    }
  }

  static getDisplayName(embeddedFile: string): string {
    let start = VpnProfile.DISPLAYNAME_TAG.length;
    let end = embeddedFile.indexOf(VpnProfile.INLINE_TAG);
    return embeddedFile.substring(start, end);
  }

  static getEmbeddedContent(data: string): string {
    if (data.indexOf(VpnProfile.INLINE_TAG) === -1) {
      return data;
    }
    let start = data.indexOf(VpnProfile.INLINE_TAG) + VpnProfile.INLINE_TAG.length;
    return data.substring(start);
  }

  static isEmbedded(data?: string): boolean {
    if (data === undefined || data === null) {
      return false;
    }
    if (data.startsWith(VpnProfile.INLINE_TAG) || data.startsWith(VpnProfile.DISPLAYNAME_TAG)) {
      return true;
    }
    return false;
  }

  /** Returns '' when the route cannot be parsed. */
  static cidrToIPAndNetmask(route?: string): string {
    if (route === undefined || route === null) {
      return '';
    }
    let parts = route.split('/');
    // No /xx, assume /32 as netmask
    if (parts.length === 1) {
      parts = (route + '/32').split('/');
    }
    if (parts.length !== 2) {
      return '';
    }
    let len = parseInt(parts[1]);
    if (isNaN(len) || len < 0 || len > 32) {
      return '';
    }
    let nm = 0xffffffff;
    nm = (nm << (32 - len)) >>> 0;
    let netmask = `${(nm & 0xff000000) >>> 24}.${(nm & 0xff0000) >>> 16}.${(nm & 0xff00) >>> 8}.${nm & 0xff}`;
    return `${parts[0]}  ${netmask}`;
  }

  getCustomRoutes(routes?: string): string[] {
    let cidrRoutes: string[] = [];
    if (routes === undefined || routes === null) {
      return cidrRoutes;
    }
    let split = routes.split(/[\n \t]/);
    for (let route of split) {
      if (route !== '') {
        let cidrroute = VpnProfile.cidrToIPAndNetmask(route);
        if (cidrroute === '') {
          return cidrRoutes;
        }
        cidrRoutes.push(cidrroute);
      }
    }
    return cidrRoutes;
  }

  getCustomRoutesv6(routes?: string): string[] {
    let cidrRoutes: string[] = [];
    if (routes === undefined || routes === null) {
      return cidrRoutes;
    }
    let split = routes.split(/[\n \t]/);
    for (let route of split) {
      if (route !== '') {
        cidrRoutes.push(route);
      }
    }
    return cidrRoutes;
  }

  isUserPWAuth(): boolean {
    switch (this.mAuthenticationType) {
      case VpnProfile.TYPE_USERPASS:
      case VpnProfile.TYPE_USERPASS_CERTIFICATES:
      case VpnProfile.TYPE_USERPASS_KEYSTORE:
      case VpnProfile.TYPE_USERPASS_PKCS12:
        return true;
      default:
        return false;
    }
  }

  usesExtraProxyOptions(): boolean {
    for (let c of this.mConnections) {
      if (c.usesExtraProxyOptions()) {
        return true;
      }
    }
    return false;
  }

  requireTLSKeyPassword(): boolean {
    if (VpnProfile.isEmpty(this.mClientKeyFilename)) {
      return false;
    }
    let data = '';
    if (VpnProfile.isEmbedded(this.mClientKeyFilename)) {
      data = this.mClientKeyFilename as string;
    } else {
      // External files are always imported (inlined) on HarmonyOS, so treat
      // non-embedded keys as unencrypted unless the content says otherwise.
      return false;
    }
    if (data.indexOf('Proc-Type: 4,ENCRYPTED') !== -1) {
      return true;
    } else if (data.indexOf('-----BEGIN ENCRYPTED PRIVATE KEY-----') !== -1) {
      return true;
    }
    return false;
  }

  /**
   * Returns which user input is needed ('' = none):
   * 'pkcs12_file_encryption_key' | 'private_key_password' | 'password'
   */
  needUserPWInputStr(): string {
    if ((this.mAuthenticationType === VpnProfile.TYPE_PKCS12 ||
      this.mAuthenticationType === VpnProfile.TYPE_USERPASS_PKCS12) &&
      VpnProfile.isEmpty(this.mPKCS12Password)) {
      return 'pkcs12_file_encryption_key';
    }
    if (this.mAuthenticationType === VpnProfile.TYPE_CERTIFICATES ||
      this.mAuthenticationType === VpnProfile.TYPE_USERPASS_CERTIFICATES) {
      if (this.requireTLSKeyPassword() && VpnProfile.isEmpty(this.mKeyPassword)) {
        return 'private_key_password';
      }
    }
    if (this.isUserPWAuth() &&
      (VpnProfile.isEmpty(this.mUsername) || VpnProfile.isEmpty(this.mPassword))) {
      return 'password';
    }
    return '';
  }

  checkProfile(useOpenVPN3: boolean): ProfileError {
    if (this.mAuthenticationType === VpnProfile.TYPE_KEYSTORE ||
      this.mAuthenticationType === VpnProfile.TYPE_USERPASS_KEYSTORE ||
      this.mAuthenticationType === VpnProfile.TYPE_EXTERNAL_APP) {
      if (this.mAlias === undefined || this.mAlias === null) {
        return ProfileError.NO_KEYSTORE_CERT_SELECTED;
      }
    } else if (this.mAuthenticationType === VpnProfile.TYPE_CERTIFICATES ||
      this.mAuthenticationType === VpnProfile.TYPE_USERPASS_CERTIFICATES) {
      if (VpnProfile.isEmpty(this.mCaFilename) && !this.mCheckPeerFingerprint) {
        return ProfileError.NO_CA_CERT_SELECTED;
      }
    }

    if (this.mCheckRemoteCN && this.mX509AuthType === VpnProfile.X509_VERIFY_TLSREMOTE) {
      return ProfileError.DEPRECATED_TLS_REMOTE;
    }

    if (!this.mUsePull || this.mAuthenticationType === VpnProfile.TYPE_STATICKEYS) {
      if (this.mIPv4Address === undefined || VpnProfile.cidrToIPAndNetmask(this.mIPv4Address) === '') {
        return ProfileError.IPV4_FORMAT_ERROR;
      }
    }
    if (!this.mUseDefaultRoute) {
      if (!VpnProfile.isEmpty(this.mCustomRoutes) && this.getCustomRoutes(this.mCustomRoutes).length === 0) {
        return ProfileError.CUSTOM_ROUTE_FORMAT_ERROR;
      }
      if (!VpnProfile.isEmpty(this.mExcludedRoutes) && this.getCustomRoutes(this.mExcludedRoutes).length === 0) {
        return ProfileError.CUSTOM_ROUTE_FORMAT_ERROR;
      }
    }

    if (this.mUseTLSAuth && VpnProfile.isEmpty(this.mTLSAuthFilename)) {
      return ProfileError.MISSING_TLSAUTH;
    }

    if ((this.mAuthenticationType === VpnProfile.TYPE_USERPASS_CERTIFICATES ||
      this.mAuthenticationType === VpnProfile.TYPE_CERTIFICATES) &&
      (VpnProfile.isEmpty(this.mClientCertFilename) || VpnProfile.isEmpty(this.mClientKeyFilename))) {
      return ProfileError.MISSING_CERTIFICATES;
    }

    let noRemoteEnabled = true;
    for (let c of this.mConnections) {
      if (c.mEnabled) {
        noRemoteEnabled = false;
      }
    }
    if (noRemoteEnabled) {
      return ProfileError.REMOTE_NO_SERVER_SELECTED;
    }

    if (useOpenVPN3) {
      if (this.mAuthenticationType === VpnProfile.TYPE_STATICKEYS) {
        return ProfileError.OPENVPN3_NOSTATICKEYS;
      }
      if (this.mAuthenticationType === VpnProfile.TYPE_PKCS12 ||
        this.mAuthenticationType === VpnProfile.TYPE_USERPASS_PKCS12) {
        return ProfileError.OPENVPN3_PKCS12;
      }
      for (let conn of this.mConnections) {
        if (conn.mProxyType === ProxyType.ORBOT || conn.mProxyType === ProxyType.SOCKS5) {
          return ProfileError.OPENVPN3_SOCKSPROXY;
        }
      }
    }

    let dataciphers = '';
    if (!VpnProfile.isEmpty(this.mDataCiphers)) {
      dataciphers = this.mDataCiphers.toUpperCase();
    }
    let cipher = 'BF-CBC';
    if (!VpnProfile.isEmpty(this.mCipher)) {
      cipher = this.mCipher.toUpperCase();
    }

    if (!this.mUseLegacyProvider &&
      ((dataciphers.indexOf('BF-CBC') !== -1) ||
        ((this.mCompatMode > 0 && this.mCompatMode < 20500) && cipher === 'BF-CBC'))) {
      return ProfileError.BF_CBC_REQUIRES_LEGACY;
    }

    return ProfileError.NO_ERROR;
  }

  copy(newName: string): VpnProfile {
    let p = new VpnProfile(newName);
    let json = this.toJson();
    let loaded = VpnProfile.fromJson(json);
    loaded.mUuid = VpnProfile.genUuid();
    loaded.mName = newName;
    loaded.mVersion = 0;
    loaded.mLastUsed = Date.now();
    loaded.mCreationDate = Date.now();
    loaded.changesLog = [];
    loaded.mProfileCreator = undefined;
    loaded.mUserEditable = true;
    loaded.mTemporaryProfile = false;
    return loaded;
  }

  // ---------------------------------------------------------------------
  // JSON serialization
  // ---------------------------------------------------------------------

  toJson(): Record<string, Object> {
    let conns: Object[] = [];
    for (let c of this.mConnections) {
      conns.push(c.toJson());
    }
    let apps: string[] = [];
    this.mAllowedAppsVpn.forEach((a: string) => {
      apps.push(a);
    });
    let log: Object[] = [];
    for (let e of this.changesLog) {
      let le: Record<string, Object> = { 'time': e.time, 'message': e.message };
      log.push(le);
    }
    let o: Record<string, Object> = {
      'mProfileVersion': this.mProfileVersion,
      'mUuid': this.mUuid,
      'mAuthenticationType': this.mAuthenticationType,
      'mName': this.mName,
      'mTLSAuthDirection': this.mTLSAuthDirection,
      'mUseLzo': this.mUseLzo,
      'mUseTLSAuth': this.mUseTLSAuth,
      'mDNS1': this.mDNS1,
      'mDNS2': this.mDNS2,
      'mOverrideDNS': this.mOverrideDNS,
      'mSearchDomain': this.mSearchDomain,
      'mUseDefaultRoute': this.mUseDefaultRoute,
      'mUsePull': this.mUsePull,
      'mCheckRemoteCN': this.mCheckRemoteCN,
      'mExpectTLSCert': this.mExpectTLSCert,
      'mRemoteCN': this.mRemoteCN,
      'mRoutenopull': this.mRoutenopull,
      'mUseRandomHostname': this.mUseRandomHostname,
      'mUseFloat': this.mUseFloat,
      'mUseCustomConfig': this.mUseCustomConfig,
      'mCustomConfigOptions': this.mCustomConfigOptions,
      'mVerb': this.mVerb,
      'mCipher': this.mCipher,
      'mNobind': this.mNobind,
      'mUseDefaultRoutev6': this.mUseDefaultRoutev6,
      'mCustomRoutesv6': this.mCustomRoutesv6,
      'mPersistTun': this.mPersistTun,
      'mConnectRetryMax': this.mConnectRetryMax,
      'mConnectRetry': this.mConnectRetry,
      'mConnectRetryMaxTime': this.mConnectRetryMaxTime,
      'mUserEditable': this.mUserEditable,
      'mAuth': this.mAuth,
      'mX509AuthType': this.mX509AuthType,
      'mAllowLocalLAN': this.mAllowLocalLAN,
      'mMssFix': this.mMssFix,
      'mConnections': conns,
      'mServerOverride': this.mServerOverride,
      'mStaticChallenge': this.mStaticChallenge,
      'mStaticChallengeEcho': this.mStaticChallengeEcho,
      'mRemoteRandom': this.mRemoteRandom,
      'mAllowedAppsVpn': apps,
      'mAllowedAppsVpnAreDisallowed': this.mAllowedAppsVpnAreDisallowed,
      'mAllowAppVpnBypass': this.mAllowAppVpnBypass,
      'mAuthRetry': this.mAuthRetry,
      'mTunMtu': this.mTunMtu,
      'mPushPeerInfo': this.mPushPeerInfo,
      'mVersion': this.mVersion,
      'mLastUsed': this.mLastUsed,
      'mUseUdp': this.mUseUdp,
      'mTemporaryProfile': this.mTemporaryProfile,
      'mDataCiphers': this.mDataCiphers,
      'mBlockUnusedAddressFamilies': this.mBlockUnusedAddressFamilies,
      'mCheckPeerFingerprint': this.mCheckPeerFingerprint,
      'mPeerFingerPrints': this.mPeerFingerPrints,
      'mCompatMode': this.mCompatMode,
      'mUseLegacyProvider': this.mUseLegacyProvider,
      'mTlSCertProfile': this.mTlSCertProfile,
      'mCreationDate': this.mCreationDate,
      'changesLog': log,
      'mServerName': this.mServerName
    };
    if (this.mAlias !== undefined) {
      o['mAlias'] = this.mAlias;
    }
    if (this.mClientCertFilename !== undefined) {
      o['mClientCertFilename'] = this.mClientCertFilename;
    }
    if (this.mTLSAuthFilename !== undefined) {
      o['mTLSAuthFilename'] = this.mTLSAuthFilename;
    }
    if (this.mClientKeyFilename !== undefined) {
      o['mClientKeyFilename'] = this.mClientKeyFilename;
    }
    if (this.mCaFilename !== undefined) {
      o['mCaFilename'] = this.mCaFilename;
    }
    if (this.mPKCS12Filename !== undefined) {
      o['mPKCS12Filename'] = this.mPKCS12Filename;
    }
    if (this.mPKCS12Password !== undefined) {
      o['mPKCS12Password'] = this.mPKCS12Password;
    }
    if (this.mIPv4Address !== undefined) {
      o['mIPv4Address'] = this.mIPv4Address;
    }
    if (this.mIPv6Address !== undefined) {
      o['mIPv6Address'] = this.mIPv6Address;
    }
    if (this.mCustomRoutes !== undefined) {
      o['mCustomRoutes'] = this.mCustomRoutes;
    }
    if (this.mPassword !== undefined) {
      o['mPassword'] = this.mPassword;
    }
    if (this.mUsername !== undefined) {
      o['mUsername'] = this.mUsername;
    }
    if (this.mKeyPassword !== undefined) {
      o['mKeyPassword'] = this.mKeyPassword;
    }
    if (this.mExcludedRoutes !== undefined) {
      o['mExcludedRoutes'] = this.mExcludedRoutes;
    }
    if (this.mExcludedRoutesv6 !== undefined) {
      o['mExcludedRoutesv6'] = this.mExcludedRoutesv6;
    }
    if (this.mCrlFilename !== undefined) {
      o['mCrlFilename'] = this.mCrlFilename;
    }
    if (this.mProfileCreator !== undefined) {
      o['mProfileCreator'] = this.mProfileCreator;
    }
    if (this.mExternalAuthenticator !== undefined) {
      o['mExternalAuthenticator'] = this.mExternalAuthenticator;
    }
    if (this.mx509UsernameField !== undefined) {
      o['mx509UsernameField'] = this.mx509UsernameField;
    }
    if (this.importedProfileHash !== undefined) {
      o['importedProfileHash'] = this.importedProfileHash;
    }
    return o;
  }

  static fromJson(o: Record<string, Object>): VpnProfile {
    let name = (o['mName'] as string) ?? 'converted Profile';
    let p = new VpnProfile(name);
    p.mUuid = (o['mUuid'] as string) ?? VpnProfile.genUuid();
    p.mProfileVersion = (o['mProfileVersion'] as number) ?? VpnProfile.CURRENT_PROFILE_VERSION;
    p.mAuthenticationType = (o['mAuthenticationType'] as number) ?? VpnProfile.TYPE_KEYSTORE;
    p.mTLSAuthDirection = (o['mTLSAuthDirection'] as string) ?? '';
    p.mUseLzo = (o['mUseLzo'] as boolean) ?? false;
    p.mUseTLSAuth = (o['mUseTLSAuth'] as boolean) ?? false;
    p.mDNS1 = (o['mDNS1'] as string) ?? VpnProfile.DEFAULT_DNS1;
    p.mDNS2 = (o['mDNS2'] as string) ?? VpnProfile.DEFAULT_DNS2;
    p.mOverrideDNS = (o['mOverrideDNS'] as boolean) ?? false;
    p.mSearchDomain = (o['mSearchDomain'] as string) ?? 'blinkt.de';
    p.mUseDefaultRoute = (o['mUseDefaultRoute'] as boolean) ?? true;
    p.mUsePull = (o['mUsePull'] as boolean) ?? true;
    p.mCheckRemoteCN = (o['mCheckRemoteCN'] as boolean) ?? true;
    p.mExpectTLSCert = (o['mExpectTLSCert'] as boolean) ?? false;
    p.mRemoteCN = (o['mRemoteCN'] as string) ?? '';
    p.mRoutenopull = (o['mRoutenopull'] as boolean) ?? false;
    p.mUseRandomHostname = (o['mUseRandomHostname'] as boolean) ?? false;
    p.mUseFloat = (o['mUseFloat'] as boolean) ?? false;
    p.mUseCustomConfig = (o['mUseCustomConfig'] as boolean) ?? false;
    p.mCustomConfigOptions = (o['mCustomConfigOptions'] as string) ?? '';
    p.mVerb = (o['mVerb'] as string) ?? '1';
    p.mCipher = (o['mCipher'] as string) ?? '';
    p.mNobind = (o['mNobind'] as boolean) ?? true;
    p.mUseDefaultRoutev6 = (o['mUseDefaultRoutev6'] as boolean) ?? true;
    p.mCustomRoutesv6 = (o['mCustomRoutesv6'] as string) ?? '';
    p.mPersistTun = (o['mPersistTun'] as boolean) ?? false;
    p.mConnectRetryMax = (o['mConnectRetryMax'] as string) ?? '-1';
    p.mConnectRetry = (o['mConnectRetry'] as string) ?? '2';
    p.mConnectRetryMaxTime = (o['mConnectRetryMaxTime'] as string) ?? '300';
    p.mUserEditable = (o['mUserEditable'] as boolean) ?? true;
    p.mAuth = (o['mAuth'] as string) ?? '';
    p.mX509AuthType = (o['mX509AuthType'] as number) ?? VpnProfile.X509_VERIFY_TLSREMOTE_RDN;
    p.mAllowLocalLAN = (o['mAllowLocalLAN'] as boolean) ?? false;
    p.mMssFix = (o['mMssFix'] as number) ?? 0;
    p.mServerOverride = (o['mServerOverride'] as string) ?? '';
    p.mStaticChallenge = (o['mStaticChallenge'] as string) ?? '';
    p.mStaticChallengeEcho = (o['mStaticChallengeEcho'] as boolean) ?? false;
    p.mRemoteRandom = (o['mRemoteRandom'] as boolean) ?? false;
    p.mAllowedAppsVpnAreDisallowed = (o['mAllowedAppsVpnAreDisallowed'] as boolean) ?? true;
    p.mAllowAppVpnBypass = (o['mAllowAppVpnBypass'] as boolean) ?? false;
    p.mAuthRetry = (o['mAuthRetry'] as number) ?? VpnProfile.AUTH_RETRY_NONE_FORGET;
    p.mTunMtu = (o['mTunMtu'] as number) ?? 0;
    p.mPushPeerInfo = (o['mPushPeerInfo'] as boolean) ?? false;
    p.mVersion = (o['mVersion'] as number) ?? 0;
    p.mLastUsed = (o['mLastUsed'] as number) ?? Date.now();
    p.mUseUdp = (o['mUseUdp'] as boolean) ?? true;
    p.mTemporaryProfile = (o['mTemporaryProfile'] as boolean) ?? false;
    p.mDataCiphers = (o['mDataCiphers'] as string) ?? '';
    p.mBlockUnusedAddressFamilies = (o['mBlockUnusedAddressFamilies'] as boolean) ?? true;
    p.mCheckPeerFingerprint = (o['mCheckPeerFingerprint'] as boolean) ?? false;
    p.mPeerFingerPrints = (o['mPeerFingerPrints'] as string) ?? '';
    p.mCompatMode = (o['mCompatMode'] as number) ?? 0;
    p.mUseLegacyProvider = (o['mUseLegacyProvider'] as boolean) ?? false;
    p.mTlSCertProfile = (o['mTlSCertProfile'] as string) ?? '';
    p.mCreationDate = (o['mCreationDate'] as number) ?? Date.now();
    p.mServerName = (o['mServerName'] as string) ?? '';

    p.mAlias = o['mAlias'] as string;
    p.mClientCertFilename = o['mClientCertFilename'] as string;
    p.mTLSAuthFilename = o['mTLSAuthFilename'] as string;
    p.mClientKeyFilename = o['mClientKeyFilename'] as string;
    p.mCaFilename = o['mCaFilename'] as string;
    p.mPKCS12Filename = o['mPKCS12Filename'] as string;
    p.mPKCS12Password = o['mPKCS12Password'] as string;
    p.mIPv4Address = o['mIPv4Address'] as string;
    p.mIPv6Address = o['mIPv6Address'] as string;
    p.mCustomRoutes = o['mCustomRoutes'] as string;
    p.mExcludedRoutes = o['mExcludedRoutes'] as string;
    p.mExcludedRoutesv6 = o['mExcludedRoutesv6'] as string;
    p.mCrlFilename = o['mCrlFilename'] as string;
    p.mProfileCreator = o['mProfileCreator'] as string;
    p.mExternalAuthenticator = o['mExternalAuthenticator'] as string;
    p.mx509UsernameField = o['mx509UsernameField'] as string;
    p.importedProfileHash = o['importedProfileHash'] as string;
    p.mPassword = o['mPassword'] as string;
    p.mUsername = o['mUsername'] as string;
    p.mKeyPassword = o['mKeyPassword'] as string;

    let conns = o['mConnections'] as Object[];
    if (conns !== undefined && conns !== null && conns.length > 0) {
      p.mConnections = [];
      for (let c of conns) {
        p.mConnections.push(Connection.fromJson(c as Record<string, Object>));
      }
    }

    let apps = o['mAllowedAppsVpn'] as string[];
    if (apps !== undefined && apps !== null) {
      p.mAllowedAppsVpn = new Set<string>(apps);
    }

    let log = o['changesLog'] as Object[];
    if (log !== undefined && log !== null) {
      p.changesLog = [];
      for (let e of log) {
        let rec = e as Record<string, Object>;
        p.changesLog.push(new ChangeLogEntry((rec['time'] as number) ?? 0,
          (rec['message'] as string) ?? ''));
      }
    }
    return p;
  }
}
