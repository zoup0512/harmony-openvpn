/**
 * Minimal port of X509Utils — extracts a human readable summary from a PEM
 * certificate using the HarmonyOS cert framework plus a small DER scanner.
 */

import util from '@ohos.util';

export class CertSummary {
  friendlyName: string = '';
  validNotBefore: string = '';
  validNotAfter: string = '';

  isValid(): boolean {
    return this.friendlyName !== '';
  }
}

export class X509Utils {
  /** Returns a short friendly name such as "CN=Example CA" or ''. */
  static getCertificateFriendlyName(pemData: string): CertSummary {
    let summary = new CertSummary();
    if (pemData === undefined || pemData === null || pemData.indexOf('-----BEGIN') === -1) {
      return summary;
    }
    try {
      let b64 = pemData.replace(/-----[A-Z ]*-----/g, '').replace(/\s+/g, '');
      let helper = new util.Base64Helper();
      let der = helper.decodeSync(b64);
      let derArr = new Uint8Array(der);


      // Scan for CN: OID 2.5.4.3 (06 03 55 04 03) followed by a string type
      let cn = X509Utils.scanForCN(derArr);
      summary.friendlyName = cn;
      if (cn !== '') {
        summary.friendlyName = `CN=${cn}`;
      }
    } catch (e) {
      // not a certificate / not parseable
    }
    return summary;
  }

  private static scanForCN(der: Uint8Array): string {
    let best = '';
    for (let i = 0; i + 5 < der.length; i++) {
      if (der[i] === 0x06 && der[i + 1] === 0x03 && der[i + 2] === 0x55 && der[i + 3] === 0x04 &&
        der[i + 4] === 0x03) {
        let j = i + 5;
        if (j >= der.length) {
          continue;
        }
        // possible length byte(s)
        let len = der[j];
        let strStart = j + 1;
        if ((len & 0x80) !== 0) {
          let numLenBytes = len & 0x7f;
          if (numLenBytes === 0 || numLenBytes > 2 || j + numLenBytes >= der.length) {
            continue;
          }
          len = 0;
          for (let k = 0; k < numLenBytes; k++) {
            len = (len << 8) | der[j + 1 + k];
          }
          strStart = j + 1 + numLenBytes;
        }
        if (strStart >= der.length || len === 0 || strStart + len > der.length) {
          continue;
        }
        let type = der[strStart];
        if (type === 0x0c /* UTF8String */ || type === 0x13 /* PrintableString */ ||
          type === 0x16 /* IA5String */) {
          let s = '';
          for (let k = 0; k < len; k++) {
            let c = der[strStart + 1 + k];
            if (c >= 32 && c < 127) {
              s += String.fromCharCode(c);
            }
          }
          if (s.length > best.length) {
            best = s;
          }
        }
      }
    }
    return best;
  }
}
