/**
 * Port of de.blinkt.openvpn.core.ProfileManager
 * Profiles are persisted as JSON files (<uuid>.json) in the app files dir.
 */

import { VpnProfile } from './VpnProfile';
import { VpnStatus } from './VpnStatus';
import { Context } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { FileUtil } from '../common/FileUtil';
import preferences from '@ohos.data.preferences';

export class ProfileManager {
  private static profiles: Map<string, VpnProfile> = new Map<string, VpnProfile>();
  private static tmpprofile?: VpnProfile = undefined;
  private static ctx?: Context = undefined;
  private static prefs?: preferences.Preferences = undefined;
  private static loaded: boolean = false;

  static readonly PREFS_NAME: string = 'VPNList';
  static readonly TEMPORARY_PROFILE_FILENAME: string = 'temporary-vpn-profile';

  static init(ctx: Context): void {
    if (ProfileManager.ctx !== undefined) {
      return;
    }
    ProfileManager.ctx = ctx;
  }

  static ensureLoaded(): void {
    if (ProfileManager.loaded || ProfileManager.ctx === undefined) {
      return;
    }
    ProfileManager.loaded = true;
    ProfileManager.loadVPNList();
  }

  private static async getPrefs(): Promise<preferences.Preferences> {
    if (ProfileManager.prefs !== undefined) {
      return ProfileManager.prefs;
    }
    let ctx = ProfileManager.ctx as Context;
    let p = await preferences.getPreferences(ctx, ProfileManager.PREFS_NAME);
    ProfileManager.prefs = p;
    return p;
  }

  private static loadVPNList(): void {
    let ctx = ProfileManager.ctx;
    if (ctx === undefined) {
      return;
    }
    try {
      let names = fs.listFileSync(ctx.filesDir);
      for (let name of names) {
        if (!name.endsWith('.json')) {
          continue;
        }
        let uuid = name.substring(0, name.length - '.json'.length);
        if (uuid === ProfileManager.TEMPORARY_PROFILE_FILENAME) {
          continue;
        }
        ProfileManager.loadVpnEntry(uuid);
      }
    } catch (e) {
      // ignore
    }
    // temporary profile
    try {
      let tmpPath = `${ctx.filesDir}/${ProfileManager.TEMPORARY_PROFILE_FILENAME}.json`;
      if (fs.accessSync(tmpPath)) {
        let text = fs.readTextSync(tmpPath);
        let vp = VpnProfile.fromJson(JSON.parse(text) as Record<string, Object>);
        ProfileManager.tmpprofile = vp;
      }
    } catch (e) {
      // ignore
    }
  }

  private static loadVpnEntry(uuid: string): void {
    let ctx = ProfileManager.ctx as Context;
    try {
      let path = `${ctx.filesDir}/${uuid}.json`;
      if (!fs.accessSync(path)) {
        return;
      }
      let text = fs.readTextSync(path);
      let vp = VpnProfile.fromJson(JSON.parse(text) as Record<string, Object>);
      if (vp.mName === undefined || vp.getUUID() === undefined || vp.getUUID() === '') {
        return;
      }
      ProfileManager.profiles.set(vp.getUUID(), vp);
    } catch (e) {
      // ignore broken files like the Android version does
    }
  }

  static get(uuid: string): VpnProfile | undefined {
    ProfileManager.ensureLoaded();
    let tmp = ProfileManager.tmpprofile;
    if (tmp !== undefined && tmp.getUUID() === uuid) {
      return tmp;
    }
    return ProfileManager.profiles.get(uuid) as VpnProfile;
  }

  static getProfiles(): VpnProfile[] {
    ProfileManager.ensureLoaded();
    let list: VpnProfile[] = [];
    ProfileManager.profiles.forEach((p: VpnProfile) => {
      list.push(p);
    });
    return list;
  }

  static getProfileByName(name: string): VpnProfile | undefined {
    ProfileManager.ensureLoaded();
    let found: VpnProfile | undefined = undefined;
    ProfileManager.profiles.forEach((p: VpnProfile) => {
      if (found === undefined && p.getName() === name) {
        found = p;
      }
    });
    return found;
  }

  static addProfile(profile: VpnProfile): void {
    ProfileManager.ensureLoaded();
    ProfileManager.saveProfile(profile);
    ProfileManager.profiles.set(profile.getUUID(), profile);
  }

  static saveProfile(profile: VpnProfile): void {
    let ctx = ProfileManager.ctx;
    if (ctx === undefined) {
      return;
    }
    profile.mVersion += 1;
    let path = `${ctx.filesDir}/${profile.getUUID()}.json`;
    try {
      FileUtil.writeText(path, JSON.stringify(profile.toJson()));
    } catch (e) {
      throw new Error(`Could not save profile: ${e}`);
    }
  }

  static removeProfile(context: Context, profile: VpnProfile): void {
    ProfileManager.ensureLoaded();
    ProfileManager.profiles.delete(profile.getUUID());
    try {
      let path = `${context.filesDir}/${profile.getUUID()}.json`;
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      // ignore
    }
    ProfileManager.setLastConnectedProfile(undefined);
  }

  static setTemporaryProfile(profile: VpnProfile): void {
    ProfileManager.tmpprofile = profile;
    let ctx = ProfileManager.ctx;
    if (ctx !== undefined) {
      try {
        FileUtil.writeText(`${ctx.filesDir}/${ProfileManager.TEMPORARY_PROFILE_FILENAME}.json`,
          JSON.stringify(profile.toJson()));
      } catch (e) {
        // ignore
      }
    }
  }

  static isTempProfile(p: VpnProfile): boolean {
    return ProfileManager.tmpprofile === p;
  }

  static getTemporaryProfile(): VpnProfile | undefined {
    ProfileManager.ensureLoaded();
    return ProfileManager.tmpprofile;
  }

  static updateLRU(profile: VpnProfile): void {
    profile.mLastUsed = Date.now();
    if (!ProfileManager.isTempProfile(profile)) {
      ProfileManager.saveProfile(profile);
    }
  }

  // ------------------------------------------------------------------
  // "last connected" and "default/always on" VPN (preferences backed)
  // ------------------------------------------------------------------

  static setLastConnectedProfile(uuid?: string): void {
    ProfileManager.getPrefs().then((p: preferences.Preferences) => {
      if (uuid === undefined) {
        p.deleteSync('lastConnectedProfile');
      } else {
        p.putSync('lastConnectedProfile', uuid);
      }
      p.flush();
    }).catch(() => {
    });
  }

  static getLastConnectedProfile(): string | undefined {
    ProfileManager.ensureLoaded();
    let lastConnected: string | undefined;
    try {
      lastConnected = VpnStatus.getLastConnectedVPNProfile();
    } catch (e) {
      lastConnected = undefined;
    }
    if (lastConnected !== undefined && lastConnected !== null) {
      let p = ProfileManager.get(lastConnected);
      if (p !== undefined && p !== null) {
        return lastConnected;
      }
    }
    // fall back to persisted value
    let uuid: string | undefined = undefined;
    try {
      let p = ProfileManager.prefs;
      if (p !== undefined) {
        uuid = p.getSync('lastConnectedProfile', '').toString();
      }
    } catch (e) {
      // ignore
    }
    if (uuid === '' || uuid === undefined) {
      return undefined;
    }
    return uuid;
  }

  static setAlwaysOnVPN(uuid?: string): void {
    ProfileManager.getPrefs().then((p: preferences.Preferences) => {
      if (uuid === undefined) {
        p.deleteSync('alwaysOnVpn');
      } else {
        p.putSync('alwaysOnVpn', uuid);
      }
      p.flush();
    }).catch(() => {
    });
  }

  static getAlwaysOnVPN(): VpnProfile | undefined {
    ProfileManager.ensureLoaded();
    try {
      let p = ProfileManager.prefs;
      if (p !== undefined) {
        let uuid = p.getSync('alwaysOnVpn', '').toString();
        if (uuid !== '' && uuid !== undefined) {
          return ProfileManager.get(uuid);
        }
      }
    } catch (e) {
      // ignore
    }
    return undefined;
  }

  /** Synchronous prefs access after first (async) load. */
  static warmupPrefs(): Promise<void> {
    return ProfileManager.getPrefs().then(() => {
      return;
    });
  }
}

