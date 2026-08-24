/**
 * File picking / reading helpers built on the system DocumentViewPicker
 * (the equivalent of the Android Storage Access Framework path used by
 * ics-openvpn).
 */

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
