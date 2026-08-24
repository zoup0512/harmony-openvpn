/**
 * Port of de.blinkt.openvpn.core.PasswordCache
 */

export class PasswordCache {
  static readonly PCKS12ORCERTPASSWORD: number = 2;
  static readonly AUTHPASSWORD: number = 3;

  private static cachedPasswordType: number = 0;
  private static cachedPassword?: string = undefined;
  private static cachedPasswordProfileUUID?: string = undefined;

  static getInstance(uuid: string): void {
    if (PasswordCache.cachedPasswordProfileUUID === undefined ||
      PasswordCache.cachedPasswordProfileUUID !== uuid) {
      PasswordCache.cachedPasswordProfileUUID = uuid;
      PasswordCache.cachedPassword = undefined;
      PasswordCache.cachedPasswordType = 0;
    }
  }

  static setCachedPassword(uuidStr: string, type: number, password: string): void {
    PasswordCache.getInstance(uuidStr);
    PasswordCache.cachedPasswordType = type;
    PasswordCache.cachedPassword = password;
  }

  static getPKCS12orCertificatePassword(uuid: string, resetPw: boolean): string | undefined {
    if (uuid === undefined) {
      return undefined;
    }
    if (uuid !== PasswordCache.cachedPasswordProfileUUID) {
      PasswordCache.getInstance(uuid);
    }
    if (PasswordCache.cachedPasswordType !== PasswordCache.PCKS12ORCERTPASSWORD) {
      return undefined;
    }
    let pw = PasswordCache.cachedPassword as string;
    if (resetPw) {
      PasswordCache.cachedPassword = undefined;
    }
    return pw;
  }

  static getAuthPassword(uuid: string, resetPw: boolean): string | undefined {
    if (uuid === undefined) {
      return undefined;
    }
    if (uuid !== PasswordCache.cachedPasswordProfileUUID) {
      PasswordCache.getInstance(uuid);
    }
    if (PasswordCache.cachedPasswordType !== PasswordCache.AUTHPASSWORD) {
      return undefined;
    }
    let pw = PasswordCache.cachedPassword as string;
    if (resetPw) {
      PasswordCache.cachedPassword = undefined;
    }
    return pw;
  }
}
