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
import { LogLevel, ConnectionStatus } from '../core/LogItem';
import { generateConfigFile, GenEnvInfo } from '../core/ConfigGenerator';
import { Connection } from '../core/Connection';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';
import { OvpnEngine } from './OvpnEngine';
import socket from '@ohos.net.socket';
import notificationManager from '@ohos.notificationManager';
import notification from '@ohos.notification';
import deviceInfo from '@ohos.deviceInfo';

const NOTIFICATION_ID = 1;

export default class VpnServiceAbility extends VpnExtensionAbility {
  private running: boolean = false;
  private engine?: OvpnEngine;

  onCreate(want: Want): void {
    super.onCreate(want);
    App.init(this.context);
    VpnStatus.setPersistenceContext(this.context, true);
    VpnStatus.logMessage(LogLevel.INFO, 'VpnServiceAbility onCreate received.');
    this.startFromWant(want, 'onCreate');
  }

  // HarmonyOS system VPN authorization may deliver the actual start request
  // through onRequest after onCreate. Keep this entry point idempotent because
  // the system can send it more than once for one authorization flow.
  onRequest(want: Want, startId: number): void {
    App.init(this.context);
    VpnStatus.setPersistenceContext(this.context, true);
    VpnStatus.logMessage(LogLevel.INFO, `VpnServiceAbility onRequest received, startId=${startId}.`);
    this.startFromWant(want, 'onRequest');
  }

  private startFromWant(want: Want, source: string): void {
    let params = want.parameters as Record<string, Object>;
    let uuid: string | undefined = undefined;
    if (params !== undefined && params !== null) {
      let v = params['de.blinkt.openvpn.profileUUID'];
      if (typeof v === 'string') {
        uuid = v;
      }
    }
    let reason = source;
    let response = '';
    let dynamicChallengeCookie = '';
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
    }
    if (uuid === undefined || uuid === null || uuid === '') {
      // The system VPN authorization dialog may start this ability with a
      // system-generated want, dropping custom parameters. Fall back to the
      // request persisted by VpnController.startVpn().
      let pending = VpnController.readPendingStart();
      if (pending !== undefined) {
        uuid = pending.uuid;
        if (pending.reason !== '') {
          reason = pending.reason;
        }
        response = pending.response;
        dynamicChallengeCookie = pending.dynamicChallengeCookie;
        VpnStatus.logMessage(LogLevel.INFO,
          `No profile uuid in want, using pending start request for ${uuid}.`);
      }
    }
    if (uuid !== undefined && uuid !== null && uuid !== '') {
      VpnController.clearPendingStartRequest();
    }
    if (uuid === undefined || uuid === null || uuid === '') {
      VpnStatus.logMessage(LogLevel.ERROR, `VPN start request from ${source} has no profile uuid.`);
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
    if (this.running && reason === 'otp') {
      let oldEngine = this.engine;
      this.running = false;
      if (oldEngine !== undefined) {
        oldEngine.stop().then(() => {
          this.engine = undefined;
          this.connect(uuid as string, reason, response, dynamicChallengeCookie);
        }).catch(() => {
          this.engine = undefined;
          this.connect(uuid as string, reason, response, dynamicChallengeCookie);
        });
      } else {
        this.connect(uuid, reason, response, dynamicChallengeCookie);
      }
      return;
    }
    if (this.running) {
      VpnStatus.logMessage(LogLevel.DEBUG, `Ignoring duplicate VPN start from ${source}.`);
      return;
    }
    this.connect(uuid, reason, response, dynamicChallengeCookie);
  }

  onDestroy(): void {
    super.onDestroy();
    this.running = false;
    if (this.engine !== undefined) {
      this.engine.stop().catch(() => {
      });
      this.engine = undefined;
    }
    VpnStatus.updateStateString('NOPROCESS', this.stateMsg('NOPROCESS'),
      ConnectionStatus.LEVEL_NOTCONNECTED);
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
      case 'EXITING':
      case 'NOPROCESS':
        return s('state_disconnected', 'Disconnected');
      default:
        return state;
    }
  }

  private async connect(uuid: string, reason: string, response: string = '',
    dynamicChallengeCookie: string = ''): Promise<void> {
    this.running = true;
    VpnStatus.setConnectedVPNProfile(uuid);
    VpnStatus.logMessage(LogLevel.INFO, `Starting VPN, reason: ${reason}`);

    let profile = ProfileManager.get(uuid);
    if (profile === undefined || profile === null) {
      VpnStatus.logMessage(LogLevel.ERROR, 'Profile not found, stopping VPN service.');
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
      this.terminate();
      return;
    }

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
      this.terminate();
      return;
    }

    let missingPw = profile.needUserPWInputStr();
    if (missingPw !== '') {
      VpnStatus.updateStateString('USER_INPUT', 'Waiting for user input (missing credentials in profile settings)',
        ConnectionStatus.LEVEL_WAITING_FOR_USER_INPUT);
      VpnStatus.logMessage(LogLevel.WARNING,
        'Missing credentials: open the profile settings and enter the required username/password.');
      this.terminate();
      return;
    }

    // 3. generate config
    VpnStatus.updateStateString('VPN_GENERATE_CONFIG', this.stateMsg('VPN_GENERATE_CONFIG'));
    this.publishNotification('OpenVPN', this.stateMsg('VPN_GENERATE_CONFIG'));

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
    this.engine = new OvpnEngine(this.context as vpnExtension.VpnExtensionContext);
    try {
      await this.engine.start({
        content: configText,
        username: profile.mUsername === undefined ? '' : profile.mUsername,
        password: profile.mPassword === undefined ? '' : profile.mPassword,
        response: response,
        dynamicChallengeCookie: dynamicChallengeCookie,
        ssoMethods: 'webauth,crtext',
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
