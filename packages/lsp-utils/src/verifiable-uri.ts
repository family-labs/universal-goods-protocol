import { keccak256, toUtf8Bytes, hexlify } from 'ethers';
import { KECCAK256_UTF8_SELECTOR } from './constants.js';

/**
 * Computes keccak256 hash from a data URL
 * @param dataUrl - The data URL string
 * @returns The hash as a hex string (without 0x prefix) or undefined if invalid
 */
export function computeHashFromDataUrl(dataUrl: string): string | undefined {
  if (!dataUrl.startsWith('data:')) return undefined;
  
  const matches = dataUrl.match(/^data:([^;]+);base64,(.+)$/);
  if (matches) {
    const base64Data = matches[2];
    try {
        if (typeof Buffer !== 'undefined') {
            const buffer = Buffer.from(base64Data, 'base64');
            return keccak256(buffer).replace('0x', '');
        } else {
            const binaryString = atob(base64Data);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            return keccak256(bytes).replace('0x', '');
        }
    } catch (e) {
        return undefined;
    }
  }
  return undefined;
}

/**
 * Encodes a verifiable URI according to the VerifiableURI standard
 * https://docs.lukso.tech/standards/universal-profile/lsp2-json-schema/#verifiableuri
 * 
 * Format: 0x[hashFunction][hash][url]
 * - hashFunction: 0x6f357c6a (keccak256(utf8))
 * - hash: 32 bytes keccak256 hash of the JSON file
 * - url: utf8 encoded URL
 * 
 * @param url - The URL to encode
 * @param hash - Optional keccak256 hash of the resource at the URL (as 0x-prefixed hex string)
 * @returns Encoded verifiable URI as a hex string
 */
export async function encodeVerifiableURI(url: string, hash?: string): Promise<string> {
  let hashValue = hash ? hash.replace('0x', '') : '';

  if (!hashValue) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        console.warn(`Failed to fetch URL for hashing: ${url}`);
        hashValue = '0'.repeat(64);
      } else {
        const arrayBuffer = await response.arrayBuffer();
        const buffer = new Uint8Array(arrayBuffer);
        hashValue = keccak256(buffer).replace('0x', '');
      }
    } catch (error) {
      console.warn(`Error fetching URL for hashing: ${url}`, error);
      hashValue = '0'.repeat(64);
    }
  }
  
  const urlHex = hexlify(toUtf8Bytes(url)).replace('0x', '');
  
  return `0x${KECCAK256_UTF8_SELECTOR}${hashValue}${urlHex}`;
}
