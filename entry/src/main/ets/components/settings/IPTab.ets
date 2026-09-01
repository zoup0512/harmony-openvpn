/**
 * IP and DNS tab — port of Settings_IP + vpn_ipsettings.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { PrefCategory, SwitchRow, CheckRow, TapRow } from '../PrefRows';
import { InputDialog, InputDialogModel } from '../InputDialog';

const TAB_BACKGROUND: string = Theme.DARK_BACKGROUND;
const TAB_SURFACE: string = Theme.DARK_SURFACE;
const TAB_BORDER: string = Theme.DARK_BORDER;

@Component
export struct IPTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State usePull: boolean = true;
  @State ipv4: string = '';
  @State ipv6: string = '';
  @State nobind: boolean = true;
  @State overrideDNS: boolean = false;
  @State searchDomain: string = '';
  @State dns1: string = '';
  @State dns2: string = '';
  private editModel: InputDialogModel = new InputDialogModel();
  private editDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.editModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let p = this.profile;
    this.usePull = p.mUsePull;
    this.ipv4 = p.mIPv4Address === undefined ? '' : p.mIPv4Address;
    this.ipv6 = p.mIPv6Address === undefined ? '' : p.mIPv6Address;
    this.nobind = p.mNobind;
    this.overrideDNS = p.mOverrideDNS;
    this.searchDomain = p.mSearchDomain;
    this.dns1 = p.mDNS1;
    this.dns2 = p.mDNS2;
  }

  private dnsSummary(value: string): string {
    if (value === '') {
      return R.s('dns_not_set');
    }
    let google = ['8.8.4.4', '8.8.8.8', '2001:4860:4860::8888', '2001:4860:4860::8844'];
    if (google.indexOf(value) !== -1) {
      return `${value} (dns.google.com)`;
    }
    if (value.startsWith('2606:4700:4700::') || value.startsWith('1.1.1.') || value.startsWith('1.0.0.')) {
      return `${value} (Cloudflare)`;
    }
    if (value.startsWith('9.9.9.') || value.startsWith('2620:fe::')) {
      return `${value} (Quad9)`;
    }
    return value;
  }

  private dnsEditable(): boolean {
    return !this.usePull || this.overrideDNS;
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          SwitchRow({
            title: R.s('use_pull'),
            summary: this.usePull ? R.s('pull_on_summary') : R.s('pull_off_summary'),
            checked: this.usePull,
            showDivider: false,
            darkMode: true,
            onChange: (v: boolean) => {
              this.usePull = v;
              this.profile.mUsePull = v;
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 12 })

        PrefCategory({ title: 'IP', darkMode: true })
        Column() {
          TapRow({
            title: R.s('ipv4_address'),
            summary: this.ipv4,
            rowEnabled: !this.usePull,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('ipv4_address', this.ipv4, R.s('ipv4_dialog_title'), (v: string) => {
                this.ipv4 = v;
                this.profile.mIPv4Address = v === '' ? undefined : v;
              });
            }
          })
          TapRow({
            title: R.s('ipv6_address'),
            summary: this.ipv6,
            rowEnabled: !this.usePull,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('ipv6_address', this.ipv6, R.s('ipv6_dialog_tile'), (v: string) => {
                this.ipv6 = v;
                this.profile.mIPv6Address = v === '' ? undefined : v;
              });
            }
          })
          CheckRow({
            title: R.s('no_bind'),
            summary: R.s('nobind_summary'),
            checked: this.nobind,
            showDivider: false,
            darkMode: true,
            onChange: (v: boolean) => {
              this.nobind = v;
              this.profile.mNobind = v;
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 0, bottom: 0 })

        PrefCategory({ title: R.s('dns'), darkMode: true })
        Column() {
          CheckRow({
            title: R.s('override_dns'),
            summary: R.s('dns_override_summary'),
            checked: this.overrideDNS,
            rowEnabled: this.usePull,
            darkMode: true,
            onChange: (v: boolean) => {
              this.overrideDNS = v;
              this.profile.mOverrideDNS = v;
            }
          })
          TapRow({
            title: R.s('searchdomain'),
            summary: this.searchDomain,
            rowEnabled: this.dnsEditable(),
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('searchdomain', this.searchDomain, '', (v: string) => {
                this.searchDomain = v;
                this.profile.mSearchDomain = v;
              });
            }
          })
          TapRow({
            title: R.s('dns_server'),
            summary: this.dnsSummary(this.dns1),
            rowEnabled: this.dnsEditable(),
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('dns_server', this.dns1, R.s('dns1_summary'), (v: string) => {
                this.dns1 = v;
                this.profile.mDNS1 = v;
              });
            }
          })
          TapRow({
            title: R.s('backup_dns'),
            summary: this.dnsSummary(this.dns2),
            rowEnabled: this.dnsEditable(),
            showDivider: false,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('backup_dns', this.dns2, R.s('secondary_dns_message'), (v: string) => {
                this.dns2 = v;
                this.profile.mDNS2 = v;
              });
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ bottom: 32 })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(TAB_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TAB_BACKGROUND)
  }

  private promptEdit(titleKey: string, initial: string, messageKey: string, onOk: (v: string) => void): void {
    this.editModel.title = R.s(titleKey);
    this.editModel.message = messageKey === '' ? '' : R.s(messageKey);
    this.editModel.initial = initial;
    this.editModel.placeholder = '';
    this.editModel.isPassword = false;
    this.editModel.multiLine = false;
    this.editModel.okText = R.s('ok');
    this.editModel.cancelText = R.s('cancel');
    this.editModel.neutralText = '';
    this.editModel.onOk = onOk;
    this.editDialog.open();
  }
}
