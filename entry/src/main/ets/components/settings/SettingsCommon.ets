/**
 * Shared helpers for the profile settings tabs: option arrays (ported from
 * arrays.xml) and an ActionSheet based single choice selector (Spinner).
 */

import { R } from '../../common/Res';
import { Theme } from '../../common/Theme';
import { VpnProfile } from '../../core/VpnProfile';
import { Connection, ProxyType } from '../../core/Connection';

export function vpnTypeEntries(): string[] {
  return [
    R.s('vpn_type_certificates'),
    R.s('vpn_type_pkcs12'),
    R.s('vpn_type_keystore'),
    R.s('vpn_type_userpass'),
    R.s('vpn_type_statickeys'),
    R.s('vpn_type_userpass_certificates'),
    R.s('vpn_type_userpass_pkcs12'),
    R.s('vpn_type_userpass_keystore'),
    R.s('vpn_type_external_app')
  ];
}

export function compatModeEntries(): string[] {
  return [
    R.s('compat_mode_modern'),
    R.s('compat_mode_25'),
    R.s('compat_mode_24'),
    R.s('compat_mode_23')
  ];
}

export function compatModeToIndex(mode: number): number {
  if (mode === 0 || mode >= 20600) {
    return 0;
  } else if (mode < 20400) {
    return 3;
  } else if (mode < 20500) {
    return 2;
  } else {
    return 1;
  }
}

export function compatModeFromIndex(i: number): number {
  switch (i) {
    case 1:
      return 20500;
    case 2:
      return 20400;
    case 3:
      return 20300;
    default:
      return 0;
  }
}

export function authRetryEntries(): string[] {
  return [
    R.s('auth_retry_disconnect_forget'),
    R.s('auth_retry_disconnect_keep'),
    R.s('auth_retry_ignore_retry')
  ];
}

export function tlsDirectionEntries(): string[] {
  return [
    R.s('tls_direction_auth_0'),
    R.s('tls_direction_auth_1'),
    R.s('tls_direction_none'),
    R.s('tls_direction_tlscrypt'),
    R.s('tls_direction_tlscrypt2')
  ];
}

export function tlsDirectionValues(): string[] {
  return ['0', '1', '', 'tls-crypt', 'tls-crypt-v2'];
}

export function tlsProfileEntries(): string[] {
  return [
    R.s('tls_profile_insecure'),
    R.s('tls_profile_legacy'),
    R.s('tls_profile_preferred'),
    R.s('tls_profile_suiteb')
  ];
}

export function tlsProfileValues(): string[] {
  return ['insecure', 'legacy', 'preferred', 'suiteb'];
}

export function crmEntries(): string[] {
  return [
    R.s('crm_none'),
    R.s('crm_one'),
    R.s('crm_five'),
    R.s('crm_fifty'),
    R.s('crm_unlimited')
  ];
}

export function crmValues(): string[] {
  return ['1', '2', '5', '50', '-1'];
}

export function x509VerifyEntries(currentType: number, currentDn: string): number[] {
  let types = [2, 3, 4];
  if (currentType === VpnProfile.X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING && currentDn !== '') {
    types.unshift(1);
  }
  return types;
}

export function x509VerifyLabel(t: number): string {
  switch (t) {
    case VpnProfile.X509_VERIFY_TLSREMOTE:
    case VpnProfile.X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING:
      return R.s('tls_remote_deprecated');
    case VpnProfile.X509_VERIFY_TLSREMOTE_DN:
      return R.s('complete_dn');
    case VpnProfile.X509_VERIFY_TLSREMOTE_RDN:
      return R.s('rdn');
    case VpnProfile.X509_VERIFY_TLSREMOTE_RDN_PREFIX:
      return R.s('rdn_prefix');
    default:
      return '';
  }
}

export function proxyTypeEntries(): string[] {
  return [
    R.s('Use_no_proxy'),
    'HTTP',
    R.s('proxy_socks5'),
    R.s('tor_orbot')
  ];
}

export function proxyTypeFromIndex(i: number): ProxyType {
  switch (i) {
    case 1:
      return ProxyType.HTTP;
    case 2:
      return ProxyType.SOCKS5;
    case 3:
      return ProxyType.ORBOT;
    default:
      return ProxyType.NONE;
  }
}

export function proxyTypeToIndex(t: ProxyType): number {
  switch (t) {
    case ProxyType.HTTP:
      return 1;
    case ProxyType.SOCKS5:
      return 2;
    case ProxyType.ORBOT:
      return 3;
    default:
      return 0;
  }
}

export function showSingleChoice(title: string, entries: string[], selected: number,
  onSelect: (index: number) => void): void {
  let sheets: Array<SheetInfo> = [];
  for (let i = 0; i < entries.length; i++) {
    let idx = i;
    sheets.push({
      title: entries[i],
      action: () => {
        onSelect(idx);
      }
    });
  }
  let confirmBtn: ActionSheetButtonOptions = {
    value: R.s('cancel'),
    action: () => {
    }
  };
  let sheetOptions: ActionSheetOptions = {
    title: title,
    message: '',
    sheets: sheets,
    confirm: confirmBtn,
    cancel: () => {
    }
  };
  ActionSheet.show(sheetOptions);
}
