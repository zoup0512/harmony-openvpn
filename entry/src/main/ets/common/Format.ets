/**
 * Formatting helpers ported from the Android app (Utils.kt).
 */

export class Format {
  static humanReadableByteCount(bytes: number, speed: boolean): string {
    let unit = speed ? 1000 : 1024;
    if (bytes < unit) {
      return `${bytes} B`;
    }
    let exp = Math.floor(Math.log(bytes) / Math.log(unit));
    let pre = 'KMGTPEZY'.charAt(exp - 1) + (speed ? '/s' : '');
    let value = bytes / Math.pow(unit, exp);
    let dec = value.toFixed(1);
    return `${dec} ${pre}B`;
  }

  static formatTime(millis: number, format: number): string {
    let d = new Date(millis);
    let two = (n: number): string => {
      return n < 10 ? `0${n}` : `${n}`;
    };
    if (format === 0) {
      return '';
    } else if (format === 1) {
      return `${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())} `;
    } else {
      return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())} ${two(d.getHours())}:${two(d.getMinutes())}:${two(d.getSeconds())} `;
    }
  }
}
