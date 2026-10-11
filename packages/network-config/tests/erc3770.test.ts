import { describe, it, expect } from 'vitest';
import {
  parseERC3770Address,
  formatERC3770Address,
  isERC3770Address,
  getChainShortName,
  getChainIdFromShortName,
  extractRawAddress,
  extractChainId,
  resolveAddress,
  CHAIN_SHORT_NAMES,
  SHORT_NAME_TO_CHAIN_ID
} from '../src/erc3770.js';
import { SupportedChainId } from '../src/chains.js';

describe('ERC-3770 Address Utilities', () => {
  const testAddress = '0x1234567890123456789012345678901234567890';
  const invalidAddress = '0x123';

  describe('formatERC3770Address', () => {
    it('formats a local chain address correctly', () => {
      const result = formatERC3770Address(SupportedChainId.LOCAL, testAddress);
      expect(result).toBe(`local:${testAddress}`);
    });

    it('formats a LUKSO testnet address correctly', () => {
      const result = formatERC3770Address(SupportedChainId.LUKSO_TESTNET, testAddress);
      expect(result).toBe(`lukso-testnet:${testAddress}`);
    });

    it('formats an Ethereum mainnet address using chains_mini.json', () => {
      const result = formatERC3770Address(1, testAddress);
      expect(result).toBe(`eth:${testAddress}`);
    });

    it('throws error for invalid address', () => {
      expect(() => {
        formatERC3770Address(SupportedChainId.LOCAL, invalidAddress);
      }).toThrow('Invalid Ethereum address format');
    });

    it('throws error for unsupported chain', () => {
      expect(() => {
        formatERC3770Address(99999999, testAddress);
      }).toThrow('Unsupported chain ID');
    });
  });

  describe('parseERC3770Address', () => {
    it('parses a valid local chain address', () => {
      const result = parseERC3770Address(`local:${testAddress}`);
      expect(result).toEqual({
        chainId: SupportedChainId.LOCAL,
        shortName: 'local',
        address: testAddress
      });
    });

    it('parses a valid LUKSO testnet address', () => {
      const result = parseERC3770Address(`lukso-testnet:${testAddress}`);
      expect(result).toEqual({
        chainId: SupportedChainId.LUKSO_TESTNET,
        shortName: 'lukso-testnet',
        address: testAddress
      });
    });

    it('parses an Ethereum mainnet address from chains_mini.json', () => {
      const result = parseERC3770Address(`eth:${testAddress}`);
      expect(result).toEqual({
        chainId: 1,
        shortName: 'eth',
        address: testAddress
      });
    });

    it('returns null for invalid format (no colon)', () => {
      const result = parseERC3770Address(testAddress);
      expect(result).toBeNull();
    });

    it('returns null for invalid format (multiple colons)', () => {
      const result = parseERC3770Address(`local:extra:${testAddress}`);
      expect(result).toBeNull();
    });

    it('returns null for invalid address', () => {
      const result = parseERC3770Address(`local:${invalidAddress}`);
      expect(result).toBeNull();
    });

    it('returns null for unknown chain', () => {
      const result = parseERC3770Address(`unknown-chain:${testAddress}`);
      expect(result).toBeNull();
    });

    it('returns null for null input', () => {
      const result = parseERC3770Address(null as any);
      expect(result).toBeNull();
    });

    it('returns null for undefined input', () => {
      const result = parseERC3770Address(undefined as any);
      expect(result).toBeNull();
    });

    it('returns null for non-string input', () => {
      const result = parseERC3770Address(123 as any);
      expect(result).toBeNull();
    });
  });

  describe('isERC3770Address', () => {
    it('returns true for valid ERC-3770 address', () => {
      expect(isERC3770Address(`local:${testAddress}`)).toBe(true);
      expect(isERC3770Address(`lukso-testnet:${testAddress}`)).toBe(true);
    });

    it('returns true for any chain in chains_mini.json', () => {
      expect(isERC3770Address(`eth:${testAddress}`)).toBe(true);
      expect(isERC3770Address(`pol:${testAddress}`)).toBe(true);
    });

    it('returns false for plain address', () => {
      expect(isERC3770Address(testAddress)).toBe(false);
    });

    it('returns false for invalid format', () => {
      expect(isERC3770Address('invalid')).toBe(false);
      expect(isERC3770Address(`local:${invalidAddress}`)).toBe(false);
    });
  });

  describe('getChainShortName', () => {
    it('returns correct short name for local chain', () => {
      expect(getChainShortName(SupportedChainId.LOCAL)).toBe('local');
    });

    it('returns correct short name for LUKSO testnet', () => {
      expect(getChainShortName(SupportedChainId.LUKSO_TESTNET)).toBe('lukso-testnet');
    });

    it('returns correct short name for Ethereum mainnet from chains_mini.json', () => {
      expect(getChainShortName(1)).toBe('eth');
    });

    it('returns undefined for unsupported chain', () => {
      expect(getChainShortName(99999999)).toBeUndefined();
    });
  });

  describe('getChainIdFromShortName', () => {
    it('returns correct chain ID for local', () => {
      expect(getChainIdFromShortName('local')).toBe(SupportedChainId.LOCAL);
    });

    it('returns correct chain ID for lukso-testnet', () => {
      expect(getChainIdFromShortName('lukso-testnet')).toBe(SupportedChainId.LUKSO_TESTNET);
    });

    it('returns correct chain ID for eth from chains_mini.json', () => {
      expect(getChainIdFromShortName('eth')).toBe(1);
    });

    it('returns undefined for unknown short name', () => {
      expect(getChainIdFromShortName('unknown')).toBeUndefined();
    });
  });

  describe('extractRawAddress', () => {
    it('extracts address from ERC-3770 format', () => {
      expect(extractRawAddress(`lukso-testnet:${testAddress}`)).toBe(testAddress);
    });

    it('returns raw address unchanged', () => {
      expect(extractRawAddress(testAddress)).toBe(testAddress);
    });

    it('returns non-address strings unchanged', () => {
      expect(extractRawAddress('hello')).toBe('hello');
    });
  });

  describe('extractChainId', () => {
    it('extracts chain ID from ERC-3770 format', () => {
      expect(extractChainId(`lukso-testnet:${testAddress}`)).toBe(SupportedChainId.LUKSO_TESTNET);
    });

    it('returns undefined for raw address', () => {
      expect(extractChainId(testAddress)).toBeUndefined();
    });

    it('returns fallback for raw address', () => {
      expect(extractChainId(testAddress, 42)).toBe(42);
    });
  });

  describe('resolveAddress', () => {
    it('resolves ERC-3770 to raw address and chain ID', () => {
      const result = resolveAddress(`lukso-testnet:${testAddress}`);
      expect(result).toEqual({
        address: testAddress,
        chainId: SupportedChainId.LUKSO_TESTNET,
      });
    });

    it('returns raw address with fallback chain ID', () => {
      const result = resolveAddress(testAddress, 4201);
      expect(result).toEqual({
        address: testAddress,
        chainId: 4201,
      });
    });

    it('returns raw address with undefined chain when no fallback', () => {
      const result = resolveAddress(testAddress);
      expect(result).toEqual({
        address: testAddress,
        chainId: undefined,
      });
    });
  });

  describe('CHAIN_SHORT_NAMES mapping', () => {
    it('has all supported chains defined', () => {
      expect(CHAIN_SHORT_NAMES[SupportedChainId.LOCAL]).toBeDefined();
      expect(CHAIN_SHORT_NAMES[SupportedChainId.LUKSO_TESTNET]).toBeDefined();
    });
  });

  describe('SHORT_NAME_TO_CHAIN_ID mapping', () => {
    it('has reverse mapping for all chains', () => {
      expect(SHORT_NAME_TO_CHAIN_ID['local']).toBe(SupportedChainId.LOCAL);
      expect(SHORT_NAME_TO_CHAIN_ID['lukso-testnet']).toBe(SupportedChainId.LUKSO_TESTNET);
    });
  });
});
