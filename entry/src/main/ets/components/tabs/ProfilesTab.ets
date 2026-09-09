/**
 * Profiles tab — the VPN profile list, per-item connect/disconnect and edit,
 * notification permission hint, empty view, and list-local add action.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile, ProfileError } from '../../core/VpnProfile';
import { ProfileManager } from '../../core/ProfileManager';
import { VpnStatus, StateListener, LogListener } from '../../core/VpnStatus';
import { LogItem, LogLevel } from '../../core/LogItem';
import { profileErrorText } from '../../common/ProfileChecks';
import { VpnController } from '../../vpn/VpnController';
import { CredentialsDialog, CredentialsDialogModel } from '../CredentialsDialog';
import notificationManager from '@ohos.notificationManager';
import { common } from '@kit.AbilityKit';
import { FileUtil } from '../../common/FileUtil';
import { ProfileShortcut } from '../../common/ProfileShortcut';
import { generateConfigFile, GenEnvInfo } from '../../core/ConfigGenerator';
import { pasteboard } from '@kit.BasicServicesKit';

@Observed
class ProfileCardView {
  uuid: string = '';
  name: string = '';
  server: string = '';
  logEntries: LogItem[] = [];
  active: boolean = false;
  busy: boolean = false;
  actionLabel: string = '启动';
  status: string = '';
  color: string = Theme.TEXT_SECONDARY;
  background: string = Theme.STATUS_IDLE_BG;
}

@Component
struct OpenVpnCard {
  @ObjectLink view: ProfileCardView;
  @Prop sequence: number = 0;
  @State expanded: boolean = false;
  @State searchText: string = '';
  @State logFilter: string = 'ALL';
  onAction: (uuid: string, action: string) => void = () => {};

  @Builder
  ActionButton(icon: Resource, label: string, selected: boolean, danger: boolean,
    action: () => void, enabled: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Image(icon).width(18).height(18).objectFit(ImageFit.Contain)
        .fillColor(!enabled ? Theme.TEXT_DISABLED :
          (selected ? Theme.WHITE : (danger ? Theme.FRP_LIST_DANGER : Theme.FRP_ACCENT)))
    }
    .width(32).height(32).padding(0).borderRadius(16)
    .backgroundColor(selected ? Theme.FRP_ACCENT : Theme.FRP_INPUT_BG)
    .enabled(enabled).accessibilityText(label)
    .accessibilityDescription(selected ? `${label}，已选中` : label).onClick(action)
  }

  @Builder
  FilterPill(label: string, value: string) {
    Button(label, { type: ButtonType.Normal })
      .width(38).height(22).padding(0).borderRadius(11).fontSize(13).fontWeight(FontWeight.Regular)
      .fontColor(this.logFilter === value ? Theme.FRP_ACCENT : Theme.FRP_LIST_TEXT_SECONDARY)
      .backgroundColor(this.logFilter === value ? Theme.FRP_FILTER_SELECTED_BG : Theme.FRP_INPUT_BG)
      .accessibilityDescription(this.logFilter === value ? `${label}，已选中` : label)
      .onClick(() => { this.logFilter = value; })
  }

  private filteredLogs(): LogItem[] {
    let keyword = this.searchText.trim().toLowerCase();
    return this.view.logEntries.filter((entry: LogItem) => {
      let levelMatches = this.logFilter === 'ALL' ||
        (this.logFilter === 'ERROR' && entry.level === LogLevel.ERROR) ||
        (this.logFilter === 'WARNING' && entry.level === LogLevel.WARNING) ||
        (this.logFilter === 'INFO' && entry.level === LogLevel.INFO);
      return levelMatches && (keyword === '' || entry.message.toLowerCase().indexOf(keyword) !== -1);
    });
  }

  private logColor(entry: LogItem): string {
    if (entry.level === LogLevel.ERROR) {
      return Theme.FRP_LIST_DANGER;
    }
    if (entry.level === LogLevel.WARNING) {
      return Theme.FRP_LOG_WARNING;
    }
    return Theme.FRP_LOG_TEXT;
  }

  private logText(entry: LogItem): string {
    let stamp = new Date(entry.logtime);
    let two = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    let level = entry.level === LogLevel.ERROR ? 'ERROR' :
      (entry.level === LogLevel.WARNING ? 'WARNING' : (entry.level === LogLevel.INFO ? 'INFO' : 'DEBUG'));
    return `${two(stamp.getHours())}:${two(stamp.getMinutes())}:${two(stamp.getSeconds())} [${level}] ${entry.message}`;
  }

  @Builder
  LogArea() {
    Column() {
      Row() {
        Text('运行日志').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(Theme.FRP_LIST_TEXT_PRIMARY).layoutWeight(1)
        Button('收起', { type: ButtonType.Normal })
          .width(44).height(22).padding(0).borderRadius(11).fontSize(13)
          .fontColor(Theme.FRP_LIST_TEXT_SECONDARY).backgroundColor(Theme.FRP_INPUT_BG)
          .onClick(() => { this.expanded = false; })
        Button('全屏', { type: ButtonType.Normal })
          .width(44).height(22).padding(0).borderRadius(11).fontSize(13)
          .fontColor(Theme.FRP_ACCENT).backgroundColor(Theme.FRP_INPUT_BG)
          .margin({ left: 6 })
          .onClick(() => router.pushUrl({ url: 'pages/LogWindow', params: { profileUuid: this.view.uuid } }))
      }.width('100%').height(22).alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        TextInput({ text: this.searchText, placeholder: '搜索日志' })
          .width(120).height(32).padding({ left: 12, right: 12 }).borderRadius(16)
          .fontSize(13).fontColor(Theme.FRP_LIST_TEXT_PRIMARY)
          .placeholderColor(Theme.FRP_LIST_TEXT_SECONDARY).backgroundColor(Theme.FRP_INPUT_BG)
          .onChange((value: string) => { this.searchText = value; })
        Row({ space: 6 }) {
          this.FilterPill('全部', 'ALL')
          this.FilterPill('错误', 'ERROR')
          this.FilterPill('警告', 'WARNING')
          this.FilterPill('信息', 'INFO')
        }.layoutWeight(1)
      }.width('100%').height(32).margin({ top: 10 }).alignItems(VerticalAlign.Center)

      if (this.filteredLogs().length === 0) {
        Column() {
          Text(this.view.logEntries.length === 0 ? '（进程未运行，无日志）' : '（没有匹配日志）')
            .fontSize(12).fontFamily('monospace').fontColor(Theme.FRP_LOG_TEXT)
        }.width('100%').height(160).padding(16).justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start).backgroundColor(Theme.FRP_LOG_BG).borderRadius(11)
          .margin({ top: 6 })
      } else {
        Scroll() {
          Column({ space: 6 }) {
            ForEach(this.filteredLogs(), (entry: LogItem, index?: number) => {
              Text(this.logText(entry)).fontSize(12).fontFamily('monospace')
                .fontColor(this.logColor(entry)).width('100%').copyOption(CopyOptions.LocalDevice)
            }, (entry: LogItem, index?: number) => `${entry.logtime}-${index}`)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').height(160).padding(16).backgroundColor(Theme.FRP_LOG_BG).borderRadius(11)
          .margin({ top: 6 })
      }

      Row({ space: 12 }) {
        Button('复制日志', { type: ButtonType.Normal }).height(24).padding({ left: 8, right: 8 })
          .borderRadius(12).fontSize(12).fontColor(Theme.FRP_LIST_TEXT_SECONDARY)
          .backgroundColor(Theme.FRP_INPUT_BG).accessibilityText('复制此配置最近会话')
          .onClick(() => this.onAction(this.view.uuid, 'copyLog'))
        Button('清空日志', { type: ButtonType.Normal }).height(24).padding({ left: 8, right: 8 })
          .borderRadius(12).fontSize(12).fontColor(Theme.FRP_LIST_DANGER)
          .backgroundColor(Theme.FRP_INPUT_BG).accessibilityText('清空此配置全部日志')
          .onClick(() => this.onAction(this.view.uuid, 'clearLog'))
      }.width('100%').justifyContent(FlexAlign.End).margin({ top: 6 })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Text(`${this.sequence}`).width(18).fontSize(14).fontColor(Theme.FRP_LIST_TEXT_SECONDARY)
          .maxLines(1)
        Text(this.view.name).fontSize(17).fontWeight(FontWeight.Medium)
          .fontColor(Theme.FRP_LIST_TEXT_PRIMARY).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).margin({ left: 12 })
        Text(this.view.status).height(22).lineHeight(22).fontSize(13).fontColor(this.view.color).maxLines(1)
          .padding({ left: 8, right: 8 }).backgroundColor(this.view.background).borderRadius(11)
      }.width('100%').height(22).alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        // Read ObjectLink fields in the render scope, not captured primitive Builder arguments.
        Button({ type: ButtonType.Normal }) {
          if (this.view.active) {
            Image($r('app.media.ic_frp_stop'))
              .width(18).height(18).objectFit(ImageFit.Contain)
              .fillColor(this.view.busy ? Theme.TEXT_DISABLED : Theme.WHITE)
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(18)
              .fontColor([this.view.busy ? Theme.TEXT_DISABLED : Theme.WHITE])
          }
        }.width(32).height(32).padding(0).borderRadius(16)
          .backgroundColor(Theme.FRP_ACCENT)
          .enabled(!this.view.busy).accessibilityText(this.view.actionLabel)
          .onClick(() => this.onAction(this.view.uuid, 'start'))
        this.ActionButton($r('app.media.ic_frp_edit'), '编辑', false, false,
          () => this.onAction(this.view.uuid, 'edit'))
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_frp_log')).width(18).height(18).objectFit(ImageFit.Contain)
            .fillColor(this.expanded ? Theme.WHITE : Theme.FRP_ACCENT)
        }.width(32).height(32).padding(0).borderRadius(16)
          .backgroundColor(this.expanded ? Theme.FRP_ACCENT : Theme.FRP_INPUT_BG)
          .accessibilityText('日志')
          .accessibilityDescription(this.expanded ? '日志，已选中' : '日志')
          .onClick(() => { this.expanded = !this.expanded; })
        this.ActionButton($r('app.media.ic_chart'), '流量统计', false, false,
          () => router.pushUrl({ url: 'pages/TrafficStats' }))
        this.ActionButton($r('app.media.ic_frp_save'), '保存', false, false,
          () => this.onAction(this.view.uuid, 'save'))
        this.ActionButton($r('app.media.ic_frp_share'), '分享', false, false,
          () => this.onAction(this.view.uuid, 'share'))
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.ic_frp_delete')).width(18).height(18).objectFit(ImageFit.Contain)
            .fillColor(this.view.active || this.view.busy ? Theme.TEXT_DISABLED : Theme.FRP_LIST_DANGER)
        }.width(32).height(32).padding(0).borderRadius(16)
          .backgroundColor(Theme.FRP_INPUT_BG)
          .enabled(!this.view.active && !this.view.busy).accessibilityText('删除').accessibilityDescription('删除')
          .onClick(() => this.onAction(this.view.uuid, 'delete'))
      }.width('100%').justifyContent(FlexAlign.Start).margin({ top: 12 })

      if (this.expanded) {
        Column() {
          this.LogArea()
        }.width('100%').margin({ top: 10 })
      }
    }.width('100%').padding(16).backgroundColor(Theme.FRP_CARD_BG)
      .borderRadius(Theme.FRP_CARD_RADIUS)
      .margin({ top: 12 }).alignItems(HorizontalAlign.Start)
  }
}

const PROFILES_BACKGROUND: string = Theme.FRP_PAGE_BG;
const PROFILES_TEXT_PRIMARY: string = Theme.TEXT_PRIMARY;
const PROFILES_TEXT_SECONDARY: string = Theme.TEXT_SECONDARY;

@Component
export struct ProfilesTab {
  @State profiles: ProfileCardView[] = [];
  @State connectionStatusLabel: string = '';
  @State activeProfileUuid: string = '';
  @State vpnActive: boolean = false;
  @State notifPermissionMissing: boolean = false;
  onImportProfile: () => void = () => {
  };
  private timerId: number = -1;
  private requestUuid: string = '';
  private requestAction: string = '';
  private stateListener: StateListener = () => {
    this.refreshStatus();
    this.reload();
  };
  private logListener: LogListener = () => this.refreshLogs();
  private credentialsModel: CredentialsDialogModel = new CredentialsDialogModel();
  private credentialsDialogController: CustomDialogController = new CustomDialogController({
    builder: CredentialsDialog({ model: this.credentialsModel }),
    autoCancel: false,
    customStyle: true
  });

  aboutToAppear(): void {
    this.refreshStatus();
    this.reload();
    this.checkNotificationPermission();
    VpnStatus.addStateListener(this.stateListener);
    VpnStatus.addLogListener(this.logListener);
    this.timerId = setInterval(() => {
      this.refreshStatus();
      this.reload();
    }, 2000);
  }

  aboutToDisappear(): void {
    VpnStatus.removeStateListener(this.stateListener);
    VpnStatus.removeLogListener(this.logListener);
    this.credentialsDialogController.close();
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
    list.sort((a: VpnProfile, b: VpnProfile) => a.getName().localeCompare(b.getName()));
    let next: ProfileCardView[] = [];
    for (let profile of list) {
      let row = this.profiles.find((item: ProfileCardView) => item.uuid === profile.getUUID());
      if (row === undefined) {
        row = new ProfileCardView();
        row.uuid = profile.getUUID();
      }
      row.name = profile.getName();
      row.server = this.serverName(profile);
      row.active = this.isActive(profile);
      // Connecting/USER_INPUT may still be cancelled through the existing stop flow.
      // Only the matching UUID owns that operation; requests block duplicate starts.
      row.busy = this.requestUuid !== '' || (this.vpnActive && !row.active);
      row.actionLabel = this.requestUuid === row.uuid ?
        (this.requestAction === 'stop' ? '停止中' : '启动中') : (row.active ? '停止' : '启动');
      let last = row.uuid === this.activeProfileUuid;
      row.status = last ? this.connectionStatusLabel : R.s('state_disconnected');
      row.color = last ? this.connectionStatusColor() : Theme.TEXT_SECONDARY;
      row.background = last ? this.connectionStatusBackground() : Theme.STATUS_IDLE_BG;
      next.push(row);
    }
    // Preserve observed row objects and UUID keys; only replace the array on membership/order changes.
    if (next.length !== this.profiles.length || next.some((row: ProfileCardView, index: number) =>
      row.uuid !== this.profiles[index].uuid)) {
      this.profiles = next;
    }
    this.refreshLogs();
  }

  private refreshLogs(): void {
    for (let row of this.profiles) {
      row.logEntries = VpnStatus.getlogbuffer(row.uuid).slice();
    }
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
    this.refreshStatus();
    this.reload();
    if (this.requestUuid !== '') {
      return;
    }
    if (this.isActive(p)) {
      this.confirmDisconnect(p.getUUID());
      return;
    }
    if (!this.vpnActive) {
      this.startVPN(p);
    }
  }

  private confirmDisconnect(uuid: string): void {
    let primBtn: AlertDialogButtonBaseOptions = {
      value: R.s('cancel'),
      fontColor: Theme.TEXT_SECONDARY,
      action: () => {
        this.reload();
      }
    };
    let secBtn: AlertDialogButtonBaseOptions = {
      value: R.s('cancel_connection'),
      fontColor: Theme.PRIMARY,
      action: () => {
        this.stopVPN(uuid);
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

  private stopVPN(uuid: string): void {
    this.requestUuid = uuid;
    this.requestAction = 'stop';
    VpnController.stopVpn().then(() => {
      VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'));
      this.requestUuid = '';
      this.requestAction = '';
      this.refreshStatus();
      this.reload();
    }).catch(() => {
      this.requestUuid = '';
      this.requestAction = '';
      this.reload();
    });
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
      this.refreshStatus();
      this.reload();
    };
    this.credentialsDialogController.open();
  }

  private beginVPN(p: VpnProfile, username: string = '', password: string = ''): void {
    ProfileManager.updateLRU(p);
    this.requestUuid = p.getUUID();
    this.requestAction = 'start';
    this.reload();
    this.runStart(p.getUUID(), username, password);
  }

  private async runStart(uuid: string, username: string, password: string): Promise<void> {
    try {
      await VpnController.startVpn(uuid, 'main profile list', '', '', '', username, password);
    } catch (e) {
      promptAction.showToast({ message: `${(e as Error).message}` });
    } finally {
      this.requestUuid = '';
      this.requestAction = '';
      this.refreshStatus();
      this.reload();
    }
  }

  private startVPN(p: VpnProfile): void {
    let checkResult = p.checkProfile(false);
    if (checkResult !== ProfileError.NO_ERROR) {
      let confBtn: AlertDialogButtonBaseOptions = {
        value: R.s('ok'),
        fontColor: Theme.PRIMARY,
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
        fontColor: Theme.PRIMARY,
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

  private connectionStatusColor(): string {
    if (VpnStatus.lastState === 'AUTH_FAILED' || VpnStatus.lastState === 'SESSION_EXPIRED') {
      return Theme.STATUS_ERROR;
    }
    if (!VpnStatus.isVPNActive()) {
      return PROFILES_TEXT_SECONDARY;
    }
    return VpnStatus.lastState === 'CONNECTED' ? Theme.STATUS_SUCCESS : Theme.STATUS_CONNECTING;
  }

  private connectionStatusBackground(): string {
    if (VpnStatus.lastState === 'AUTH_FAILED' || VpnStatus.lastState === 'SESSION_EXPIRED') {
      return Theme.STATUS_ERROR_BG;
    }
    if (!VpnStatus.isVPNActive()) {
      return Theme.STATUS_IDLE_BG;
    }
    return VpnStatus.lastState === 'CONNECTED' ? Theme.STATUS_SUCCESS_BG : Theme.STATUS_CONNECTING_BG;
  }

  @Builder
  NotificationPermissionCard() {
    Row() {
      Image($r('app.media.ic_bell'))
        .width(20)
        .height(20)
        .fillColor(Theme.NOTICE_LIGHT)
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
    .backgroundColor(Theme.NOTICE_LIGHT_BG)
    .border({ width: 1, color: Theme.NOTICE_LIGHT })
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

  private countActiveProfiles(): number {
    let count = 0;
    for (let profile of this.profiles) {
      if (profile.active) {
        count++;
      }
    }
    return count;
  }

  private countErrorProfiles(): number {
    if (VpnStatus.lastState !== 'AUTH_FAILED' && VpnStatus.lastState !== 'SESSION_EXPIRED') {
      return 0;
    }
    for (let profile of this.profiles) {
      if (profile.uuid === this.activeProfileUuid) {
        return 1;
      }
    }
    return 0;
  }

  @Builder
  StatusSummary() {
    Row() {
      Column() {
        Text('配置')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.profiles.length}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      Column() {
        Text('运行中')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.countActiveProfiles()}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countActiveProfiles() > 0 ? Theme.STATUS_SUCCESS : Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      Column() {
        Text('异常')
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
        Text(`${this.countErrorProfiles()}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.countErrorProfiles() > 0 ? Theme.STATUS_ERROR : Theme.TEXT_PRIMARY)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(Theme.CARD_BG)
    .border({ width: 1, color: Theme.DIVIDER })
    .borderRadius(12)
  }

  private copyLog(uuid: string): void {
    VpnStatus.restoreFromSnapshot();
    let text = VpnStatus.getlogbuffer(uuid).map((entry) => `${new Date(entry.logtime).toLocaleString()} ${entry.message}`).join('\n');
    if (text === '') {
      promptAction.showToast({ message: '暂无可复制日志' });
      return;
    }
    let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data)
      .then(() => promptAction.showToast({ message: R.s('log_copied_clipboard') }))
      .catch(() => promptAction.showToast({ message: '日志复制失败' }));
  }

  private askClearLog(uuid: string): void {
    AlertDialog.show({
      title: '清空此配置全部日志',
      message: '确定清空此配置全部会话日志（含历史）吗？不影响其他配置或全局诊断，不会断开连接；后续日志会继续出现。',
      primaryButton: { value: R.s('cancel'), action: () => {} },
      secondaryButton: { value: '清空', fontColor: Theme.FRP_DANGER, action: () => {
        let cleared = VpnStatus.clearLog(uuid);
        if (!cleared) {
          promptAction.showToast({ message: '清空失败，请稍后重试' });
          return;
        }
        this.refreshLogs();
        promptAction.showToast({ message: R.s('log_cleared') });
      } }
    });
  }

  private handleAction(uuid: string, action: string): void {
    if (action === 'copyLog') {
      this.copyLog(uuid);
      return;
    }
    if (action === 'clearLog') {
      this.askClearLog(uuid);
      return;
    }
    let p = ProfileManager.get(uuid);
    if (p === undefined) {
      this.reload();
      return;
    }
    if (action === 'start') {
      this.startOrStopVPN(p);
    } else if (action === 'edit') {
      this.editVPN(uuid);
    } else if (action === 'delete') {
      this.askDelete(p);
    } else if (action === 'share') {
      // Existing generated-config preview: opening it never copies or sends data.
      router.pushUrl({ url: 'pages/VPNPreferences', params: { 'uuid': uuid, 'tab': 7 } });
    } else if (action === 'save') {
      AlertDialog.show({
        title: '保存 OpenVPN 配置',
        message: '导出内容可能包含内嵌证书、私钥、静态密钥或自定义凭据。请仅保存到可信位置；外部证书文件不会自动打包，换设备可能需要重新选择。',
        primaryButton: { value: R.s('cancel'), action: () => {} },
        secondaryButton: { value: '继续保存', action: () => { this.saveConfig(p); } }
      });
    }
  }

  private async saveConfig(p: VpnProfile): Promise<void> {
    try {
      // Generate actual OpenVPN directives on a detached profile, never JSON metadata.
      let env = new GenEnvInfo();
      env.openVpn3 = true;
      env.useSystemProxy = false;
      env.guiVer = 'com.razor.tools.openvpn';
      env.platVer = 'HarmonyOS';
      let content = generateConfigFile(VpnProfile.fromJson(p.toJson()), env);
      let name = p.getName().replace(/[\\\/:*?"<>|\x00-\x1f]/g, '_').substring(0, 100) || 'OpenVPN';
      await FileUtil.saveText(`${name}.ovpn`, content, '.ovpn',
        this.getUIContext().getHostContext() as common.UIAbilityContext);
      promptAction.showToast({ message: 'OpenVPN 配置已保存' });
    } catch (error) {
      if ((error as Error).message !== 'cancelled') {
        promptAction.showToast({ message: '配置保存失败，请检查配置及保存位置' });
      }
    }
  }

  private deletionBlocked(p: VpnProfile): boolean {
    VpnStatus.restoreFromSnapshot();
    let challenge = VpnController.readPendingAuthChallenge();
    return this.requestUuid === p.getUUID() ||
      (VpnStatus.isVPNActive() && VpnStatus.getLastConnectedVPNProfile() === p.getUUID()) ||
      (challenge !== undefined && challenge.uuid === p.getUUID() && challenge.expiresAt > Date.now());
  }

  private askDelete(p: VpnProfile): void {
    if (this.deletionBlocked(p)) {
      promptAction.showToast({ message: '配置连接或认证中，请停止后再删除' });
      return;
    }
    AlertDialog.show({
      title: R.s('remove_vpn_confirm_title'),
      message: R.s('remove_vpn_query', p.getName()),
      primaryButton: { value: R.s('cancel'), action: () => {} },
      secondaryButton: { value: '删除', fontColor: Theme.FRP_DANGER, action: () => {
        if (this.deletionBlocked(p)) {
          promptAction.showToast({ message: '配置连接或认证中，请停止后再删除' });
          return;
        }
        let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        let alwaysOn = ProfileManager.getAlwaysOnVPN();
        if (alwaysOn !== undefined && alwaysOn.getUUID() === p.getUUID()) {
          ProfileManager.setAlwaysOnVPN(undefined);
        }
        ProfileShortcut.remove(context, p).catch(() => {});
        ProfileManager.removeProfile(context, p);
        this.reload();
      } }
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        Text('OpenVPN 配置').fontSize(22).fontWeight(FontWeight.Medium)
          .fontColor(Theme.TEXT_PRIMARY).width('100%')
          .padding({ left: 16, right: 12, top: 12, bottom: 4 })
        if (this.notifPermissionMissing) {
          this.NotificationPermissionCard()
        }

        if (this.profiles.length === 0) {
          this.EmptyState()
        } else {
          this.StatusSummary()

          List() {
            ForEach(this.profiles, (p: ProfileCardView, index?: number) => {
              ListItem() {
                OpenVpnCard({ view: p, sequence: (index ?? 0) + 1,
                  onAction: (uuid: string, action: string) => this.handleAction(uuid, action) })
              }
            }, (p: ProfileCardView) => p.uuid)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 16, right: 16, bottom: 12 })
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
