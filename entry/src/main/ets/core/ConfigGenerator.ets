/**
 * Port of VpnProfile.getConfigFile() — generates the .conf content handed to
 * the OpenVPN process via stdin in the Android version. On HarmonyOS the same
 * text is used for the "Generated Config" tab, the share/export function and
 * as input for the (to be plugged in) native engine.
 */

import { VpnProfile } from './VpnProfile';
import { Connection } from './Connection';

export class GenEnvInfo {
  mgmtSocketDir: string = '';
  guiVer: string = '';
  platVer: string = '';
  hwaddr: string = '';
  useSystemProxy: boolean = true;
  openVpn3: boolean = false;
}

export function generateConfigFile(p: VpnProfile, env: GenEnvInfo): string {
  let cfg = '';

  if (!env.openVpn3) {
    // OpenVPN 2.x management interface used by the external process build.
    cfg += '# Config for OpenVPN 2.x\n';
    cfg += '# Enables connection to GUI\n';
    cfg += 'management ';
    cfg += env.mgmtSocketDir;
    cfg += '/';
    cfg += 'mgmtsocket';
    cfg += ' unix\n';
    cfg += 'management-client\n';
    cfg += 'management-query-passwords\n';
    cfg += 'management-hold\n\n';
  } else {
    cfg += '# Config for embedded OpenVPN3 core\n';
  }

  cfg += `setenv IV_GUI_VER ${VpnProfile.openVpnEscape(env.guiVer)} \n`;
  cfg += 'setenv IV_SSO openurl,webauth,crtext\n';
  cfg += `setenv IV_PLAT_VER ${VpnProfile.openVpnEscape(env.platVer)}\n`;
  if (env.hwaddr !== '') {
    cfg += `setenv IV_HWADDR ${env.hwaddr}\n`;
  }

  if (p.mUseLegacyProvider) {
    cfg += 'providers legacy default\n';
  }

  if (!VpnProfile.isEmpty(p.mTlSCertProfile) && p.mAuthenticationType !== VpnProfile.TYPE_STATICKEYS) {
    cfg += `tls-cert-profile ${p.mTlSCertProfile}\n`;
  }

  if (!env.openVpn3) {
    cfg += 'machine-readable-output\n';
    cfg += 'allow-recursive-routing\n';
    // Users are confused by warnings that are misleading...
    cfg += 'ifconfig-nowarn\n';
  }

  let useTLSClient = p.mAuthenticationType !== VpnProfile.TYPE_STATICKEYS;

  if (useTLSClient && p.mUsePull) {
    cfg += 'client\n';
  } else if (p.mUsePull) {
    cfg += 'pull\n';
  } else if (useTLSClient) {
    cfg += 'tls-client\n';
  }

  cfg += `verb ${VpnProfile.MAXLOGLEVEL}\n`;

  if (p.mConnectRetryMax === undefined || p.mConnectRetryMax === null) {
    p.mConnectRetryMax = '-1';
  }
  if (p.mConnectRetryMax !== '-1') {
    cfg += `connect-retry-max ${p.mConnectRetryMax}\n`;
  }
  if (VpnProfile.isEmpty(p.mConnectRetry)) {
    p.mConnectRetry = '2';
  }
  if (VpnProfile.isEmpty(p.mConnectRetryMaxTime)) {
    p.mConnectRetryMaxTime = '300';
  }
  cfg += `connect-retry ${p.mConnectRetry} ${p.mConnectRetryMaxTime}\n`;
  cfg += 'resolv-retry 60\n';

  // We cannot use anything else than tun
  cfg += 'dev tun\n';

  let canUsePlainRemotes = true;
  let serverOverride = p.mServerOverride.trim();

  if (p.mConnections.length === 1) {
    cfg += p.mConnections[0].getConnectionBlock(env.openVpn3, serverOverride);
  } else {
    for (let conn of p.mConnections) {
      canUsePlainRemotes = canUsePlainRemotes && conn.isOnlyRemote();
    }

    if (p.mRemoteRandom) {
      cfg += 'remote-random\n';
    }

    if (canUsePlainRemotes) {
      for (let conn of p.mConnections) {
        if (conn.mEnabled) {
          cfg += conn.getConnectionBlock(env.openVpn3, serverOverride);
        }
      }
    }
  }

  if (!VpnProfile.isEmpty(p.mStaticChallenge)) {
    cfg += `static-challenge ${VpnProfile.openVpnEscape(p.mStaticChallenge)} ${p.mStaticChallengeEcho ? '1' : '0'}\n`;
  }

  switch (p.mAuthenticationType) {
    case VpnProfile.TYPE_USERPASS_CERTIFICATES:
      cfg += 'auth-user-pass\n';
    // fallthrough
    case VpnProfile.TYPE_CERTIFICATES: {
      // Ca
      if (!VpnProfile.isEmpty(p.mCaFilename)) {
        cfg += VpnProfile.insertFileData('ca', p.mCaFilename);
      }
      // Client Cert + Key
      cfg += VpnProfile.insertFileData('key', p.mClientKeyFilename);
      cfg += VpnProfile.insertFileData('cert', p.mClientCertFilename);
      break;
    }
    case VpnProfile.TYPE_USERPASS_PKCS12:
      cfg += 'auth-user-pass\n';
    // fallthrough
    case VpnProfile.TYPE_PKCS12: {
      cfg += VpnProfile.insertFileData('pkcs12', p.mPKCS12Filename);
      if (!VpnProfile.isEmpty(p.mCaFilename)) {
        cfg += VpnProfile.insertFileData('ca', p.mCaFilename);
      }
      break;
    }
    case VpnProfile.TYPE_USERPASS_KEYSTORE:
      cfg += 'auth-user-pass\n';
    // fallthrough
    case VpnProfile.TYPE_KEYSTORE:
    case VpnProfile.TYPE_EXTERNAL_APP: {
      cfg += '### From Keystore/ext auth app ####\n';
      if (!VpnProfile.isEmpty(p.mCaFilename)) {
        cfg += VpnProfile.insertFileData('ca', p.mCaFilename);
      } else if (!p.mCheckPeerFingerprint) {
        cfg += '# no keystore/explicit certificate available on this platform\n';
      }
      cfg += 'management-external-key nopadding pkcs1 pss digest\n';
      break;
    }
    case VpnProfile.TYPE_USERPASS: {
      cfg += 'auth-user-pass\n';
      if (!VpnProfile.isEmpty(p.mCaFilename)) {
        cfg += VpnProfile.insertFileData('ca', p.mCaFilename);
      }
      break;
    }
    default:
      break;
  }

  if (p.mCheckPeerFingerprint) {
    cfg += `<peer-fingerprint>\n${p.mPeerFingerPrints}\n</peer-fingerprint>\n`;
  }

  if (p.isUserPWAuth()) {
    if (p.mAuthRetry === VpnProfile.AUTH_RETRY_NOINTERACT) {
      cfg += 'auth-retry nointeract\n';
    }
  }

  if (!VpnProfile.isEmpty(p.mCrlFilename)) {
    cfg += VpnProfile.insertFileData('crl-verify', p.mCrlFilename);
  }

  if (p.mUseLzo) {
    cfg += 'comp-lzo\n';
  }

  if (p.mUseTLSAuth) {
    let useTlsCrypt = p.mTLSAuthDirection === 'tls-crypt';
    let useTlsCrypt2 = p.mTLSAuthDirection === 'tls-crypt-v2';

    if (p.mAuthenticationType === VpnProfile.TYPE_STATICKEYS) {
      cfg += VpnProfile.insertFileData('secret', p.mTLSAuthFilename);
    } else if (useTlsCrypt) {
      cfg += VpnProfile.insertFileData('tls-crypt', p.mTLSAuthFilename);
    } else if (useTlsCrypt2) {
      cfg += VpnProfile.insertFileData('tls-crypt-v2', p.mTLSAuthFilename);
    } else {
      cfg += VpnProfile.insertFileData('tls-auth', p.mTLSAuthFilename);
    }

    if (!VpnProfile.isEmpty(p.mTLSAuthDirection) && !useTlsCrypt && !useTlsCrypt2) {
      cfg += 'key-direction ';
      cfg += p.mTLSAuthDirection;
      cfg += '\n';
    }
  }

  if (!p.mUsePull) {
    if (!VpnProfile.isEmpty(p.mIPv4Address)) {
      cfg += `ifconfig ${VpnProfile.cidrToIPAndNetmask(p.mIPv4Address)}\n`;
    }
    let v6 = p.mIPv6Address;
    if (v6 !== undefined && v6 !== null) {
      // Use our own ip as gateway since we ignore it anyway
      let fakegw = v6.split('/')[0];
      cfg += `ifconfig-ipv6 ${v6} ${fakegw}\n`;
    }
  }

  if (p.mUsePull && p.mRoutenopull) {
    cfg += 'route-nopull\n';
  }

  let routes = '';

  if (p.mUseDefaultRoute) {
    routes += 'route 0.0.0.0 0.0.0.0 vpn_gateway\n';
  } else {
    let custom = p.getCustomRoutes(p.mCustomRoutes);
    for (let route of custom) {
      routes += `route ${route} vpn_gateway\n`;
    }
    let excluded = p.getCustomRoutes(p.mExcludedRoutes);
    for (let route of excluded) {
      routes += `route ${route} net_gateway\n`;
    }
  }

  if (p.mUseDefaultRoutev6) {
    cfg += 'route-ipv6 ::/0\n';
  } else {
    let customv6 = p.getCustomRoutesv6(p.mCustomRoutesv6);
    for (let route of customv6) {
      routes += `route-ipv6 ${route}\n`;
    }
  }

  cfg += routes;

  if (p.mOverrideDNS || !p.mUsePull) {
    if (!VpnProfile.isEmpty(p.mDNS1)) {
      cfg += `dhcp-option DNS ${p.mDNS1}\n`;
    }
    if (!VpnProfile.isEmpty(p.mDNS2)) {
      cfg += `dhcp-option DNS ${p.mDNS2}\n`;
    }
    if (!VpnProfile.isEmpty(p.mSearchDomain)) {
      cfg += `dhcp-option DOMAIN ${p.mSearchDomain}\n`;
    }
  }

  if (p.mMssFix !== 0) {
    if (p.mMssFix !== 1450) {
      cfg += `mssfix ${p.mMssFix}\n`;
    } else {
      cfg += 'mssfix\n';
    }
  }

  if (p.mTunMtu >= 48 && p.mTunMtu !== 1500) {
    cfg += `tun-mtu ${p.mTunMtu}\n`;
  }

  if (p.mNobind) {
    cfg += 'nobind\n';
  }

  // Authentication
  if (p.mAuthenticationType !== VpnProfile.TYPE_STATICKEYS) {
    if (p.mCheckRemoteCN) {
      if (p.mRemoteCN === undefined || p.mRemoteCN === null || p.mRemoteCN === '') {
        cfg += `verify-x509-name ${VpnProfile.openVpnEscape(p.mConnections[0].mServerName)} name\n`;
      } else {
        switch (p.mX509AuthType) {
          case VpnProfile.X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING:
            cfg += 'compat-names no-remapping\n';
          // fallthrough
          case VpnProfile.X509_VERIFY_TLSREMOTE:
            cfg += `tls-remote ${VpnProfile.openVpnEscape(p.mRemoteCN)}\n`;
            break;
          case VpnProfile.X509_VERIFY_TLSREMOTE_RDN:
            cfg += `verify-x509-name ${VpnProfile.openVpnEscape(p.mRemoteCN)} name\n`;
            break;
          case VpnProfile.X509_VERIFY_TLSREMOTE_RDN_PREFIX:
            cfg += `verify-x509-name ${VpnProfile.openVpnEscape(p.mRemoteCN)} name-prefix\n`;
            break;
          case VpnProfile.X509_VERIFY_TLSREMOTE_DN:
            cfg += `verify-x509-name ${VpnProfile.openVpnEscape(p.mRemoteCN)}\n`;
            break;
          default:
            break;
        }
      }
      if (!VpnProfile.isEmpty(p.mx509UsernameField)) {
        cfg += `x509-username-field ${VpnProfile.openVpnEscape(p.mx509UsernameField)}\n`;
      }
    }
    if (p.mExpectTLSCert) {
      cfg += 'remote-cert-tls server\n';
    }
  }

  if (!VpnProfile.isEmpty(p.mDataCiphers)) {
    cfg += `data-ciphers ${p.mDataCiphers}\n`;
  }

  if (p.mCompatMode > 0) {
    let major = Math.floor(p.mCompatMode / 10000);
    let minor = Math.floor((p.mCompatMode % 10000) / 100);
    let patch = p.mCompatMode % 100;
    cfg += `compat-mode ${major}.${minor}.${patch}\n`;
  }

  if (!VpnProfile.isEmpty(p.mCipher) && p.mCompatMode > 0) {
    cfg += `cipher ${p.mCipher}\n`;
  }

  if (!VpnProfile.isEmpty(p.mAuth)) {
    cfg += `auth ${p.mAuth}\n`;
  }

  // Obscure Settings dialog
  if (p.mUseRandomHostname && serverOverride === '') {
    cfg += '#my favorite options :)\nremote-random-hostname\n';
  }

  if (p.mUseFloat) {
    cfg += 'float\n';
  }

  if (p.mPersistTun && !env.openVpn3) {
    cfg += 'persist-tun\n';
    cfg += '# persist-tun also enables pre resolving to avoid DNS resolve problem\n';
    cfg += 'preresolve\n';
  }

  if (p.mPushPeerInfo) {
    cfg += 'push-peer-info\n';
  }

  if (env.useSystemProxy && !p.usesExtraProxyOptions() && !env.openVpn3) {
    cfg += '# Use system proxy setting\n';
    cfg += 'management-query-proxy\n';
  }

  if (p.mUseCustomConfig) {
    cfg += '# Custom configuration options\n';
    cfg += '# You are on your on own here :)\n';
    cfg += p.mCustomConfigOptions;
    cfg += '\n';
  }

  if (!canUsePlainRemotes) {
    cfg += '# Connection Options are at the end to allow global options (and global custom options) to influence connection blocks\n';
    for (let conn of p.mConnections) {
      if (conn.mEnabled) {
        cfg += '<connection>\n';
        cfg += conn.getConnectionBlock(env.openVpn3, serverOverride);
        cfg += '</connection>\n';
      }
    }
  }

  return cfg;
}
