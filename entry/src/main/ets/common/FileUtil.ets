/**
 * File picking / reading helpers built on the system DocumentViewPicker
 * (the equivalent of the Android Storage Access Framework path used by
 * ics-openvpn).
 */

import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';

export class PickedFile {
  name: string = '';
  content: string = '';
}

export class FileUtil {
  /** Replacement for the not-available fs.writeTextSync. */
  static writeText(path: string, text: string): void {
    let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  }

  /** Writes through a same-directory temporary file before replacing the target. */
  static writeTextAtomic(path: string, text: string): void {
    let temporaryPath = `${path}.tmp-${Date.now()}`;
    let backupPath = `${path}.bak-${Date.now()}`;
    FileUtil.writeText(temporaryPath, text);
    let hadOriginal = false;
    try {
      hadOriginal = fs.accessSync(path);
      if (hadOriginal) {
        fs.renameSync(path, backupPath);
      }
      fs.renameSync(temporaryPath, path);
    } catch (replaceError) {
      try {
        if (hadOriginal && fs.accessSync(backupPath) && !fs.accessSync(path)) {
          fs.renameSync(backupPath, path);
        }
      } catch (rollbackError) {
      }
      try {
        if (fs.accessSync(temporaryPath)) {
          fs.unlinkSync(temporaryPath);
        }
      } catch (cleanupError) {
      }
      throw new Error(`Atomic file replacement failed: ${String(replaceError)}`);
    }
    try {
      if (hadOriginal && fs.accessSync(backupPath)) {
        fs.unlinkSync(backupPath);
      }
    } catch (cleanupBackupError) {
      // The new target is already committed; an orphan backup is harmless and
      // can be cleaned up on the next write.
    }
  }

  /** Opens a single-file picker restricted to the given suffixes (e.g. ['.ovpn']). */
  static pickAndRead(suffixes: string[]): Promise<PickedFile> {
    return new Promise<PickedFile>((resolve, reject) => {
      let docPicker = new picker.DocumentViewPicker();
      let options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = suffixes;
      docPicker.select(options).then((uris: Array<string>) => {
        if (uris === undefined || uris === null || uris.length === 0) {
          reject(new Error('cancelled'));
          return;
        }
        try {
          let file = FileUtil.readUri(uris[0]);
          resolve(file);
        } catch (e) {
          reject(e as Error);
        }
      }).catch((err: Error) => {
        reject(err);
      });
    });
  }

  /** Opens the system document saver and writes UTF-8 text to the selected URI. */
  static saveText(fileName: string, text: string, suffix: string = '.txt',
    context?: common.UIAbilityContext): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      let docPicker = context === undefined ? new picker.DocumentViewPicker() :
        new picker.DocumentViewPicker(context);
      let options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      options.fileSuffixChoices = [suffix];
      docPicker.save(options).then((uris: Array<string>) => {
        if (uris === undefined || uris === null || uris.length === 0) {
          reject(new Error('cancelled'));
          return;
        }
        try {
          FileUtil.writeText(uris[0], text);
          resolve();
        } catch (e) {
          reject(e as Error);
        }
      }).catch((error: Error) => {
        reject(error);
      });
    });
  }

  static readUri(uri: string): PickedFile {
    let file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      let stat = fs.statSync(file.fd);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      let text = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
      let picked = new PickedFile();
      picked.content = text;
      // uri like file://docs/storage/Users/currentUser/Documents/xx.ovpn
      let idx = uri.lastIndexOf('/');
      picked.name = idx !== -1 ? uri.substring(idx + 1) : uri;
      return picked;
    } finally {
      fs.closeSync(file);
    }
  }
}
