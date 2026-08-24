/**
 * Port of de.blinkt.openvpn.core.CIDRIP
 * Parses and normalises IPv4 addresses with prefix length / netmask.
 */

export class CIDRIP {
  ip: string;
  len: number;

  private constructor(ip: string, len: number) {
    this.ip = ip;
    this.len = len;
  }

  /** Create from ip + netmask string (e.g. "255.255.255.0"), like Java CIDRIP(String, String) */
  static fromNetmask(ip: string, mask: string): CIDRIP {
    let len = CIDRIP.calculateLenFromMask(mask);
    return new CIDRIP(ip, len);
  }

  /** Create from ip + prefix (e.g. 24), like Java CIDRIP(String, int) */
  static fromPrefix(ip: string, prefix: number): CIDRIP {
    return new CIDRIP(ip, prefix);
  }

  static getInt(ipaddr: string): number {
    let parts = ipaddr.split('.');
    if (parts.length !== 4) {
      throw new Error('Invalid IPv4 address');
    }
    let value = 0;
    for (let i = 0; i < 4; i++) {
      let p = parseInt(parts[i]);
      if (isNaN(p) || p < 0 || p > 255) {
        throw new Error('Invalid IPv4 address');
      }
      value = (value * 256) + p;
    }
    return value >>> 0;
  }

  static calculateLenFromMask(mask: string): number {
    let netmask = CIDRIP.getInt(mask);
    let netmaskAddOne = (netmask + 1) >>> 0;
    let lenZeros = 0;
    while (lenZeros < 32) {
      if ((netmaskAddOne & 1) === 1) {
        break;
      }
      lenZeros++;
      netmaskAddOne = netmaskAddOne >>> 1;
    }
    let allOnes = 0xffffffff;
    let expect = ((allOnes >>> lenZeros) >>> 0);
    if (netmaskAddOne !== expect) {
      return 32;
    }
    return 32 - lenZeros;
  }

  /** Returns true if the host part had to be cleared. */
  normalise(): boolean {
    let ipInt = CIDRIP.getInt(this.ip);
    let mask = this.len === 0 ? 0 : (0xffffffff << (32 - this.len)) >>> 0;
    let norm = (ipInt & mask) >>> 0;
    let normStr = CIDRIP.intToString(norm);
    if (normStr !== this.ip) {
      this.ip = normStr;
      return true;
    }
    return false;
  }

  static intToString(v: number): string {
    let a = (v >>> 24) & 0xff;
    let b = (v >>> 16) & 0xff;
    let c = (v >>> 8) & 0xff;
    let d = v & 0xff;
    return `${a}.${b}.${c}.${d}`;
  }

  toString(): string {
    return `${this.ip}/${this.len}`;
  }
}
