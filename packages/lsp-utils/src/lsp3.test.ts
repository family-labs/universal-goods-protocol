import { describe, expect, it } from 'vitest';
import { generateOrganizationLSP3Metadata, generateUserLSP3Metadata } from './lsp3.js';

describe('generateUserLSP3Metadata', () => {
  it('carries the display name and nothing that identifies the account internally', async () => {
    const doc = await generateUserLSP3Metadata(
      {
        name: 'Olive Example',
        image: null,
        profileAddress: '0x00000000000000000000000000000000000d5a01',

        ...({ email: 'olive@example.com', userId: 'user_123' } as object),
      },
      'https://app.example',
    );
    const text = JSON.stringify(doc);
    expect(doc.LSP3Profile.name).toBe('Olive Example');
    expect(text).not.toContain('olive@example.com');
    expect(text).not.toContain('user_123');
    expect(text).not.toContain('UserId');
    expect(doc.LSP3Profile.profile).toBeUndefined();
    expect(doc.LSP3Profile.attributes).toBeUndefined();
  });
});

describe('generateOrganizationLSP3Metadata', () => {
  it('keeps name, description and links, but drops a link that is an email address', async () => {
    const doc = await generateOrganizationLSP3Metadata(
      {
        name: 'Acme Batteries',
        profileAddress: '0x00000000000000000000000000000000000d5a02',
        organizationId: 'org_1',
        slug: 'acme',
        description: 'We make packs.',
        links: [
          { title: 'Website', url: 'https://acme.example' },
          { title: 'Email us', url: 'mailto:jane.doe@acme.example' },
          { title: 'Sales', url: 'sales.person@acme.example' },
        ],
      },
      'https://app.example',
    );
    const text = JSON.stringify(doc);
    expect(doc.LSP3Profile.name).toBe('Acme Batteries');
    expect(doc.LSP3Profile.description).toBe('We make packs.');
    expect(doc.LSP3Profile.links.map((l) => l.url)).toEqual([
      'https://app.example/o/acme',
      'https://acme.example',
    ]);
    expect(text).not.toContain('@acme.example');
  });
});
