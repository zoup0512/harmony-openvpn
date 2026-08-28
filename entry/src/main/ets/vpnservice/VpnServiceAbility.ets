/**
 * VpnServiceAbility — the VPN extension ability (equivalent of
 * de.blinkt.openvpn.core.OpenVPNService on Android).
 *
 * The complete profile lifecycle (check, config generation, logging, state
 * machine, notification) is ported from the Android app. The actual OpenVPN
 * tunnel is established by a native OpenVPN engine; this build does not bundle
 * the native library, so connection attempts perform a real TCP reachability
 * probe, report it in the log, and then stop with an explicit error stating
 * that the native engine is missing. All UI/state behaviour matches the
 * Android client so the engine can be plugged in without UI changes.
 */

import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import type Want from '@ohos.app.ability.Want';
import vpnExtension from '@ohos.net.vpnExtension';
import { App } from '../common/App';
import { ProfileManager } from '../core/ProfileManager';
import { VpnProfile, ProfileError } from '../core/VpnProfile';
import { VpnStatus } from '../core/VpnStatus';
import { LogItem, LogLevel, ConnectionStatus } from '../core/LogItem';
import { generateConfigFile, GenEnvInfo } from '../core/ConfigGenerator';
import { Connection } from '../core/Connection';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';
import { OvpnEngine } from './OvpnEngine';
import socket from '@ohos.net.socket';
import notificationManager from '@ohos.notificationManager';
import notification from '@ohos.notification';
import deviceInfo from '@ohos.deviceInfo';

const NOTIFICATION_ID = 1;

class SessionCredentials {
  username: string = '';
  password: string = '';
}

export default class VpnServiceAbility extends VpnExtensionAbility {
  private running: boolean = false;
  private engine?: OvpnEngine;
  private authWaitTimer: number = -1;
  private sessionCredentialProfileUuid: string = '';
  private sessionUsername: string = '';
  private sessionPassword: string = '';
  private sessionCredentialsExpiresAt: number = 0;
  private statusListener?: (level: ConnectionStatus, cleanMessage: string, logItem: LogItem) => void;
  private statusListenerInstalled: boolean = false;

  onCreate(want: Want): void {
    super.onCreate(want);
    App.init(this.context);
    VpnStatus.setPersistenceContext(this.context, true);
    VpnStatus.logMessage(LogLevel.INFO, 'VpnServiceAbility onCreate received.');
    VpnStatus.logMessage(LogLevel.DEBUG, `onCreate want: ${this.describeWant(want)}`);
    this.installStatusListener();
    this.startFromWant(want, 'onCreate');
  }

  // HarmonyOS system VPN authorization may deliver the actual start request
  // through onRequest after onCreate. Keep this entry point idempotent because
  // the system can send it more than once for one authorization flow.
  onRequest(want: Want, startId: number): void {
    App.init(this.context);
    VpnStatus.setPersistenceContext(this.context, true);
    VpnStatus.logMessage(LogLevel.INFO, `VpnServiceAbility onRequest received, startId=${startId}.`);
    VpnStatus.logMessage(LogLevel.DEBUG, `onRequest want (startId=${startId}): ${this.describeWant(want)}`);
    this.installStatusListener();
    this.startFromWant(want, 'onRequest');
  }

  /**
   * Redacted want summary for the log window: structural fields plus every
   * parameter key with its type. Only the profile uuid / reason values are
   * printed; credentials stay type-only.
   */
  private describeWant(want: Want): string {
    let parts: string[] = [];
    try {
      if (want.action !== undefined) {
        parts.push(`action=${want.action}`);
      }
      if (want.bundleName !== undefined) {
        parts.push(`bundle=${want.bundleName}`);
      }
      if (want.abilityName !== undefined) {
        parts.push(`ability=${want.abilityName}`);
      }
      if (want.type !== undefined) {
        parts.push(`type=${want.type}`);
      }
      let params = want.parameters as Record<string, Object> | undefined;
      if (params === undefined || params === null) {
        parts.push('params=none');
      } else {
        let described: string[] = [];
        let keys = Object.keys(params);
        for (let key of keys) {
          let v: Object | undefined = params[key];
          if (key === 'de.blinkt.openvpn.profileUUID' || key === 'startReason' || key === 'authKind') {
            described.push(`${key}=${v === undefined || v === null ? 'null' : `${v}`}`);
          } else {
            described.push(`${key}:${v === undefined || v === null ? 'null' : typeof v}`);
          }
        }
        parts.push(`params{${described.join(', ')}}`);
      }
    } catch (e) {
      parts.push('describe-failed');
    }
    return parts.join(' ');
  }

  private startFromWant(want: Want, source: string): void {
    let params = want.parameters as Record<string, Object>;
    let uuid: string | undefined = undefined;
    if (params !== undefined && params !== null) {
      let v = params['de.blinkt.openvpn.profileUUID'];
      if (typeof v === 'string') {
        uuid = v;
      } else if (v !== undefined && v !== null) {
        VpnStatus.logMessage(LogLevel.WARNING,
          `startFromWant: profileUUID parameter has unexpected type ${typeof v}, ignoring it.`);
      }
    }
    let uuidFromWant = uuid !== undefined;
    let reason = source;
    let response = '';
    let dynamicChallengeCookie = '';
    let username = '';
    let password = '';
    if (params !== undefined && params !== null) {
      let r = params['startReason'];
      if (typeof r === 'string') {
        reason = r;
      }
      let ar = params['authResponse'];
      if (typeof ar === 'string') {
        response = ar;
      }
      let dc = params['dynamicChallengeCookie'];
      if (typeof dc === 'string') {
        dynamicChallengeCookie = dc;
      }
      let u = params['username'];
      if (typeof u === 'string') {
        username = u;
      }
      let p = params['password'];
      if (typeof p === 'string') {
        password = p;
      }
    }
    let pending = VpnController.readPendingStart();
    if (pending !== undefined) {
      if (uuid === undefined || uuid === null || uuid === '') {
        uuid = pending.uuid;
      }
      if (reason === source && pending.reason !== '') {
        reason = pending.reason;
      }
      if (response === '') {
        response = pending.response;
      }
      if (dynamicChallengeCookie === '') {
        dynamicChallengeCookie = pending.dynamicChallengeCookie;
      }
      if (username === '') {
        username = pending.username;
      }
      if (password === '') {
        password = pending.password;
      }
      VpnStatus.logMessage(LogLevel.INFO, `Merged pending VPN start request for ${uuid}.`);
    }
    if (uuid !== undefined && uuid !== null && uuid !== '') {
      VpnStatus.logMessage(LogLevel.DEBUG,
        `VPN start uuid source: ${uuidFromWant ? 'want-parameter' : 'pending-file'} (${uuid}), reason=${reason}.`);
      VpnController.clearPendingStartRequest();
    }
    if (uuid === undefined || uuid === null || uuid === '') {
      if (this.running) {
        // The system re-delivers the start want for one authorization flow;
        // with the tunnel already up and the pending file consumed this
        // duplicate carries no uuid and is harmless.
        VpnStatus.logMessage(LogLevel.INFO,
          `VPN start from ${source} carries no profile uuid; tunnel already running, ignoring.`);
        return;
      }
      VpnStatus.logMessage(LogLevel.ERROR,
        `VPN start request from ${source} has no profile uuid ` +
        `(want carried none, pending start file: ${VpnController.pendingStartDebugInfo()}).`);
      return;
    }
    if (this.running && reason === 'otp-cr-text' && this.engine !== undefined) {
      try {
        this.engine.respondCrText(response);
        return;
      } catch (e) {
        VpnStatus.logMessage(LogLevel.ERROR, 'Unable to submit CR_TEXT response');
        return;
      }
    }
    if (this.running && (reason === 'otp' || reason === 'credentials')) {
      let oldEngine = this.engine;
      this.running = false;
      if (oldEngine !== undefined) {
        oldEngine.stop().then(() => {
          if (this.engine === oldEngine) {
            this.engine = undefined;
          }
          this.connect(uuid as string, reason, response, dynamicChallengeCookie, username, password);
        }).catch(() => {
          if (this.engine === oldEngine) {
            this.engine = undefined;
          }
          this.connect(uuid as string, reason, response, dynamicChallengeCookie, username, password);
        });
      } else {
        this.connect(uuid, reason, response, dynamicChallengeCookie, username, password);
      }
      return;
    }
    if (this.running) {
      VpnStatus.logMessage(LogLevel.DEBUG, `Ignoring duplicate VPN start from ${source}.`);
      return;
    }
    this.connect(uuid, reason, response, dynamicChallengeCookie, username, password);
  }

  private rememberSessionCredentials(uuid: string, username: string, password: string): void {
    if (username === '' && password === '') {
      return;
    }
    if (this.sessionCredentialProfileUuid !== '' && this.sessionCredentialProfileUuid !== uuid) {
      this.clearSessionCredentials();
    }
    this.sessionCredentialProfileUuid = uuid;
    if (username !== '') {
      this.sessionUsername = username;
    }
    if (password !== '') {
      this.sessionPassword = password;
    }
    this.sessionCredentialsExpiresAt = Date.now() + 120000;
  }

  private sessionCredentialsFor(uuid: string): SessionCredentials | undefined {
    if (this.sessionCredentialProfileUuid !== uuid || this.sessionCredentialsExpiresAt <= Date.now()) {
      if (this.sessionCredentialProfileUuid === uuid) {
        this.clearSessionCredentials();
      }
      return undefined;
    }
    let credentials = new SessionCredentials();
    credentials.username = this.sessionUsername;
    credentials.password = this.sessionPassword;
    return credentials;
  }

  private clearSessionCredentials(): void {
    this.sessionCredentialProfileUuid = '';
    this.sessionUsername = '';
    this.sessionPassword = '';
    this.sessionCredentialsExpiresAt = 0;
  }

  private scheduleAuthWaitTimeout(expiresAt: number): void {
    this.clearAuthWaitTimeout();
    let delay = Math.max(1, expiresAt - Date.now());
    this.authWaitTimer = setTimeout(() => {
      this.authWaitTimer = -1;
      VpnController.clearPendingAuthChallenge();
      this.clearSessionCredentials();
      VpnStatus.updateStateString('NOPROCESS', this.stateMsg('NOPROCESS'),
        ConnectionStatus.LEVEL_NOTCONNECTED);
      this.terminate();
    }, delay) as number;
  }

  private clearAuthWaitTimeout(): void {
    if (this.authWaitTimer !== -1) {
      clearTimeout(this.authWaitTimer);
      this.authWaitTimer = -1;
    }
  }

  private installStatusListener(): void {
    if (this.statusListenerInstalled) {
      return;
    }
    this.statusListenerInstalled = true;
    this.statusListener = (level: ConnectionStatus, cleanMessage: string, _logItem: LogItem): void => {
      if (level === ConnectionStatus.LEVEL_CONNECTED) {
        this.clearSessionCredentials();
        this.publishNotification('OpenVPN', this.stateMsg('CONNECTED'));
      } else if (level === ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT) {
        this.publishNotification('OpenVPN', this.stateMsg('USER_INPUT'));
      } else if (level === ConnectionStatus.LEVEL_AUTH_FAILED) {
        this.clearSessionCredentials();
        this.publishNotification('OpenVPN', this.stateMsg('AUTH_FAILED'));
      } else if (level === ConnectionStatus.LEVEL_NOTCONNECTED) {
        this.cancelNotification();
      } else if (cleanMessage !== '') {
        this.publishNotification('OpenVPN', cleanMessage);
      }
    };
    VpnStatus.addStateListener(this.statusListener);
  }

  onDestroy(): void {
    super.onDestroy();
    this.clearAuthWaitTimeout();
    this.running = false;
    this.clearSessionCredentials();
    if (this.engine !== undefined) {
      this.engine.stop().catch(() => {
      });
      this.engine = undefined;
    }
    if (this.statusListener !== undefined) {
      VpnStatus.removeStateListener(this.statusListener);
      this.statusListener = undefined;
      this.statusListenerInstalled = false;
    }
    if (VpnStatus.lastState !== 'AUTH_FAILED' && VpnStatus.lastState !== 'SESSION_EXPIRED') {
      VpnStatus.updateStateString('NOPROCESS', this.stateMsg('NOPROCESS'),
        ConnectionStatus.LEVEL_NOTCONNECTED);
    }
    VpnStatus.persistNow();
    this.cancelNotification();
  }

  private stateMsg(state: string): string {
    let rm = this.context.resourceManager;
    let s = (key: string, fallback: string): string => {
      try {
        return rm.getStringByNameSync(key);
      } catch (e) {
        return fallback;
      }
    };
    switch (state) {
      case 'VPN_GENERATE_CONFIG':
        return s('state_building_config', 'Building configuration…');
      case 'CONNECTING':
        return s('state_connecting', 'Connecting…');
      case 'RESOLVE':
        return s('state_resolving', 'Resolving host names…');
      case 'TCP_CONNECT':
        return s('state_connecting_tcp', 'Connecting (TCP)…');
      case 'CONNECTED':
        return s('state_connected', 'Connected');
      case 'USER_INPUT':
        return s('state_waiting_for_user_input', 'Waiting for authentication input…');
      case 'AUTH_PENDING':
        return s('state_waiting_for_authentication', 'Waiting for authentication…');
      case 'AUTH_FAILED':
        return s('state_auth_failed', 'Authentication failed');
      case 'EXITING':
      case 'NOPROCESS':
        return s('state_disconnected', 'Disconnected');
      default:
        return state;
    }
  }

  private async connect(uuid: string, reason: string, response: string = '',
    dynamicChallengeCookie: string = '', username: string = '', password: string = ''): Promise<void> {
    this.clearAuthWaitTimeout();
    this.running = true;
    VpnStatus.setConnectedVPNProfile(uuid);
    VpnStatus.logMessage(LogLevel.INFO, `Starting VPN, reason: ${reason}`);

    if (username !== '' || password !== '') {
      this.rememberSessionCredentials(uuid, username, password);
    }
    let sessionCredentials = this.sessionCredentialsFor(uuid);
    if (sessionCredentials !== undefined) {
      if (username === '') {
        username = sessionCredentials.username;
      }
      if (password === '') {
        password = sessionCredentials.password;
      }
    }

    let profile = ProfileManager.get(uuid);
    if (profile === undefined || profile === null) {
      VpnStatus.logMessage(LogLevel.ERROR, 'Profile not found, stopping VPN service.');
      this.clearSessionCredentials();
      this.terminate();
      return;
    }
    ProfileManager.updateLRU(profile);
    ProfileManager.setLastConnectedProfile(uuid);

    // 1. check profile
    let checkResult = profile.checkProfile(false);
    if (checkResult !== ProfileError.NO_ERROR) {
      VpnStatus.logMessage(LogLevel.ERROR, `Profile check failed: ${checkResult}`);
      VpnStatus.updateStateString('NOPROCESS', 'Profile check failed', undefined);
      this.clearSessionCredentials();
      this.terminate();
      return;
    }

    let effectiveUsername = username !== '' ? username : (profile.mUsername === undefined ? '' : profile.mUsername);
    let effectivePassword = password !== '' ? password : (profile.mPassword === undefined ? '' : profile.mPassword);

    // 2. missing credentials?
    if (profile.mStaticChallenge !== '' && response === '' && dynamicChallengeCookie === '') {
      let pending = new PendingAuthChallenge();
      pending.uuid = uuid;
      pending.kind = 'static';
      pending.challenge = profile.mStaticChallenge;
      pending.echo = profile.mStaticChallengeEcho;
      pending.responseRequired = true;
      pending.expiresAt = Date.now() + 120000;
      VpnController.writePendingAuthChallenge(pending);
      VpnStatus.updateStateString('USER_INPUT', 'Waiting for one-time password',
        ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT);
      this.publishNotification('OpenVPN', this.stateMsg('USER_INPUT'));
      this.scheduleAuthWaitTimeout(pending.expiresAt);
      return;
    }

    let missingPw = profile.needUserPWInputStr();
    if (missingPw === 'password' && profile.isUserPWAuth() &&
      (effectiveUsername === '' || effectivePassword === '')) {
      let pending = new PendingAuthChallenge();
      pending.uuid = uuid;
      pending.kind = 'credentials';
      pending.challenge = '';
      pending.echo = false;
      pending.responseRequired = true;
      pending.username = effectiveUsername;
      pending.expiresAt = Date.now() + 120000;
      VpnController.writePendingAuthChallenge(pending);
      VpnStatus.updateStateString('USER_INPUT', 'Waiting for username and password',
        ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT);
      this.publishNotification('OpenVPN', this.stateMsg('USER_INPUT'));
      this.scheduleAuthWaitTimeout(pending.expiresAt);
      return;
    }
    if (missingPw !== '' && !(missingPw === 'password' && profile.isUserPWAuth())) {
      VpnStatus.updateStateString('NOPROCESS', 'Missing credentials in profile settings',
        ConnectionStatus.LEVEL_NOTCONNECTED);
      VpnStatus.logMessage(LogLevel.WARNING,
        'Missing certificate or key credentials in profile settings.');
      this.terminate();
      return;
    }

    // 3. generate config
    VpnStatus.updateStateString('VPN_GENERATE_CONFIG', this.stateMsg('VPN_GENERATE_CONFIG'));
    this.publishNotification('OpenVPN', this.stateMsg('VPN_GENERATE_CONFIG'));
    let timeoutSeconds = 120;
    for (let connection of profile.mConnections) {
      if (connection.mEnabled) {
        timeoutSeconds = connection.getTimeout();
        break;
      }
    }

    let env = new GenEnvInfo();
    env.mgmtSocketDir = this.context.cacheDir;
    env.guiVer = 'com.razor.tools.openvpn 1.0.0';
    env.platVer = `${deviceInfo.sdkApiVersion} HarmonyOS ${deviceInfo.osReleaseType}`;
    env.hwaddr = '';
    env.useSystemProxy = true;
    env.openVpn3 = true;
    let configText = generateConfigFile(profile, env);
    VpnStatus.logMessage(LogLevel.DEBUG, 'Generated OpenVPN configuration:');
    let cfgLines = configText.split('\n');
    for (let line of cfgLines) {
      if (line !== '') {
        VpnStatus.logMessage(LogLevel.DEBUG, `  ${line}`);
      }
    }

    // 4. Run the OpenVPN3 core. It requests the HarmonyOS TUN fd through
    // OvpnEngine.establishTun() and then performs the real TLS/data-channel
    // handshake on its worker thread.
    VpnStatus.updateStateString('CONNECTING', this.stateMsg('CONNECTING'));
    let currentEngine = new OvpnEngine(this.context as vpnExtension.VpnExtensionContext, () => {
      if (this.engine !== currentEngine) {
        return;
      }
      let retrying = !this.running;
      this.running = false;
      if (!retrying) {
        this.clearSessionCredentials();
      }
      this.engine = undefined;
      this.cancelNotification();
    });
    this.engine = currentEngine;
    try {
      await this.engine.start({
        content: configText,
        username: effectiveUsername,
        password: effectivePassword,
        response: response,
        dynamicChallengeCookie: dynamicChallengeCookie,
        ssoMethods: 'webauth,crtext',
        connTimeout: timeoutSeconds,
        info: true
      });
      if (this.running) {
        VpnStatus.logMessage(LogLevel.INFO, 'OpenVPN3 engine started. Waiting for connection events.');
        this.publishNotification('OpenVPN', this.stateMsg('CONNECTING'));
      }
    } catch (e) {
      let message = e instanceof Error ? e.message : `${e}`;
      VpnStatus.logMessage(LogLevel.ERROR, `OpenVPN3 engine failed to start: ${message}`);
      VpnStatus.updateStateString('EXITING', message, undefined);
      this.terminate();
    }
  }

  private firstEnabledConnection(profile: VpnProfile): Connection | undefined {
    for (let c of profile.mConnections) {
      if (c.mEnabled) {
        return c;
      }
    }
    return undefined;
  }

  private async probeTcp(host: string, port: number, timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      try {
        let tcp = socket.constructTCPSocketInstance();
        tcp.on('error', () => {
          resolve(false);
        });
        tcp.connect({
          address: { address: host, port: port, family: 1 },
          timeout: Math.min(timeoutMs, 30000)
        }).then(() => {
          tcp.close();
          resolve(true);
        }).catch(() => {
          resolve(false);
        });
      } catch (e) {
        resolve(false);
      }
    });
  }

  /** Establishes the TUN device via the system VPN API (used by the native engine). */
  private async startTun(profile: VpnProfile): Promise<void> {
    let conn = vpnExtension.createVpnConnection(this.context as vpnExtension.VpnExtensionContext);
    let addresses: Array<vpnExtension.LinkAddress> = [];
    if (!VpnProfile.isEmpty(profile.mIPv4Address)) {
      let parts = (profile.mIPv4Address as string).split('/');
      let prefix = parts.length > 1 ? parseInt(parts[1]) : 24;
      let la: vpnExtension.LinkAddress = {
        address: { address: parts[0] },
        prefixLength: isNaN(prefix) ? 24 : prefix
      };
      addresses.push(la);
    }
    let config: vpnExtension.VpnConfig = {
      addresses: addresses,
      dnsAddresses: [],
      mtu: 1400,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isBlocking: true
    };
    if (profile.mAllowedAppsVpnAreDisallowed && profile.mAllowedAppsVpn.size > 0) {
      let list: string[] = [];
      profile.mAllowedAppsVpn.forEach((a: string) => {
        list.push(a);
      });
      config.blockedApplications = list;
    } else if (!profile.mAllowedAppsVpnAreDisallowed && profile.mAllowedAppsVpn.size > 0) {
      let list: string[] = [];
      profile.mAllowedAppsVpn.forEach((a: string) => {
        list.push(a);
      });
      config.trustedApplications = list;
    }
    await conn.create(config);
  }

  private publishNotification(title: string, text: string): void {
    try {
      let request: notificationManager.NotificationRequest = {
        id: NOTIFICATION_ID,
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        isOngoing: true,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text,
            additionalText: ''
          }
        }
      };
      notificationManager.publish(request).then(() => {
        VpnStatus.logMessage(LogLevel.DEBUG, `VPN notification published: ${text}`);
      }).catch((e: Error) => {
        VpnStatus.logMessage(LogLevel.ERROR, `VPN notification publish failed: ${e.message}`);
      });
    } catch (e) {
      let message = e instanceof Error ? e.message : `${e}`;
      VpnStatus.logMessage(LogLevel.ERROR, `VPN notification request failed: ${message}`);
    }
  }

  private cancelNotification(): void {
    try {
      notificationManager.cancel(NOTIFICATION_ID);
    } catch (e) {
      // ignore
    }
  }

  private terminate(): void {
    this.running = false;
    this.clearSessionCredentials();
    this.cancelNotification();
    VpnStatus.persistNow();
    let want: Want = {
      bundleName: 'com.razor.tools.openvpn',
      abilityName: 'VpnServiceAbility'
    };
    vpnExtension.stopVpnExtensionAbility(want).catch(() => {
    });
  }
}
