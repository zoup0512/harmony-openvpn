import { util } from '@kit.ArkTS';
import { Context } from '@kit.AbilityKit';
import { FrpType, allFrpTypes } from './FrpType';
import { FrpConfig } from './FrpConfig';
import { FrpValidator } from './FrpValidator';

export class FrpConfigTemplate {
  type: FrpType;
  rawfilePath: string;
  fileName: string;
  displayName: string;

  constructor(type: FrpType, rawfilePath: string, fileName: string, displayName: string = '') {
    this.type = type;
    this.rawfilePath = rawfilePath;
    this.fileName = fileName;
    this.displayName = displayName === '' ? fileName : displayName;
  }
}

/** An editor-friendly frpc template that can be rendered without rawfile access. */
export class FrpQuickTemplate {
  id: string;
  label: string;
  content: string;
  formCompatible: boolean;

  constructor(id: string, label: string, content: string, formCompatible: boolean) {
    this.id = id;
    this.label = label;
    this.content = content;
    this.formCompatible = formCompatible;
  }
}

/** Loads packaged rawfiles, with built-in templates as a safe fallback. */
export class FrpTemplateManager {
  static readonly RAWFILE_ROOT: string = 'frp/templates';
  static readonly ENGLISH_LOCALE: string = 'en';
  static readonly CHINESE_LOCALE: string = 'zh-cn';
  private static context?: Context = undefined;

  /** Returns common frpc editor templates; these do not depend on rawfiles. */
  static quickTemplates(): FrpQuickTemplate[] {
    let templates: FrpQuickTemplate[] = [];
    templates.push(new FrpQuickTemplate('ssh', 'SSH',
      '# SSH 远程访问\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "ssh"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 22\nremotePort = 6000\n', true));
    templates.push(new FrpQuickTemplate('rdp', 'RDP 远程桌面',
      '# RDP 远程桌面\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "rdp"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 3389\nremotePort = 63389\n', true));
    templates.push(new FrpQuickTemplate('http', 'HTTP 网站',
      '# HTTP 网站\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "web-http"\ntype = "http"\nlocalIP = "127.0.0.1"\nlocalPort = 8080\ncustomDomains = ["example.com"]\n', false));
    templates.push(new FrpQuickTemplate('https', 'HTTPS 网站',
      '# HTTPS 网站\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "web-https"\ntype = "https"\nlocalIP = "127.0.0.1"\nlocalPort = 8443\ncustomDomains = ["secure.example.com"]\n', false));
    templates.push(new FrpQuickTemplate('tcp', 'TCP 通用',
      '# TCP 通用转发\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "tcp-service"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 8080\nremotePort = 6000\n', true));
    templates.push(new FrpQuickTemplate('udp', 'UDP 通用',
      '# UDP 通用转发\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "udp-service"\ntype = "udp"\nlocalIP = "127.0.0.1"\nlocalPort = 9000\nremotePort = 6000\n', true));
    templates.push(new FrpQuickTemplate('mysql', 'MySQL',
      '# MySQL 数据库\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "mysql"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 3306\nremotePort = 13306\n', true));
    templates.push(new FrpQuickTemplate('redis', 'Redis',
      '# Redis 服务\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "redis"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 6379\nremotePort = 16379\n', true));
    templates.push(new FrpQuickTemplate('vnc', 'VNC',
      '# VNC 远程桌面\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "vnc"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 5900\nremotePort = 15900\n', true));
    templates.push(new FrpQuickTemplate('stcp-secret', 'STCP 秘钥访问',
      '# STCP 秘钥访问（被连接端）\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "secret-service"\ntype = "stcp"\nsecretKey = "change-me"\nlocalIP = "127.0.0.1"\nlocalPort = 22\n', false));
    templates.push(new FrpQuickTemplate('xtcp-p2p', 'XTCP P2P',
      '# XTCP P2P 穿透（被连接端）\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "p2p-service"\ntype = "xtcp"\nsecretKey = "change-me"\nlocalIP = "127.0.0.1"\nlocalPort = 22\n', false));
    templates.push(new FrpQuickTemplate('multi-proxy', '单配置多代理',
      '# 单配置多代理\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[[proxies]]\nname = "ssh"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 22\nremotePort = 6000\n\n[[proxies]]\nname = "web"\ntype = "http"\nlocalIP = "127.0.0.1"\nlocalPort = 8080\ncustomDomains = ["example.com"]\n', false));
    templates.push(new FrpQuickTemplate('ssh-ipv6', 'SSH over IPv6',
      '# SSH over IPv6\nserverAddr = "::1"\nserverPort = 7000\n\n[[proxies]]\nname = "ssh-ipv6"\ntype = "tcp"\nlocalIP = "::1"\nlocalPort = 22\nremotePort = 6000\n', false));
    templates.push(new FrpQuickTemplate('http-ipv6', 'HTTP over IPv6',
      '# HTTP over IPv6\nserverAddr = "::1"\nserverPort = 7000\n\n[[proxies]]\nname = "web-ipv6"\ntype = "http"\nlocalIP = "::1"\nlocalPort = 8080\ncustomDomains = ["ipv6.example.com"]\n', false));
    return templates;
  }

  static init(context: Context): void {
    FrpTemplateManager.context = context;
  }

  static list(type?: FrpType): FrpConfigTemplate[] {
    let result: FrpConfigTemplate[] = [];
    if (FrpTemplateManager.context !== undefined) {
      let types = type === undefined ? allFrpTypes() : [type];
      let locales: string[] = [FrpTemplateManager.ENGLISH_LOCALE];
      // The Chinese resource directory is tried first on this app's primary
      // locale; the English set remains a deterministic fallback.
      locales.unshift(FrpTemplateManager.CHINESE_LOCALE);
      for (let item of types) {
        let loadedForType: boolean = false;
        for (let locale of locales) {
          if (loadedForType) {
            break;
          }
          let path = `${FrpTemplateManager.RAWFILE_ROOT}/${locale}/${item}`;
          try {
            let names = FrpTemplateManager.context.resourceManager.getRawFileListSync(path);
            for (let name of names) {
              if (!name.toLowerCase().endsWith(FrpConfig.FILE_EXTENSION)) {
                continue;
              }
              let rawPath = `${path}/${name}`;
              let firstLine = FrpTemplateManager.firstLine(rawPath);
              result.push(new FrpConfigTemplate(item, rawPath, name, firstLine));
            }
            if (names.length > 0) {
              loadedForType = true;
            }
          } catch (e) {
            // Try the next locale when a rawfile directory is unavailable.
          }
        }
      }
    }
    if (result.length === 0) {
      let types = type === undefined ? allFrpTypes() : [type];
      for (let item of types) {
        result.push(...FrpTemplateManager.builtInTemplates(item));
      }
    }
    return result;
  }

  static get(type: FrpType, fileName: string): FrpConfigTemplate | undefined {
    let templates = FrpTemplateManager.list(type);
    for (let template of templates) {
      if (template.fileName === fileName) {
        return template;
      }
    }
    return undefined;
  }

  static read(template: FrpConfigTemplate): string {
    if (FrpTemplateManager.context !== undefined && template.rawfilePath !== '') {
      try {
        let data = FrpTemplateManager.context.resourceManager.getRawFileContentSync(template.rawfilePath);
        return new util.TextDecoder('utf-8').decodeToString(data);
      } catch (e) {
        // Built-in content is used if rawfile loading fails.
      }
    }
    return FrpTemplateManager.builtInContent(template.type, template.fileName);
  }

  static createConfig(type: FrpType, template: FrpConfigTemplate, fileName: string): FrpConfig {
    if (type !== template.type) {
      throw new Error('Template type does not match the requested FRP type.');
    }
    let content = FrpTemplateManager.read(template);
    let safeName = FrpValidator.normalizeFileName(fileName);
    let config = new FrpConfig(type, safeName, template.displayName);
    let validation = FrpValidator.validateConfig(config, content);
    if (!validation.valid) {
      throw new Error(validation.message);
    }
    return config;
  }

  private static firstLine(path: string): string {
    try {
      if (FrpTemplateManager.context !== undefined) {
        let data = FrpTemplateManager.context.resourceManager.getRawFileContentSync(path);
        let text = new util.TextDecoder('utf-8').decodeToString(data);
        for (let line of text.replace(/\r\n/g, '\n').split('\n')) {
          let trimmed = line.trim();
          if (trimmed.startsWith('#')) {
            let title = trimmed.substring(1).trim();
            if (title !== '') {
              return title;
            }
          }
        }
      }
    } catch (e) {
      // use file name
    }
    return path.substring(path.lastIndexOf('/') + 1);
  }

  private static builtInTemplates(type: FrpType): FrpConfigTemplate[] {
    if (type === FrpType.FRPC) {
      return [new FrpConfigTemplate(type, '', 'basic-frpc.toml', 'Basic frpc client')];
    }
    return [new FrpConfigTemplate(type, '', 'basic-frps.toml', 'Basic frps server')];
  }

  private static builtInContent(type: FrpType, fileName: string): string {
    if (type === FrpType.FRPC || fileName.toLowerCase().indexOf('frpc') !== -1) {
      return '# Basic frpc client configuration\nserverAddr = "127.0.0.1"\nserverPort = 7000\n\n[log]\nlevel = "info"\ndisablePrintColor = true\n\n[[proxies]]\nname = "ssh"\ntype = "tcp"\nlocalIP = "127.0.0.1"\nlocalPort = 22\nremotePort = 6000\n';
    }
    return '# Basic frps server configuration\nbindPort = 7000\n\n[log]\nlevel = "info"\ndisablePrintColor = true\n';
  }
}
