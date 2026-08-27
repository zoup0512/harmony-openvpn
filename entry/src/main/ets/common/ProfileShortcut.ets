import { common, Want } from '@kit.AbilityKit';
import { productViewManager } from '@kit.AppGalleryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import { VpnProfile } from '../core/VpnProfile';

export enum ProfileShortcutErrorKind {
  INVALID_PROFILE = 'invalid_profile',
  NOT_SUPPORTED = 'not_supported',
  ALREADY_EXISTS = 'already_exists',
  LIMIT_REACHED = 'limit_reached',
  VERIFICATION_FAILED = 'verification_failed',
  REQUEST_EXPIRED = 'request_expired',
  USER_REFUSED = 'user_refused',
  SERVICE_UNAVAILABLE = 'service_unavailable',
  ICON_PREPARATION_FAILED = 'icon_preparation_failed',
  INTERNAL_ERROR = 'internal_error',
  UNKNOWN = 'unknown'
}

export class ProfileShortcutError extends Error {
  readonly kind: ProfileShortcutErrorKind;
  readonly code: number;

  constructor(kind: ProfileShortcutErrorKind, code: number, message: string) {
    super(message);
    this.name = 'ProfileShortcutError';
    this.kind = kind;
    this.code = code;
  }
}

export interface ProfileShortcutResult {
  shortcutId: string;
  code: number;
}

/** Creates a stable, profile-specific pinned shortcut through HMS AppGalleryKit. */
export class ProfileShortcut {
  private static readonly BUNDLE_NAME: string = 'com.razor.tools.openvpn';
  private static readonly MODULE_NAME: string = 'entry';
  private static readonly ABILITY_NAME: string = 'EntryAbility';
  private static readonly SHORTCUT_PREFIX: string = 'vpn_';
  private static readonly ICON_RESOURCE_NAME: string = 'app_icon';
  private static readonly ICON_FILENAME: string = 'profile-shortcut-icon.png';
  private static readonly MAX_SHORTCUT_ID_BYTES: number = 63;
  private static readonly MAX_LABEL_LENGTH: number = 255;
  private static readonly MAX_ICON_BYTES: number = 100 * 1024;

  static async create(context: common.UIAbilityContext, profile: VpnProfile): Promise<ProfileShortcutResult> {
    let uuid = profile.getUUID().trim();
    if (uuid === '') {
      throw new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, 401,
        'The VPN profile has no UUID.');
    }

    let shortcutId = `${ProfileShortcut.SHORTCUT_PREFIX}${uuid}`;
    // Profile UUIDs are ASCII, so string length is also the UTF-8 byte length here.
    if (shortcutId.length > ProfileShortcut.MAX_SHORTCUT_ID_BYTES) {
      throw new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, 401,
        'The generated shortcut ID exceeds the 63-byte limit.');
    }

    let label = profile.getName().trim();
    if (label === '') {
      label = 'OpenVPN';
    } else if (label.length > ProfileShortcut.MAX_LABEL_LENGTH) {
      label = label.substring(0, ProfileShortcut.MAX_LABEL_LENGTH);
    }

    let iconPath: string;
    try {
      iconPath = await ProfileShortcut.prepareIcon(context);
    } catch (e) {
      let error = e as BusinessError;
      throw new ProfileShortcutError(ProfileShortcutErrorKind.ICON_PREPARATION_FAILED,
        ProfileShortcut.errorCode(error), `Could not prepare the shortcut icon: ${ProfileShortcut.errorMessage(error)}`);
    }

    let want: Want = {
      bundleName: ProfileShortcut.BUNDLE_NAME,
      moduleName: ProfileShortcut.MODULE_NAME,
      abilityName: ProfileShortcut.ABILITY_NAME,
      parameters: {
        'de.blinkt.openvpn.profileUUID': uuid,
        'startReason': 'shortcut'
      } as Record<string, Object>
    };

    let checkResult: productViewManager.CheckShortcutResult;
    try {
      checkResult = await productViewManager.checkPinShortcutPermitted(context, shortcutId, want, label, iconPath, '');
    } catch (e) {
      throw ProfileShortcut.fromBusinessError(e as BusinessError);
    }

    if (checkResult.code !== 0) {
      throw ProfileShortcut.fromCode(checkResult.code,
        `Shortcut verification returned code ${checkResult.code}.`);
    }
    if (checkResult.tid === undefined || checkResult.tid === '') {
      throw new ProfileShortcutError(ProfileShortcutErrorKind.VERIFICATION_FAILED, 1006620005,
        'Shortcut verification succeeded without a transaction ID.');
    }

    try {
      await productViewManager.requestNewPinShortcut(context, checkResult.tid);
    } catch (e) {
      throw ProfileShortcut.fromBusinessError(e as BusinessError);
    }

    return {
      shortcutId: shortcutId,
      code: 0
    };
  }

  /** Removes the stable shortcut for a profile. Missing shortcuts are already clean. */
  static async remove(context: common.UIAbilityContext, profileOrUuid: VpnProfile | string): Promise<void> {
    let uuid = typeof profileOrUuid === 'string' ? profileOrUuid.trim() : profileOrUuid.getUUID().trim();
    if (uuid === '') {
      throw new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, 401,
        'The VPN profile has no UUID.');
    }

    let shortcutId = `${ProfileShortcut.SHORTCUT_PREFIX}${uuid}`;
    if (shortcutId.length > ProfileShortcut.MAX_SHORTCUT_ID_BYTES) {
      throw new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, 401,
        'The generated shortcut ID exceeds the 63-byte limit.');
    }

    try {
      await productViewManager.removePinShortcut(context, shortcutId);
    } catch (e) {
      let error = e as BusinessError;
      // Missing shortcut is the desired post-delete state. The caller can also
      // best-effort catch unsupported/service errors during profile deletion.
      if (ProfileShortcut.errorCode(error) === 1006620010) {
        return;
      }
      throw ProfileShortcut.fromBusinessError(error);
    }
  }

  private static async prepareIcon(context: common.UIAbilityContext): Promise<string> {
    let content = await context.resourceManager.getMediaByName(ProfileShortcut.ICON_RESOURCE_NAME);
    if (content.byteLength === 0 || content.byteLength > ProfileShortcut.MAX_ICON_BYTES) {
      throw new Error('The app icon is empty or exceeds the 100 KB shortcut limit.');
    }

    let iconPath = `${context.filesDir}/${ProfileShortcut.ICON_FILENAME}`;
    let buffer = new ArrayBuffer(content.byteLength);
    new Uint8Array(buffer).set(content);
    let file = fs.openSync(iconPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      let written = fs.writeSync(file.fd, buffer);
      if (written !== content.byteLength) {
        throw new Error('The shortcut icon was not written completely.');
      }
    } finally {
      fs.closeSync(file);
    }
    return iconPath;
  }

  private static fromBusinessError(error: BusinessError): ProfileShortcutError {
    let code = ProfileShortcut.errorCode(error);
    let message = ProfileShortcut.errorMessage(error);
    return ProfileShortcut.fromCode(code, `Shortcut request failed: ${message}`);
  }

  private static fromCode(code: number, message: string): ProfileShortcutError {
    switch (code) {
      case 401:
        return new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, code, message);
      case 801:
        return new ProfileShortcutError(ProfileShortcutErrorKind.NOT_SUPPORTED, code, message);
      case 1006620002:
        return new ProfileShortcutError(ProfileShortcutErrorKind.SERVICE_UNAVAILABLE, code, message);
      case 1006620003:
        return new ProfileShortcutError(ProfileShortcutErrorKind.ALREADY_EXISTS, code, message);
      case 1006620004:
        return new ProfileShortcutError(ProfileShortcutErrorKind.LIMIT_REACHED, code, message);
      case 1006620005:
        return new ProfileShortcutError(ProfileShortcutErrorKind.VERIFICATION_FAILED, code, message);
      case 1006620006:
        return new ProfileShortcutError(ProfileShortcutErrorKind.REQUEST_EXPIRED, code, message);
      case 1006620007:
      case 1006620013:
        return new ProfileShortcutError(ProfileShortcutErrorKind.USER_REFUSED, code, message);
      case 1006620012:
        return new ProfileShortcutError(ProfileShortcutErrorKind.INVALID_PROFILE, code, message);
      case 1006620001:
      case 1006620011:
      case 1006620014:
        return new ProfileShortcutError(ProfileShortcutErrorKind.INTERNAL_ERROR, code, message);
      default:
        return new ProfileShortcutError(ProfileShortcutErrorKind.UNKNOWN, code, message);
    }
  }

  private static errorCode(error: BusinessError): number {
    return typeof error.code === 'number' ? error.code : 0;
  }

  private static errorMessage(error: BusinessError): string {
    return typeof error.message === 'string' && error.message !== '' ? error.message : 'Unknown error';
  }
}
