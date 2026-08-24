/**
 * String resource helper similar to Android's getString(R.string.x, args).
 */

import { common } from '@kit.AbilityKit';

export class R {
  private static ctx?: common.Context = undefined;

  static init(context: common.Context): void {
    R.ctx = context;
  }

  static s(key: string, ...args: string[]): string {
    let value = key;
    try {
      if (R.ctx !== undefined) {
        value = R.ctx.resourceManager.getStringByNameSync(key);
      }
    } catch (e) {
      return key;
    }
    if (args.length === 0) {
      return value;
    }
    // support %s, %1$s, %2$s, %d style placeholders
    for (let i = 0; i < args.length; i++) {
      let idx = `${i + 1}`;
      value = value.split(`%${idx}$s`).join(args[i]);
      value = value.split(`%${idx}$d`).join(args[i]);
    }
    let posArg = 0;
    value = value.replace(/%[sd]/g, (): string => {
      let v = posArg < args.length ? args[posArg] : '';
      posArg++;
      return v;
    });
    return value;
  }
}
