import { ERC725 } from '@erc725/erc725.js';
import LSP6Schema from '@erc725/erc725.js/schemas/LSP6KeyManager.json' with { type: 'json' };
import { verifyMessage } from 'ethers';
import { sameAddress, toBareAddress } from '@universal-goods/network-config';

/**
 * LSP6 Permission types
 */
export enum LSP6Permission {
  CHANGEOWNER = 'CHANGEOWNER',
  ADDCONTROLLER = 'ADDCONTROLLER',
  EDITPERMISSIONS = 'EDITPERMISSIONS',
  ADDEXTENSIONS = 'ADDEXTENSIONS',
  CHANGEEXTENSIONS = 'CHANGEEXTENSIONS',
  ADDUNIVERSALRECEIVERDELEGATE = 'ADDUNIVERSALRECEIVERDELEGATE',
  CHANGEUNIVERSALRECEIVERDELEGATE = 'CHANGEUNIVERSALRECEIVERDELEGATE',
  REENTRANCY = 'REENTRANCY',
  SUPER_TRANSFERVALUE = 'SUPER_TRANSFERVALUE',
  TRANSFERVALUE = 'TRANSFERVALUE',
  SUPER_CALL = 'SUPER_CALL',
  CALL = 'CALL',
  SUPER_STATICCALL = 'SUPER_STATICCALL',
  STATICCALL = 'STATICCALL',
  SUPER_DELEGATECALL = 'SUPER_DELEGATECALL',
  DELEGATECALL = 'DELEGATECALL',
  DEPLOY = 'DEPLOY',
  SUPER_SETDATA = 'SUPER_SETDATA',
  SETDATA = 'SETDATA',
  ENCRYPT = 'ENCRYPT',
  DECRYPT = 'DECRYPT',
  SIGN = 'SIGN',
  EXECUTE_RELAY_CALL = 'EXECUTE_RELAY_CALL',
}

/**
 * Check if a controller has specific LSP6 permissions on a Universal Profile
 * 
 * @param profileAddress - The Universal Profile address
 * @param controllerAddress - The controller address to check
 * @param requiredPermissions - Array of required permissions (e.g., ['SIGN', 'SUPER_SIGN'])
 * @param rpcUrl - RPC URL
 * @returns Object with hasPermission boolean and permission details
 */
export async function validateControllerPermissions(
  profileAddress: string,
  controllerAddress: string,
  requiredPermissions: string[],
  rpcUrl: string
): Promise<{
  hasPermission: boolean;
  grantedPermissions: string[];
  missingPermissions: string[];
  error?: string;
}> {
  try {
    /**
     * Normalised here rather than trusting the caller. ERC725.js does NOT validate the address
     * it is constructed with: `new ERC725(schema, 'local:0x…', rpc)` succeeds and stores the
     * prefixed string verbatim, and the failure only arrives at `getData` as the misleading
     * "Missing ERC725 contract address."
     */
    const erc725 = new ERC725(LSP6Schema as any, toBareAddress(profileAddress) ?? profileAddress, rpcUrl);
    
    // Get controller's permissions from the Universal Profile
    const permissionData = await erc725.getData({
      keyName: 'AddressPermissions:Permissions:<address>',
      dynamicKeyParts: controllerAddress,
    });
    
    if (!permissionData || !permissionData.value) {
      return {
        hasPermission: false,
        grantedPermissions: [],
        missingPermissions: requiredPermissions,
        error: 'Controller not found on Universal Profile',
      };
    }
    
    // Decode permissions
    const decodedPermissions = erc725.decodePermissions(permissionData.value as any);
    const grantedPermissions = Object.keys(decodedPermissions).filter(
      (key) => (decodedPermissions as any)[key] === true
    );
    
    // Check if all required permissions are granted
    const missingPermissions = requiredPermissions.filter(
      (perm) => !grantedPermissions.includes(perm)
    );
    
    return {
      hasPermission: missingPermissions.length === 0,
      grantedPermissions,
      missingPermissions,
    };
  } catch (error) {
    console.error('[LSP6] Error validating controller permissions:', error);
    return {
      hasPermission: false,
      grantedPermissions: [],
      missingPermissions: requiredPermissions,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Encodes LSP6 permissions
 * @param permissions - Object mapping permission names to booleans
 * @returns Encoded permissions as hex string
 */
export function encodeLSP6Permissions(permissions: Record<string, boolean>): string {
  const erc725 = new ERC725(LSP6Schema as any);
  return erc725.encodePermissions(permissions);
}

/**
 * Check if a controller can sign transactions for a Universal Profile
 * Requires SIGN permission (or optionally SUPER_SIGN for advanced operations)
 * 
 * @param profileAddress - The Universal Profile address
 * @param controllerAddress - The controller address to check
 * @param rpcUrl - RPC URL
 * @param allowSuperSign - Whether to accept SUPER_SIGN as alternative (default: true)
 * @returns Object with validation result
 */
export async function canControllerSign(
  profileAddress: string,
  controllerAddress: string,
  rpcUrl: string,
  allowSuperSign: boolean = true
): Promise<{
  canSign: boolean;
  reason?: string;
  grantedPermissions: string[];
}> {
  // SIGN permission is required for signing operations.
  const requiredPermissions = allowSuperSign ? ['SIGN'] : ['SIGN'];
  
  const validation = await validateControllerPermissions(
    profileAddress,
    controllerAddress,
    requiredPermissions,
    rpcUrl
  );
  
  if (validation.hasPermission) {
    return {
      canSign: true,
      grantedPermissions: validation.grantedPermissions,
    };
  }
  
  // LSP6 defines no SUPER_SIGN permission, so this second probe can only ever report it
  // missing. It is kept for API compatibility with `allowSuperSign`; the result is SIGN only.
  if (allowSuperSign && !validation.grantedPermissions.includes('SIGN')) {
     const superValidation = await validateControllerPermissions(
        profileAddress,
        controllerAddress,
        ['SUPER_SIGN'],
        rpcUrl
     );
  }

  return {
    canSign: false,
    reason: `Missing permissions: ${validation.missingPermissions.join(', ')}`,
    grantedPermissions: validation.grantedPermissions,
  };
}

export function verifyControllerSignature(
  message: string,
  signature: string,
  controllerAddress: string
): boolean {
  try {
    const recoveredAddress = verifyMessage(message, signature);
    /**
     * `sameAddress`, not a lower-cased `===`: the latter answers false for an ERC-3770 prefixed
     * `controllerAddress`, which would report a valid signature as invalid.
     */
    return sameAddress(recoveredAddress, controllerAddress);
  } catch (error) {
    return false;
  }
}


