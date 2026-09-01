/**
 * Advanced (obscure) tab — port of Settings_Obscure + vpn_obscure.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { PrefCategory, CheckRow, TapRow } from '../PrefRows';
import { InputDialog, InputDialogModel } from '../InputDialog';
import { showSingleChoice, crmEntries, crmValues } from './SettingsCommon';
import { promptAction } from '@kit.ArkUI';

const TAB_BACKGROUND: string = Theme.DARK_BACKGROUND;
const TAB_SURFACE: string = Theme.DARK_SURFACE;
const TAB_BORDER: string = Theme.DARK_BORDER;

@Component
export struct ObscureTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State persistTun: boolean = false;
  @State peerInfo: boolean = false;
  @State useRandomHostname: boolean = false;
  @State useFloat: boolean = false;
  @State mssFixEnabled: boolean = false;
  @State mssFixValue: string = '1280';
  @State tunMtu: string = '1500';
  @State useCustomOptions: boolean = false;
  @State customOptions: string = '';
  @State connectRetryMax: string = '-1';
  @State connectRetry: string = '2';
  @State connectRetryMaxTime: string = '300';
  private editModel: InputDialogModel = new InputDialogModel();
  private editDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.editModel, darkMode: true }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let p = this.profile;
    this.persistTun = p.mPersistTun;
    this.peerInfo = p.mPushPeerInfo;
    this.useRandomHostname = p.mUseRandomHostname;
    this.useFloat = p.mUseFloat;
    this.mssFixEnabled = p.mMssFix !== 0;
    this.mssFixValue = p.mMssFix === 0 ? `${VpnProfile.DEFAULT_MSSFIX_SIZE}` : `${p.mMssFix}`;
    this.tunMtu = p.mTunMtu < 48 ? '1500' : `${p.mTunMtu}`;
    this.useCustomOptions = p.mUseCustomConfig;
    this.customOptions = p.mCustomConfigOptions;
    this.connectRetryMax = p.mConnectRetryMax;
    this.connectRetry = p.mConnectRetry;
    this.connectRetryMaxTime = p.mConnectRetryMaxTime;
  }

  private promptEdit(titleKey: string, messageKey: string, initial: string, validate: (v: string) => boolean,
    onOk: (v: string) => void): void {
    this.editModel.title = R.s(titleKey);
    this.editModel.message = messageKey === '' ? '' : R.s(messageKey);
    this.editModel.initial = initial;
    this.editModel.multiLine = false;
    this.editModel.okText = R.s('ok');
    this.editModel.cancelText = R.s('cancel');
    this.editModel.neutralText = '';
    this.editModel.onOk = (v: string) => {
      if (!validate(v)) {
        return;
      }
      onOk(v);
    };
    this.editDialog.open();
  }

  build() {
    Scroll() {
      Column() {
        PrefCategory({ title: R.s('client_behaviour'), darkMode: true })
        Column() {
          CheckRow({
            title: R.s('persistent_tun_title'),
            summary: R.s('persisttun_summary'),
            checked: this.persistTun,
            darkMode: true,
            onChange: (v: boolean) => {
              this.persistTun = v;
              this.profile.mPersistTun = v;
            }
          })
          CheckRow({
            title: R.s('pushpeerinfo'),
            summary: R.s('pushpeerinfosummary'),
            checked: this.peerInfo,
            darkMode: true,
            onChange: (v: boolean) => {
              this.peerInfo = v;
              this.profile.mPushPeerInfo = v;
            }
          })
          CheckRow({
            title: R.s('random_host_prefix'),
            summary: R.s('random_host_summary'),
            checked: this.useRandomHostname,
            darkMode: true,
            onChange: (v: boolean) => {
              this.useRandomHostname = v;
              this.profile.mUseRandomHostname = v;
            }
          })
          CheckRow({
            title: R.s('float_title'),
            summary: R.s('float_summary'),
            checked: this.useFloat,
            showDivider: false,
            darkMode: true,
            onChange: (v: boolean) => {
              this.useFloat = v;
              this.profile.mUseFloat = v;
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 0, bottom: 0 })

        PrefCategory({ title: R.s('payload_options'), darkMode: true })
        Column() {
          CheckRow({
            title: R.s('mssfix_checkbox'),
            checked: this.mssFixEnabled,
            darkMode: true,
            onChange: (v: boolean) => {
              this.mssFixEnabled = v;
              if (!v) {
                this.profile.mMssFix = 0;
              } else {
                let n = parseInt(this.mssFixValue);
                this.profile.mMssFix = isNaN(n) ? VpnProfile.DEFAULT_MSSFIX_SIZE : n;
              }
            }
          })
          if (this.mssFixEnabled) {
            TapRow({
              title: R.s('mssfix_dialogtitle'),
              summary: R.s('mssfix_value_summary', this.mssFixValue),
              darkMode: true,
              onRowClick: () => {
                this.promptEdit('mssfix_dialogtitle', 'mssfix_value_dialog', this.mssFixValue,
                  (v: string) => {
                    let n = parseInt(v);
                    if (isNaN(n) || n < 0 || n > 9000) {
                      promptAction.showToast({ message: R.s('mssfix_invalid_value') });
                      return false;
                    }
                    return true;
                  }, (v: string) => {
                    this.mssFixValue = v;
                    this.profile.mMssFix = parseInt(v);
                  });
              }
            })
          }
          TapRow({
            title: R.s('tun_mtu_title'),
            summary: this.tunMtu === '1500' ? R.s('mtu_default_summary') : R.s('mtu_configured_summary', this.tunMtu),
            showDivider: false,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('tun_mtu_title', 'mtu_dialog_message', this.tunMtu,
                (v: string) => {
                  let n = parseInt(v);
                  if (isNaN(n) || n < 48 || n > 9000) {
                    promptAction.showToast({ message: R.s('mtu_invalid_value') });
                    return false;
                  }
                  return true;
                }, (v: string) => {
                  this.tunMtu = v;
                  this.profile.mTunMtu = parseInt(v);
                });
            }
          })
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 0, bottom: 0 })

        PrefCategory({ title: R.s('custom_config_title'), darkMode: true })
        Column() {
          CheckRow({
            title: R.s('custom_config_title'),
            summary: R.s('custom_config_summary'),
            checked: this.useCustomOptions,
            darkMode: true,
            onChange: (v: boolean) => {
              this.useCustomOptions = v;
              this.profile.mUseCustomConfig = v;
            }
          })
          if (this.useCustomOptions) {
            TapRow({
              title: R.s('custom_options_title'),
              summary: this.customOptions,
              showDivider: false,
              darkMode: true,
              onRowClick: () => {
                this.editModel.title = R.s('custom_options_title');
                this.editModel.message = R.s('custom_option_warning');
                this.editModel.initial = this.customOptions;
                this.editModel.multiLine = true;
                this.editModel.okText = R.s('ok');
                this.editModel.cancelText = R.s('cancel');
                this.editModel.neutralText = '';
                this.editModel.onOk = (v: string) => {
                  this.customOptions = v;
                  this.profile.mCustomConfigOptions = v;
                };
                this.editDialog.open();
              }
            })
          }
        }
        .width('100%')
        .backgroundColor(TAB_SURFACE)
        .border({ width: 1, color: TAB_BORDER })
        .borderRadius(16)
        .margin({ top: 0, bottom: 0 })

        PrefCategory({ title: R.s('reconnection_settings'), darkMode: true })
        Column() {
          TapRow({
            title: R.s('connection_retries'),
            summary: crmEntries()[crmValues().indexOf(this.connectRetryMax)],
            darkMode: true,
            onRowClick: () => {
              let values = crmValues();
              showSingleChoice(R.s('connection_retries'), crmEntries(), values.indexOf(this.connectRetryMax),
                (i: number) => {
                  this.connectRetryMax = values[i];
                  this.profile.mConnectRetryMax = values[i];
                });
            }
          })
          TapRow({
            title: R.s('connectretrywait'),
            summary: `${this.connectRetry} s`,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('connectretrywait', 'connectretrymessage', this.connectRetry,
                () => true, (v: string) => {
                  this.connectRetry = v === '' ? '2' : v;
                  this.profile.mConnectRetry = this.connectRetry;
                });
            }
          })
          TapRow({
            title: R.s('connectretrymaxtitle'),
            summary: `${this.connectRetryMaxTime} s`,
            showDivider: false,
            darkMode: true,
            onRowClick: () => {
              this.promptEdit('connectretrymaxtitle', 'connectretrymaxmessage', this.connectRetryMaxTime,
                () => true, (v: string) => {
                  this.connectRetryMaxTime = v === '' ? '300' : v;
                  this.profile.mConnectRetryMaxTime = this.connectRetryMaxTime;
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
}
