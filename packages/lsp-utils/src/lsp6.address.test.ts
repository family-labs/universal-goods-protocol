import { describe, it, expect } from 'vitest';
import { Wallet } from 'ethers';
import { verifyControllerSignature } from './lsp6.js';

const MESSAGE = 'universal-goods:controller-proof:1';

const CONTROLLER = new Wallet(
  '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
);

describe('verifyControllerSignature compares by value, not by spelling', () => {
  it('accepts the controller address as ethers checksums it', async () => {
    const signature = await CONTROLLER.signMessage(MESSAGE);
    expect(verifyControllerSignature(MESSAGE, signature, CONTROLLER.address)).toBe(true);
  });

  it('accepts it lower-cased, as a database column holds it', async () => {
    const signature = await CONTROLLER.signMessage(MESSAGE);
    expect(
      verifyControllerSignature(MESSAGE, signature, CONTROLLER.address.toLowerCase()),
    ).toBe(true);
  });

  it('accepts it ERC-3770 prefixed — this used to answer false and blame the signature', async () => {
    const signature = await CONTROLLER.signMessage(MESSAGE);
    expect(
      verifyControllerSignature(MESSAGE, signature, `lukso-testnet:${CONTROLLER.address}`),
    ).toBe(true);
    expect(
      verifyControllerSignature(MESSAGE, signature, `local:${CONTROLLER.address.toLowerCase()}`),
    ).toBe(true);
  });

  it('still refuses a signature from a DIFFERENT controller, in every spelling', async () => {
    const other = Wallet.createRandom();
    const signature = await other.signMessage(MESSAGE);
    expect(verifyControllerSignature(MESSAGE, signature, CONTROLLER.address)).toBe(false);
    expect(
      verifyControllerSignature(MESSAGE, signature, `lukso-testnet:${CONTROLLER.address}`),
    ).toBe(false);
  });

  it('still refuses a tampered message and a malformed signature', async () => {
    const signature = await CONTROLLER.signMessage(MESSAGE);
    expect(verifyControllerSignature('something else', signature, CONTROLLER.address)).toBe(false);
    expect(verifyControllerSignature(MESSAGE, '0xdeadbeef', CONTROLLER.address)).toBe(false);
  });

  it('refuses when the controller address is not an address at all', async () => {
    const signature = await CONTROLLER.signMessage(MESSAGE);
    expect(verifyControllerSignature(MESSAGE, signature, 'not-an-address')).toBe(false);
    expect(verifyControllerSignature(MESSAGE, signature, '')).toBe(false);
  });
});
