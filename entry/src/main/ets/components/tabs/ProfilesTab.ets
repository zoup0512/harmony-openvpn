/**
 * Profiles tab — the VPN profile list, per-item connect/disconnect and edit,
 * notification permission hint, empty view, and list-local add action.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { GP } from '../../common/GP';
import { VpnProfile, ProfileError } from '../../core/VpnProfile';
import { ProfileManager } from '../../core/ProfileManager';
import { VpnStatus } from '../../core/VpnStatus';
import { profileErrorText } from '../../common/ProfileChecks';
import { VpnController } from '../../vpn/VpnController';
import notificationManager from '@ohos.notificationManager';

const PROFILES_BACKGROUND: string = Theme.CARD_BG;
const PROFILES_TEXT_PRIMARY: string = Theme.TEXT_PRIMARY;
const PROFILES_TEXT_SECONDARY: string = Theme.TEXT_SECONDARY;
const PROFILES_NOTICE_BACKGROUND: string = '#3D3F51B5';

@Component
export struct ProfilesTab {
  @Prop @Watch('onSortTick') sortTick: number = 0;
  @State profiles: VpnProfile[] = [];
  @State connectionStatusLabel: string = '';
  @State activeProfileUuid: string = '';
  @State vpnActive: boolean = false;
  @State statusRenderTick: number = 0;
  @State notifPermissionMissing: boolean = false;
  private timerId: number = -1;

  onSortTick(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.refreshStatus();
    this.reload();
    this.checkNotificationPermission();
    this.timerId = setInterval(() => {
      this.refreshStatus();
      this.reload();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private refreshStatus(): void {
    VpnStatus.restoreFromSnapshot();
    let nextActive = VpnStatus.isVPNActive();
    let nextUuid = VpnStatus.getLastConnectedVPNProfile() ?? '';
    if (nextActive !== this.vpnActive || nextUuid !== this.activeProfileUuid) {
      this.vpnActive = nextActive;
      this.activeProfileUuid = nextUuid;
      this.statusRenderTick++;
    }
    this.connectionStatusLabel = this.buildConnectionStatusLabel();
  }

  private buildConnectionStatusLabel(): string {
    if (!VpnStatus.isVPNActive()) {
      return R.s('state_disconnected').toUpperCase();
    }
    switch (VpnStatus.lastState) {
      case 'CONNECTED':
        return R.s('state_connected').toUpperCase();
      case 'RESOLVE':
        return R.s('state_resolving').toUpperCase();
      case 'TCP_CONNECT':
        return R.s('state_connecting_tcp').toUpperCase();
      case 'GET_CONFIG':
        return R.s('state_building_config').toUpperCase();
      default:
        return R.s('state_connecting').toUpperCase();
    }
  }

  private checkNotificationPermission(): void {
    notificationManager.isNotificationEnabled().then((enabled: boolean) => {
      this.notifPermissionMissing = !enabled;
    }).catch(() => {
      this.notifPermissionMissing = false;
    });
  }

  private reload(): void {
    let list = ProfileManager.getProfiles();
    let byLru = GP.getBool('sortProfilesByLRU', false);
    if (byLru) {
      list.sort((a: VpnProfile, b: VpnProfile) => {
        if (b.mLastUsed !== a.mLastUsed) {
          return b.mLastUsed - a.mLastUsed;
        }
        return a.getName().localeCompare(b.getName());
      });
    } else {
      list.sort((a: VpnProfile, b: VpnProfile) => a.getName().localeCompare(b.getName()));
    }
    this.profiles = list;
  }

  private serverName(p: VpnProfile): string {
    let fallback = '';
    for (let connection of p.mConnections) {
      let server = connection.mServerName.trim();
      if (server === '') {
        continue;
      }
      if (fallback === '') {
        fallback = server;
      }
      if (connection.mEnabled) {
        return server;
      }
    }
    if (fallback !== '') {
      return fallback;
    }
    if (p.mServerName.trim() !== '') {
      return p.mServerName.trim();
    }
    return R.s('no_data');
  }

  private startOrStopVPN(p: VpnProfile): void {
    if (VpnStatus.isVPNActive() && VpnStatus.getLastConnectedVPNProfile() === p.getUUID()) {
      this.confirmDisconnect();
      return;
    }
    this.startVPN(p);
  }

  private confirmDisconnect(): void {
    let primBtn: AlertDialogButtonBaseOptions = {
      value: R.s('cancel'),
      action: () => {
        this.reload();
      }
    };
    let secBtn: AlertDialogButtonBaseOptions = {
      value: R.s('cancel_connection'),
      fontColor: Theme.PRIMARY,
      action: () => {
        VpnController.stopVpn().catch(() => {
        });
        VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'));
        this.refreshStatus();
        this.reload();
      }
    };
    let dialogParams: AlertDialogParamWithButtons = {
      title: R.s('title_cancel'),
      message: R.s('cancel_connection_query'),
      primaryButton: primBtn,
      secondaryButton: secBtn
    };
    AlertDialog.show(dialogParams);
  }

  private startVPN(p: VpnProfile): void {
    let checkResult = p.checkProfile(false);
    if (checkResult !== ProfileError.NO_ERROR) {
      let confBtn: AlertDialogButtonBaseOptions = {
        value: R.s('ok'),
        action: () => {
          this.reload();
        }
      };
      let dialogParams: AlertDialogParamWithConfirm = {
        title: R.s('config_error_found'),
        message: profileErrorText(checkResult),
        confirm: confBtn
      };
      AlertDialog.show(dialogParams);
      return;
    }
    let missing = p.needUserPWInputStr();
    if (missing !== '') {
      let confBtn: AlertDialogButtonBaseOptions = {
        value: R.s('ok'),
        action: () => {
          this.editVPN(p.getUUID());
        }
      };
      let dialogParams: AlertDialogParamWithConfirm = {
        title: R.s('config_error_found'),
        message: `${R.s(missing)}\n${R.s('pw_query_hint')}`,
        confirm: confBtn
      };
      AlertDialog.show(dialogParams);
      return;
    }
    ProfileManager.updateLRU(p);
    VpnController.startVpn(p.getUUID(), 'main profile list').catch((e: Error) => {
      promptAction.showToast({ message: `${e.message}` });
      this.reload();
    });
  }

  private editVPN(uuid: string): void {
    let params: Record<string, Object> = { 'uuid': uuid };
    let opt: router.RouterOptions = {
      url: 'pages/ProfileEdit',
      params: params
    };
    router.pushUrl(opt);
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.notifPermissionMissing) {
          Row() {
            Image($r('app.media.ic_bell'))
              .width(24)
              .height(24)
              .fillColor(Theme.ACCENT)
            Text(R.s('missing_notification_permission'))
              .fontSize(13)
              .fontColor(PROFILES_TEXT_PRIMARY)
              .padding({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')
          .padding(8)
          .backgroundColor(PROFILES_NOTICE_BACKGROUND)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            notificationManager.requestEnableNotification().then(() => {
              this.notifPermissionMissing = false;
            }).catch(() => {
            });
          })
        }

        if (this.profiles.length === 0) {
          Column() {
            Text(R.s('no_vpn_profiles_defined'))
              .fontSize(22)
              .fontColor(PROFILES_TEXT_PRIMARY)
            Text(R.s('openvpn_is_no_free_vpn'))
              .fontSize(14)
              .fontColor(PROFILES_TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24, top: 12, bottom: 12 })
            Text(R.s('add_new_vpn_hint'))
              .fontSize(14)
              .fontColor(PROFILES_TEXT_PRIMARY)
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24 })
            Text(R.s('vpn_import_hint'))
              .fontSize(14)
              .fontColor(PROFILES_TEXT_PRIMARY)
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24, top: 12 })
            Text(R.s('faq_hint'))
              .fontSize(14)
              .fontColor(PROFILES_TEXT_PRIMARY)
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24, top: 12 })
          }
          .justifyContent(FlexAlign.Center)
          .layoutWeight(1)
          .width('100%')
        } else {
          Text(this.connectionStatusLabel)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(PROFILES_TEXT_PRIMARY)
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding({ left: 20, right: 20, top: 24, bottom: 12 })

          List() {
            ForEach(this.profiles, (p: VpnProfile) => {
              ListItem() {
                Row() {
                  Column() {
                    Toggle({ type: ToggleType.Switch, isOn: this.isActive(p) })
                      .width(72)
                      .height(40)
                      .selectedColor(Theme.ACCENT)
                      .onChange((isOn: boolean) => {
                        if (isOn) {
                          this.vpnActive = true;
                          this.activeProfileUuid = p.getUUID();
                        }
                        this.startOrStopVPN(p);
                        this.statusRenderTick++;
                        this.reload();
                      })
                  }
                  .width(112)
                  .height('100%')
                  .justifyContent(FlexAlign.Center)

                  Column() {
                    Text(this.serverName(p))
                      .fontSize(16)
                      .fontColor(PROFILES_TEXT_SECONDARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 8 })
                    Text(`[${p.getName()}]`)
                      .fontSize(16)
                      .fontColor(PROFILES_TEXT_SECONDARY)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .layoutWeight(1)
                  .height('100%')
                  .alignItems(HorizontalAlign.Start)
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => {
                    this.startOrStopVPN(p);
                  })

                  Column() {
                    Image($r('app.media.ic_edit'))
                      .width(30)
                      .height(30)
                      .fillColor(PROFILES_TEXT_PRIMARY)
                  }
                  .width(72)
                  .height('100%')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .onClick(() => {
                    this.editVPN(p.getUUID());
                  })
                }
                .width('100%')
                .height(136)
                .alignItems(VerticalAlign.Center)
                .backgroundColor(PROFILES_BACKGROUND)
              }
            }, (p: VpnProfile) => `${p.getUUID()}-${p.mVersion}-${p.getName()}-${this.statusRenderTick}`)
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PROFILES_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PROFILES_BACKGROUND)
  }

  private isActive(p: VpnProfile): boolean {
    return this.activeProfileUuid === p.getUUID() && this.vpnActive;
  }
}
