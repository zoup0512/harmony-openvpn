/**
 * FRP executable/configuration kind.
 *
 * FRP binaries are deliberately not started from this domain layer.  The type
 * only owns paths and names which can be shared by a future service layer.
 */
export enum FrpType {
  FRPC = 'frpc',
  FRPS = 'frps'
}

export function parseFrpType(value: string): FrpType | undefined {
  let normalized = value.trim().toLowerCase();
  if (normalized === FrpType.FRPC) {
    return FrpType.FRPC;
  }
  if (normalized === FrpType.FRPS) {
    return FrpType.FRPS;
  }
  return undefined;
}

export function isFrpClient(type: FrpType): boolean {
  return type === FrpType.FRPC;
}

export function frpConfigDirectory(rootDirectory: string, type: FrpType): string {
  return `${rootDirectory}/${type}`;
}

export function frpLogDirectory(rootDirectory: string, type: FrpType): string {
  return `${rootDirectory}/logs/${type}`;
}

export function frpTypeName(type: FrpType): string {
  return type;
}

export function allFrpTypes(): FrpType[] {
  return [FrpType.FRPC, FrpType.FRPS];
}
