export enum FrpTunnelType {
  TCP = 'tcp',
  UDP = 'udp'
}

export class FrpTunnelDraft {
  id: string;
  name: string;
  type: FrpTunnelType;
  localIP: string;
  localPort: string;
  remotePort: string;

  constructor(id: string = 'proxy-1', name: string = 'ssh', type: FrpTunnelType = FrpTunnelType.TCP,
    localIP: string = '127.0.0.1', localPort: string = '22', remotePort: string = '10022') {
    this.id = id;
    this.name = name;
    this.type = type;
    this.localIP = localIP;
    this.localPort = localPort;
    this.remotePort = remotePort;
  }
}

export class FrpClientFormDraft {
  serverAddr: string;
  serverPort: string;
  token: string;
  user: string;
  tunnels: FrpTunnelDraft[];

  constructor(serverAddr: string = 'frp.example.com', serverPort: string = '7000',
    token: string = '', user: string = '', tunnels?: FrpTunnelDraft[]) {
    this.serverAddr = serverAddr;
    this.serverPort = serverPort;
    this.token = token;
    this.user = user;
    this.tunnels = tunnels === undefined ? [new FrpTunnelDraft()] : tunnels;
  }
}

export class FrpFormValidationResult {
  valid: boolean;
  message: string;

  constructor(valid: boolean = true, message: string = '') {
    this.valid = valid;
    this.message = message;
  }
}

export class FrpFormParseResult {
  compatible: boolean;
  message: string;
  draft?: FrpClientFormDraft;

  constructor(compatible: boolean = false, message: string = '', draft?: FrpClientFormDraft) {
    this.compatible = compatible;
    this.message = message;
    this.draft = draft;
  }
}

class FrpTomlStringResult {
  valid: boolean;
  value: string;
  message: string;

  constructor(valid: boolean, value: string = '', message: string = '') {
    this.valid = valid;
    this.value = value;
    this.message = message;
  }
}

class FrpParsedProxy {
  name: string = '';
  type: FrpTunnelType = FrpTunnelType.TCP;
  localIP: string = '';
  localPort: string = '';
  remotePort: string = '';
  nameSet: boolean = false;
  typeSet: boolean = false;
  localIPSet: boolean = false;
  localPortSet: boolean = false;
  remotePortSet: boolean = false;
  keys: Set<string> = new Set<string>();
}

class FrpFormParseState {
  serverAddr: string = '';
  serverPort: string = '';
  user: string = '';
  authMethod: string = '';
  authToken: string = '';
  serverAddrSet: boolean = false;
  serverPortSet: boolean = false;
  userSet: boolean = false;
  authMethodSet: boolean = false;
  authTokenSet: boolean = false;
  authTableSeen: boolean = false;
  currentTable: string = '';
  rootKeys: Set<string> = new Set<string>();
  authKeys: Set<string> = new Set<string>();
  proxies: FrpParsedProxy[] = [];
  currentProxy?: FrpParsedProxy;
}

/** Conservative codec for the simple frpc TCP/UDP form subset. */
export class FrpFormCodec {
  static createDefaultDraft(): FrpClientFormDraft {
    return new FrpClientFormDraft('frp.example.com', '7000', '', '', [
      new FrpTunnelDraft('proxy-1', 'ssh', FrpTunnelType.TCP, '127.0.0.1', '22', '10022')
    ]);
  }

  static defaultDraft(): FrpClientFormDraft {
    return FrpFormCodec.createDefaultDraft();
  }

  static nextTunnelId(draft: FrpClientFormDraft): string {
    let sequence = 1;
    while (true) {
      let candidate = `proxy-${sequence}`;
      let used = false;
      for (let tunnel of draft.tunnels) {
        if (tunnel.id === candidate) {
          used = true;
          break;
        }
      }
      if (!used) {
        return candidate;
      }
      sequence++;
    }
    return '';
  }

  static validate(draft: FrpClientFormDraft): FrpFormValidationResult {
    if (draft === undefined || draft === null) {
      return new FrpFormValidationResult(false, '表单数据不存在');
    }
    if (draft.serverAddr.trim() === '') {
      return new FrpFormValidationResult(false, '服务器地址不能为空');
    }
    if (!FrpFormCodec.isPort(draft.serverPort)) {
      return new FrpFormValidationResult(false, '服务器端口必须是 1-65535 的整数');
    }
    if (draft.tunnels === undefined || draft.tunnels.length === 0) {
      return new FrpFormValidationResult(false, '至少需要一个隧道');
    }

    let names: Set<string> = new Set<string>();
    let ids: Set<string> = new Set<string>();
    for (let i = 0; i < draft.tunnels.length; i++) {
      let tunnel = draft.tunnels[i];
      let label = `第 ${i + 1} 个隧道`;
      let id = tunnel.id.trim();
      let name = tunnel.name.trim();
      if (id === '') {
        return new FrpFormValidationResult(false, `${label}的本地标识不能为空`);
      }
      if (ids.has(id)) {
        return new FrpFormValidationResult(false, `${label}的本地标识重复`);
      }
      ids.add(id);
      if (name === '') {
        return new FrpFormValidationResult(false, `${label}的名称不能为空`);
      }
      if (names.has(name)) {
        return new FrpFormValidationResult(false, `隧道名称“${name}”重复`);
      }
      names.add(name);
      if (tunnel.type !== FrpTunnelType.TCP && tunnel.type !== FrpTunnelType.UDP) {
        return new FrpFormValidationResult(false, `${label}的类型仅支持 tcp 或 udp`);
      }
      if (tunnel.localIP.trim() === '') {
        return new FrpFormValidationResult(false, `${label}的本地地址不能为空`);
      }
      if (!FrpFormCodec.isPort(tunnel.localPort)) {
        return new FrpFormValidationResult(false, `${label}的本地端口必须是 1-65535 的整数`);
      }
      if (!FrpFormCodec.isPort(tunnel.remotePort)) {
        return new FrpFormValidationResult(false, `${label}的远程端口必须是 1-65535 的整数`);
      }
    }
    return new FrpFormValidationResult(true, '');
  }

  static serialize(draft: FrpClientFormDraft): string {
    let validation = FrpFormCodec.validate(draft);
    if (!validation.valid) {
      throw new Error(validation.message);
    }

    let user = draft.user;
    let lines: string[] = [];
    lines.push('# Generated by the FRP form editor.');
    lines.push(`serverAddr = "${FrpFormCodec.escapeTomlString(draft.serverAddr)}"`);
    lines.push(`serverPort = ${draft.serverPort}`);
    if (user !== '') {
      lines.push(`user = "${FrpFormCodec.escapeTomlString(user)}"`);
    }
    if (draft.token !== '') {
      lines.push('auth.method = "token"');
      lines.push(`auth.token = "${FrpFormCodec.escapeTomlString(draft.token)}"`);
    }

    for (let tunnel of draft.tunnels) {
      lines.push('');
      lines.push('[[proxies]]');
      lines.push(`name = "${FrpFormCodec.escapeTomlString(tunnel.name)}"`);
      lines.push(`type = "${tunnel.type}"`);
      lines.push(`localIP = "${FrpFormCodec.escapeTomlString(tunnel.localIP)}"`);
      lines.push(`localPort = ${tunnel.localPort}`);
      lines.push(`remotePort = ${tunnel.remotePort}`);
    }
    return lines.join('\n') + '\n';
  }

  static parse(content: string): FrpFormParseResult {
    if (content === undefined || content === null || content.trim() === '') {
      return FrpFormCodec.incompatible('配置内容为空');
    }

    let state = new FrpFormParseState();
    let lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    for (let index = 0; index < lines.length; index++) {
      let lineNumber = index + 1;
      let line = FrpFormCodec.stripComment(lines[index]).trim();
      if (line === '') {
        continue;
      }

      if (line.startsWith('[')) {
        let tableResult = FrpFormCodec.readTable(line, lineNumber, state);
        if (tableResult !== undefined) {
          return tableResult;
        }
        continue;
      }

      let equals = FrpFormCodec.findAssignmentSeparator(line);
      if (equals < 1) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：仅支持单行键值赋值`);
      }
      let key = line.substring(0, equals).trim();
      let rawValue = line.substring(equals + 1).trim();
      if (!/^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*$/.test(key) || rawValue === '') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：键名或值不是受支持的简单 TOML 语法`);
      }

      let assignmentResult = FrpFormCodec.readAssignment(state, key, rawValue, lineNumber);
      if (assignmentResult !== undefined) {
        return assignmentResult;
      }
    }

    return FrpFormCodec.finishParse(state);
  }

  private static readTable(line: string, lineNumber: number,
    state: FrpFormParseState): FrpFormParseResult | undefined {
    if (line.startsWith('[[')) {
      if (!line.endsWith(']]') || line.length < 5) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：数组表语法不完整`);
      }
      let name = line.substring(2, line.length - 2).trim();
      if (name !== 'proxies' || name.indexOf('[') !== -1 || name.indexOf(']') !== -1) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：表单模式仅支持 [[proxies]] 数组表`);
      }
      let proxy = new FrpParsedProxy();
      state.proxies.push(proxy);
      state.currentProxy = proxy;
      state.currentTable = 'proxies';
      return undefined;
    }

    if (!line.endsWith(']') || line.length < 3) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：表语法不完整`);
    }
    let name = line.substring(1, line.length - 1).trim();
    if (name !== 'auth' || name.indexOf('[') !== -1 || name.indexOf(']') !== -1) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：表单模式仅支持 [auth] 表`);
    }
    if (state.authTableSeen || state.authMethodSet || state.authTokenSet) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth 配置重复或混用了点键与表写法`);
    }
    if (state.proxies.length > 0) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：[auth] 不能出现在 [[proxies]] 之后`);
    }
    state.authTableSeen = true;
    state.currentProxy = undefined;
    state.currentTable = 'auth';
    return undefined;
  }

  private static readAssignment(state: FrpFormParseState, key: string, rawValue: string,
    lineNumber: number): FrpFormParseResult | undefined {
    if (state.currentTable === '') {
      return FrpFormCodec.readRootAssignment(state, key, rawValue, lineNumber);
    }
    if (state.currentTable === 'auth') {
      return FrpFormCodec.readAuthAssignment(state, key, rawValue, lineNumber);
    }
    if (state.currentTable === 'proxies' && state.currentProxy !== undefined) {
      return FrpFormCodec.readProxyAssignment(state.currentProxy, key, rawValue, lineNumber);
    }
    return FrpFormCodec.incompatible(`第 ${lineNumber} 行：字段不属于受支持的表`);
  }

  private static readRootAssignment(state: FrpFormParseState, key: string, rawValue: string,
    lineNumber: number): FrpFormParseResult | undefined {
    if (key !== 'serverAddr' && key !== 'serverPort' && key !== 'user' &&
      key !== 'auth.method' && key !== 'auth.token') {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：不支持顶层字段“${key}”`);
    }
    if (state.rootKeys.has(key)) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：字段“${key}”重复`);
    }
    state.rootKeys.add(key);

    if (key === 'serverPort') {
      if (state.proxies.length > 0) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：顶层字段不能出现在 [[proxies]] 之后`);
      }
      let port = FrpFormCodec.parseSimplePort(rawValue);
      if (port === undefined) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：serverPort 必须是 1-65535 的简单整数`);
      }
      state.serverPort = port;
      state.serverPortSet = true;
      return undefined;
    }

    let stringResult = FrpFormCodec.parseTomlString(rawValue);
    if (!stringResult.valid) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：${key} ${stringResult.message}`);
    }
    if (key === 'serverAddr') {
      state.serverAddr = stringResult.value;
      state.serverAddrSet = true;
    } else if (key === 'user') {
      if (stringResult.value === '') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：user 为空时应删除该字段`);
      }
      state.user = stringResult.value;
      state.userSet = true;
    } else if (key === 'auth.method') {
      if (state.authTableSeen || state.authKeys.has('method')) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.method 重复或混用了点键与表写法`);
      }
      if (stringResult.value !== 'token') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.method 仅支持 token`);
      }
      state.authKeys.add('method');
      state.authMethod = stringResult.value;
      state.authMethodSet = true;
    } else {
      if (state.authTableSeen || state.authKeys.has('token')) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.token 重复或混用了点键与表写法`);
      }
      if (stringResult.value === '') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.token 不能为空`);
      }
      state.authKeys.add('token');
      state.authToken = stringResult.value;
      state.authTokenSet = true;
    }
    return undefined;
  }

  private static readAuthAssignment(state: FrpFormParseState, key: string, rawValue: string,
    lineNumber: number): FrpFormParseResult | undefined {
    if (key !== 'method' && key !== 'token') {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：[auth] 中不支持字段“${key}”`);
    }
    if (state.authKeys.has(key)) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：[auth] 字段“${key}”重复`);
    }
    let stringResult = FrpFormCodec.parseTomlString(rawValue);
    if (!stringResult.valid) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.${key} ${stringResult.message}`);
    }
    if (key === 'method') {
      if (stringResult.value !== 'token') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.method 仅支持 token`);
      }
      state.authMethod = stringResult.value;
      state.authMethodSet = true;
    } else {
      if (stringResult.value === '') {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：auth.token 不能为空`);
      }
      state.authToken = stringResult.value;
      state.authTokenSet = true;
    }
    state.authKeys.add(key);
    return undefined;
  }

  private static readProxyAssignment(proxy: FrpParsedProxy, key: string, rawValue: string,
    lineNumber: number): FrpFormParseResult | undefined {
    if (key !== 'name' && key !== 'type' && key !== 'localIP' && key !== 'localPort' &&
      key !== 'remotePort') {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：[[proxies]] 中不支持字段“${key}”`);
    }
    if (proxy.keys.has(key)) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：代理字段“${key}”重复`);
    }
    proxy.keys.add(key);

    if (key === 'localPort' || key === 'remotePort') {
      let port = FrpFormCodec.parseSimplePort(rawValue);
      if (port === undefined) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：${key} 必须是 1-65535 的简单整数`);
      }
      if (key === 'localPort') {
        proxy.localPort = port;
        proxy.localPortSet = true;
      } else {
        proxy.remotePort = port;
        proxy.remotePortSet = true;
      }
      return undefined;
    }

    let stringResult = FrpFormCodec.parseTomlString(rawValue);
    if (!stringResult.valid) {
      return FrpFormCodec.incompatible(`第 ${lineNumber} 行：${key} ${stringResult.message}`);
    }
    if (key === 'name') {
      proxy.name = stringResult.value;
      proxy.nameSet = true;
    } else if (key === 'type') {
      if (stringResult.value !== FrpTunnelType.TCP && stringResult.value !== FrpTunnelType.UDP) {
        return FrpFormCodec.incompatible(`第 ${lineNumber} 行：代理类型仅支持 tcp 或 udp`);
      }
      proxy.type = stringResult.value === FrpTunnelType.TCP ? FrpTunnelType.TCP : FrpTunnelType.UDP;
      proxy.typeSet = true;
    } else {
      proxy.localIP = stringResult.value;
      proxy.localIPSet = true;
    }
    return undefined;
  }

  private static finishParse(state: FrpFormParseState): FrpFormParseResult {
    if (!state.serverAddrSet) {
      return FrpFormCodec.incompatible('缺少顶层字段 serverAddr');
    }
    if (!state.serverPortSet) {
      return FrpFormCodec.incompatible('缺少顶层字段 serverPort');
    }
    if (state.authTableSeen && !state.authMethodSet && !state.authTokenSet) {
      return FrpFormCodec.incompatible('[auth] 表缺少 method 和 token');
    }
    if (state.authMethodSet !== state.authTokenSet) {
      return FrpFormCodec.incompatible('auth.method 与 auth.token 必须同时提供');
    }
    if (state.proxies.length === 0) {
      return FrpFormCodec.incompatible('至少需要一个 [[proxies]]');
    }

    let tunnels: FrpTunnelDraft[] = [];
    for (let i = 0; i < state.proxies.length; i++) {
      let proxy = state.proxies[i];
      let missing = FrpFormCodec.missingProxyField(proxy);
      if (missing !== '') {
        return FrpFormCodec.incompatible(`第 ${i + 1} 个代理缺少字段 ${missing}`);
      }
      tunnels.push(new FrpTunnelDraft(`proxy-${i + 1}`, proxy.name, proxy.type,
        proxy.localIP, proxy.localPort, proxy.remotePort));
    }

    let draft = new FrpClientFormDraft(state.serverAddr, state.serverPort,
      state.authTokenSet ? state.authToken : '', state.userSet ? state.user : '', tunnels);
    let validation = FrpFormCodec.validate(draft);
    if (!validation.valid) {
      return FrpFormCodec.incompatible(validation.message);
    }
    return new FrpFormParseResult(true, '', draft);
  }

  private static missingProxyField(proxy: FrpParsedProxy): string {
    if (!proxy.nameSet) {
      return 'name';
    }
    if (!proxy.typeSet) {
      return 'type';
    }
    if (!proxy.localIPSet) {
      return 'localIP';
    }
    if (!proxy.localPortSet) {
      return 'localPort';
    }
    if (!proxy.remotePortSet) {
      return 'remotePort';
    }
    return '';
  }

  private static parseSimplePort(rawValue: string): string | undefined {
    if (!FrpFormCodec.isPort(rawValue)) {
      return undefined;
    }
    return rawValue;
  }

  private static isPort(value: string): boolean {
    if (!/^[1-9][0-9]*$/.test(value)) {
      return false;
    }
    let numeric = Number(value);
    return isFinite(numeric) && Math.floor(numeric) === numeric && numeric >= 1 && numeric <= 65535;
  }

  private static incompatible(message: string): FrpFormParseResult {
    return new FrpFormParseResult(false, message);
  }

  private static stripComment(line: string): string {
    let quote = '';
    let escaped = false;
    for (let i = 0; i < line.length; i++) {
      let ch = line.charAt(i);
      if (quote === '"') {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          quote = '';
        }
        continue;
      }
      if (quote === "'") {
        if (ch === "'") {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '#') {
        return line.substring(0, i);
      }
    }
    return line;
  }

  private static findAssignmentSeparator(line: string): number {
    let quote = '';
    let escaped = false;
    for (let i = 0; i < line.length; i++) {
      let ch = line.charAt(i);
      if (quote === '"') {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          quote = '';
        }
        continue;
      }
      if (quote === "'") {
        if (ch === "'") {
          quote = '';
        }
        continue;
      }
      if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '=') {
        return i;
      }
    }
    return -1;
  }

  private static parseTomlString(rawValue: string): FrpTomlStringResult {
    if (rawValue.startsWith('"""') || rawValue.startsWith("'''")) {
      return new FrpTomlStringResult(false, '', '不支持多行字符串');
    }
    if (rawValue.length < 2) {
      return new FrpTomlStringResult(false, '', '必须使用单行引号字符串');
    }
    let quote = rawValue.charAt(0);
    if (quote !== '"' && quote !== "'") {
      return new FrpTomlStringResult(false, '', '必须使用单行引号字符串');
    }

    let value = '';
    for (let i = 1; i < rawValue.length; i++) {
      let ch = rawValue.charAt(i);
      if (ch === quote) {
        if (i !== rawValue.length - 1) {
          return new FrpTomlStringResult(false, '', '字符串后存在额外内容');
        }
        return new FrpTomlStringResult(true, value);
      }
      let code = rawValue.charCodeAt(i);
      if ((code < 32 && code !== 9) || code === 127) {
        return new FrpTomlStringResult(false, '', '包含不受支持的原始控制字符');
      }
      if (quote === "'" || ch !== '\\') {
        value += ch;
        continue;
      }
      if (i + 1 >= rawValue.length) {
        return new FrpTomlStringResult(false, '', '包含不完整的转义序列');
      }
      i++;
      let escaped = rawValue.charAt(i);
      if (escaped === '"' || escaped === '\\') {
        value += escaped;
      } else if (escaped === 'b') {
        value += '\b';
      } else if (escaped === 't') {
        value += '\t';
      } else if (escaped === 'n') {
        value += '\n';
      } else if (escaped === 'f') {
        value += '\f';
      } else if (escaped === 'r') {
        value += '\r';
      } else if (escaped === 'u' || escaped === 'U') {
        let digits = escaped === 'u' ? 4 : 8;
        if (i + digits >= rawValue.length) {
          return new FrpTomlStringResult(false, '', '包含不完整的 Unicode 转义');
        }
        let hex = rawValue.substring(i + 1, i + 1 + digits);
        if (!/^[0-9A-Fa-f]+$/.test(hex)) {
          return new FrpTomlStringResult(false, '', '包含无效的 Unicode 转义');
        }
        let codePoint = parseInt(hex, 16);
        if (codePoint > 1114111 || (codePoint >= 55296 && codePoint <= 57343)) {
          return new FrpTomlStringResult(false, '', '包含无效的 Unicode 码点');
        }
        value += FrpFormCodec.codePointToString(codePoint);
        i += digits;
      } else {
        return new FrpTomlStringResult(false, '', `包含不支持的转义 \\${escaped}`);
      }
    }
    return new FrpTomlStringResult(false, '', '字符串缺少结束引号');
  }

  private static codePointToString(codePoint: number): string {
    if (codePoint <= 65535) {
      return String.fromCharCode(codePoint);
    }
    let adjusted = codePoint - 65536;
    let high = 55296 + Math.floor(adjusted / 1024);
    let low = 56320 + adjusted % 1024;
    return String.fromCharCode(high, low);
  }

  private static escapeTomlString(value: string): string {
    let escaped = '';
    for (let i = 0; i < value.length; i++) {
      let ch = value.charAt(i);
      let code = value.charCodeAt(i);
      if (ch === '\\') {
        escaped += '\\\\';
      } else if (ch === '"') {
        escaped += '\\"';
      } else if (ch === '\b') {
        escaped += '\\b';
      } else if (ch === '\t') {
        escaped += '\\t';
      } else if (ch === '\n') {
        escaped += '\\n';
      } else if (ch === '\f') {
        escaped += '\\f';
      } else if (ch === '\r') {
        escaped += '\\r';
      } else if (code < 32 || code === 127) {
        let hex = code.toString(16).toUpperCase();
        while (hex.length < 4) {
          hex = '0' + hex;
        }
        escaped += `\\u${hex}`;
      } else {
        escaped += ch;
      }
    }
    return escaped;
  }
}
