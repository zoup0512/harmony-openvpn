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
import { CredentialsDialog, CredentialsDialogModel } from '../CredentialsDialog';
import notificationManager from '@ohos.notificationManager';

const PROFILES_BACKGROUND: string = Theme.WINDOW_BG;
const PROFILES_CARD_BACKGROUND: string = Theme.CARD_BG;
const PROFILES_TEXT_PRIMARY: string = Theme.TEXT_PRIMARY;
const PROFILES_TEXT_SECONDARY: string = Theme.TEXT_SECONDARY;
const PROFILES_NOTICE_BACKGROUND: string = '#1AFFA726';

@Component
export struct ProfilesTab {
  @Prop @Watch('onSortTick') sortTick: number = 0;
  @State profiles: VpnProfile[] = [];
  @State connectionStatusLabel: string = '';
  @State activeProfileUuid: string = '';
  @State vpnActive: boolean = false;
  @State statusRenderTick: number = 0;
  @State notifPermissionMissing: boolean = false;
  onImportProfile: () => void = () => {
  };
  private timerId: number = -1;
  private credentialsModel: CredentialsDialogModel = new CredentialsDialogModel();
  private credentialsDialogController: CustomDialogController = new CustomDialogController({
    builder: CredentialsDialog({ model: this.credentialsModel }),
    autoCancel: false,
    customStyle: true
  });

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
    if (VpnStatus.lastState === 'AUTH_FAILED') {
      return this.authenticationFailureLabel();
    }
    if (VpnStatus.lastState === 'SESSION_EXPIRED') {
      return R.s('state_auth_failed');
    }
    if (!VpnStatus.isVPNActive()) {
      return R.s('state_disconnected');
    }
    switch (VpnStatus.lastState) {
      case 'CONNECTED':
        return R.s('state_connected');
      case 'RESOLVE':
        return R.s('state_resolving');
      case 'TCP_CONNECT':
        return R.s('state_connecting_tcp');
      case 'GET_CONFIG':
        return R.s('state_building_config');
      case 'USER_INPUT':
        return R.s('state_waiting_for_user_input');
      case 'AUTH_PENDING':
        return R.s('state_waiting_for_authentication');
      case 'AUTH_FAILED':
      case 'SESSION_EXPIRED':
        return R.s('state_auth_failed');
      default:
        return R.s('state_connecting');
    }
  }

  private authenticationFailureLabel(): string {
    let fallback = R.s('state_auth_failed');
    let reason = VpnStatus.lastCleanMessage.trim();
    if (reason === '' || reason === 'Authentication failed' || reason === fallback) {
      return fallback;
    }
    let upperReason = reason.toUpperCase();
    if (upperReason.indexOf('CRV1:') !== -1 || upperReason.indexOf('SCRV1:') !== -1 ||
      upperReason.indexOf('AUTH_TOKEN') !== -1 || upperReason.indexOf('SESSION_TOKEN') !== -1) {
      return fallback;
    }
    reason = reason.replace(/[\r\n]+/g, ' ').trim();
    if (reason.length > 160) {
      reason = reason.substring(0, 157) + '...';
    }
    return `${fallback}: ${reason}`;
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

  private requestCredentials(p: VpnProfile): void {
    // No start request exists yet at this point, so the global connection
    // status must stay untouched: marking USER_INPUT here and only rolling it
    // back on submit left the switch stuck "on" with a waiting-for-input
    // label after Cancel, and clobbered the status of an already-connected
    // profile while the dialog was open.
    this.credentialsModel.title = R.s('credentials_title');
    this.credentialsModel.message = R.s('credentials_message');
    this.credentialsModel.username = p.mUsername === undefined ? '' : p.mUsername;
    this.credentialsModel.password = '';
    this.credentialsModel.usernamePlaceholder = R.s('credentials_username_placeholder');
    this.credentialsModel.passwordPlaceholder = R.s('credentials_password_placeholder');
    this.credentialsModel.okText = R.s('submit');
    this.credentialsModel.cancelText = R.s('cancel');
    this.credentialsModel.onOk = (username: string, password: string): boolean => {
      let trimmedUsername = username.trim();
      if (trimmedUsername === '' || password === '') {
        promptAction.showToast({ message: R.s('credentials_required') });
        return false;
      }
      this.beginVPN(p, trimmedUsername, password);
      return true;
    };
    this.credentialsModel.onCancel = () => {
      // Rebuild the list so the toggled switch snaps back to isOn=false; a
      // Toggle only re-reads isOn when its ForEach item is recreated.
      this.statusRenderTick++;
      this.refreshStatus();
      this.reload();
    };
    this.credentialsDialogController.open();
  }

  private beginVPN(p: VpnProfile, username: string = '', password: string = ''): void {
    ProfileManager.updateLRU(p);
    VpnController.startVpn(p.getUUID(), 'main profile list', '', '', '', username, password).catch((e: Error) => {
      promptAction.showToast({ message: `${e.message}` });
      this.statusRenderTick++;
      this.reload();
    });
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
    if (missing === 'password' && p.isUserPWAuth()) {
      this.requestCredentials(p);
      return;
    }
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
    this.beginVPN(p);
  }

  private editVPN(uuid: string): void {
    let params: Record<string, Object> = { 'uuid': uuid };
    let opt: router.RouterOptions = {
      url: 'pages/ProfileEdit',
      params: params
    };
    router.pushUrl(opt);
  }

  private handleProfileToggle(p: VpnProfile, isOn: boolean): void {
    let active = this.isActive(p);
    if (isOn) {
      if (!active) {
        this.startVPN(p);
      }
    } else if (active) {
      this.confirmDisconnect();
    } else {
      this.reload();
    }
    this.statusRenderTick++;
  }

  private connectionStatusColor(): string {
    if (VpnStatus.lastState === 'AUTH_FAILED' || VpnStatus.lastState === 'SESSION_EXPIRED') {
      return Theme.WARNING_RED;
    }
    if (!VpnStatus.isVPNActive()) {
      return PROFILES_TEXT_SECONDARY;
    }
    return VpnStatus.lastState === 'CONNECTED' ? Theme.SUCCESS : Theme.ACCENT;
  }

  private connectionStatusBackground(): string {
    if (VpnStatus.lastState === 'AUTH_FAILED' || VpnStatus.lastState === 'SESSION_EXPIRED') {
      return '#14FF0000';
    }
    if (!VpnStatus.isVPNActive()) {
      return '#0F000000';
    }
    return VpnStatus.lastState === 'CONNECTED' ? '#142E7D32' : '#1AFFA726';
  }

  @Builder
  NotificationPermissionCard() {
    Row() {
      Image($r('app.media.ic_bell'))
        .width(20)
        .height(20)
        .fillColor(Theme.ACCENT)
      Text(R.s('missing_notification_permission'))
        .fontSize(13)
        .fontColor(PROFILES_TEXT_PRIMARY)
        .lineHeight(19)
        .padding({ left: 10 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .margin({ left: 12, right: 12, top: 12, bottom: 4 })
    .backgroundColor(PROFILES_NOTICE_BACKGROUND)
    .border({ width: 1, color: Theme.ACCENT })
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      notificationManager.requestEnableNotification().then(() => {
        this.notifPermissionMissing = false;
      }).catch(() => {
      });
    })
  }

  @Builder
  EmptyState() {
    Column() {
      Image($r('app.media.ic_import'))
        .width(44)
        .height(44)
        .fillColor(Theme.PRIMARY)
      Text(R.s('no_vpn_profiles_defined'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(PROFILES_TEXT_PRIMARY)
        .margin({ top: 16 })
      Text(R.s('openvpn_is_no_free_vpn'))
        .fontSize(14)
        .fontColor(PROFILES_TEXT_SECONDARY)
        .lineHeight(21)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, top: 10 })
      Button(R.s('menu_import_short'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.WHITE)
        .height(40)
        .padding({ left: 24, right: 24 })
        .backgroundColor(Theme.PRIMARY)
        .borderRadius(20)
        .margin({ top: 20 })
        .onClick(() => {
          this.onImportProfile();
        })
      Text(R.s('vpn_import_hint'))
        .fontSize(13)
        .fontColor(PROFILES_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, top: 12 })
      Text(R.s('faq_hint'))
        .fontSize(13)
        .fontColor(PROFILES_TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, top: 8 })
    }
    .justifyContent(FlexAlign.Center)
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  ConnectionStatusSummary() {
    Row() {
      Text('●')
        .fontSize(10)
        .fontColor(this.connectionStatusColor())
      Text(this.connectionStatusLabel)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.connectionStatusColor())
        .padding({ left: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ProfileCard(p: VpnProfile) {
    Row() {
      Column() {
        Toggle({ type: ToggleType.Switch, isOn: this.isActive(p) })
          .width(48)
          .height(28)
          .selectedColor(Theme.ACCENT)
          .onChange((isOn: boolean) => {
            this.handleProfileToggle(p, isOn);
          })
      }
      .width(60)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text(p.getName())
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(PROFILES_TEXT_PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.serverName(p))
          .fontSize(13)
          .fontColor(PROFILES_TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
        if (this.isActive(p)) {
          Text(this.connectionStatusLabel)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.connectionStatusColor())
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .margin({ top: 7 })
            .backgroundColor(this.connectionStatusBackground())
            .borderRadius(10)
        }
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
          .width(20)
          .height(20)
          .fillColor(PROFILES_TEXT_SECONDARY)
      }
      .width(52)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.editVPN(p.getUUID());
      })
    }
    .width('100%')
    .height(104)
    .padding({ left: 4, right: 4 })
    .margin({ top: 4, bottom: 4 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(PROFILES_CARD_BACKGROUND)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(12)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.notifPermissionMissing) {
          this.NotificationPermissionCard()
        }

        if (this.profiles.length === 0) {
          this.EmptyState()
        } else {
          this.ConnectionStatusSummary()

          List() {
            ForEach(this.profiles, (p: VpnProfile) => {
              ListItem() {
                this.ProfileCard(p)
              }
            }, (p: VpnProfile) => `${p.getUUID()}-${p.mVersion}-${p.getName()}-${this.statusRenderTick}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 12 })
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
