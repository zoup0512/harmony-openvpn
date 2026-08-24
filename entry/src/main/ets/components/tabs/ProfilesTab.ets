/**
 * Profiles tab — replicates VPNProfileList: the VPN profile list, per item
 * connect/disconnect (left side) and edit (pencil icon), empty view, and the
 * notification permission hint.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { GP } from '../../common/GP';
import { VpnProfile, ProfileError } from '../../core/VpnProfile';
import { ProfileManager } from '../../core/ProfileManager';
import { VpnStatus } from '../../core/VpnStatus';
import { getWarningText, profileErrorText } from '../../common/ProfileChecks';
import { VpnController } from '../../vpn/VpnController';
import { InputDialog } from '../InputDialog';
import notificationManager from '@ohos.notificationManager';

@Component
export struct ProfilesTab {
  @Prop @Watch('onSortTick') sortTick: number = 0;
  @State profiles: VpnProfile[] = [];
  @State lastStatusMessage: string = '';
  @State notifPermissionMissing: boolean = false;
  private timerId: number = -1;

  onSortTick(): void {
    this.reload();
  }

  aboutToAppear(): void {
    this.reload();
    this.checkNotificationPermission();
    this.timerId = setInterval(() => {
      VpnStatus.restoreFromSnapshot();
      this.reload();
      this.lastStatusMessage = VpnStatus.lastCleanLogMessage();
    }, 2000);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
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

  private isDefaultVPN(p: VpnProfile): boolean {
    let alwaysOn = ProfileManager.getAlwaysOnVPN();
    return alwaysOn !== undefined && alwaysOn !== null && alwaysOn.getUUID() === p.getUUID();
  }

  private subtitle(p: VpnProfile): string {
    let active = VpnStatus.getLastConnectedVPNProfile() === p.getUUID() && VpnStatus.isVPNActive();
    if (active) {
      return this.lastStatusMessage;
    }
    let warning = getWarningText(p);
    if (this.isDefaultVPN(p)) {
      warning = warning === '' ? 'Default VPN' : `${warning}, Default VPN`;
    }
    return warning;
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
      }
    };
    let secBtn: AlertDialogButtonBaseOptions = {
      value: R.s('cancel_connection'),
      fontColor: Theme.PRIMARY,
      action: () => {
        VpnController.stopVpn().catch(() => {
        });
        VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'));
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
    });
  }

  private editVPN(uuid: string): void {
    let params: Record<string, Object> = { 'uuid': uuid };
    let opt: router.RouterOptions = {
      url: 'pages/VPNPreferences',
      params: params
    };
    router.pushUrl(opt);
  }

  build() {
    if (this.profiles.length === 0) {
      Column() {
        Text(R.s('no_vpn_profiles_defined'))
          .fontSize(22)
          .fontColor(Theme.TEXT_PRIMARY)
        Text(R.s('openvpn_is_no_free_vpn'))
          .fontSize(14)
          .fontColor(Theme.TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
        Text(R.s('add_new_vpn_hint'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24 })
        Text(R.s('vpn_import_hint'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, top: 12 })
        Text(R.s('faq_hint'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .textAlign(TextAlign.Center)
          .padding({ left: 24, right: 24, top: 12 })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
      .height('100%')
    } else {
      Column() {
        if (this.notifPermissionMissing) {
          Row() {
            Image($r('app.media.ic_bell'))
              .width(24).height(24).fillColor(Theme.PRIMARY)
            Text(R.s('missing_notification_permission'))
              .fontSize(13)
              .fontColor(Theme.TEXT_PRIMARY)
              .padding({ left: 8 })
          }
          .width('100%')
          .padding(8)
          .backgroundColor('#3D3F51B5')
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            notificationManager.requestEnableNotification().then(() => {
              this.notifPermissionMissing = false;
            }).catch(() => {
            });
          })
        }
        List() {
          ForEach(this.profiles, (p: VpnProfile) => {
            ListItem() {
              Row() {
                Column() {
                  Text(p.getName())
                    .fontSize(16)
                    .fontColor(Theme.TEXT_PRIMARY)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (this.subtitle(p) !== '') {
                    Text(this.subtitle(p))
                      .fontSize(12)
                      .fontColor(this.isActive(p) ? Theme.TEXT_SECONDARY : Theme.WARNING_RED)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 12 })
                .height(64)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.startOrStopVPN(p);
                })

                Divider()
                  .vertical(true)
                  .height(54)
                  .width(2)
                  .color('#1F000000')

                Image($r('app.media.ic_edit'))
                  .width(24).height(24).fillColor(Theme.TEXT_SECONDARY)
                  .padding({ left: 15, right: 15 })
                  .height(64)
                  .onClick(() => {
                    this.editVPN(p.getUUID());
                  })
              }
              .width('100%')
              .backgroundColor(Theme.CARD_BG)
              .border({ width: { bottom: 1 }, color: '1F000000' })
            }
          }, (p: VpnProfile) => `${p.getUUID()}-${p.mVersion}-${p.getName()}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }

  private isActive(p: VpnProfile): boolean {
    return VpnStatus.getLastConnectedVPNProfile() === p.getUUID() && VpnStatus.isVPNActive();
  }
}
