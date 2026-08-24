/**
 * General app preferences (equivalent of the default SharedPreferences).
 */

import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';

export class GP {
  private static p?: preferences.Preferences = undefined;
  private static storeName: string = 'general_prefs';

  static init(context: common.Context): Promise<void> {
    return preferences.getPreferences(context, GP.storeName).then((p: preferences.Preferences) => {
      GP.p = p;
    });
  }

  static ready(): boolean {
    return GP.p !== undefined;
  }

  static getBool(key: string, def: boolean): boolean {
    if (GP.p === undefined) {
      return def;
    }
    return GP.p.getSync(key, def) as boolean;
  }

  static setBool(key: string, value: boolean): void {
    if (GP.p === undefined) {
      return;
    }
    GP.p.putSync(key, value);
    GP.p.flush();
  }

  static getString(key: string, def: string): string {
    if (GP.p === undefined) {
      return def;
    }
    return GP.p.getSync(key, def) as string;
  }

  static setString(key: string, value: string): void {
    if (GP.p === undefined) {
      return;
    }
    GP.p.putSync(key, value);
    GP.p.flush();
  }

  static getInt(key: string, def: number): number {
    if (GP.p === undefined) {
      return def;
    }
    return GP.p.getSync(key, def) as number;
  }

  static setInt(key: string, value: number): void {
    if (GP.p === undefined) {
      return;
    }
    GP.p.putSync(key, value);
    GP.p.flush();
  }
}
