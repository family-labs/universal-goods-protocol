import { encodeVerifiableURI, computeHashFromDataUrl } from './verifiable-uri.js';

/**
 * LSP3 Profile Metadata Interface
 * Based on the LSP3 Universal Profile Metadata standard
 * https://docs.lukso.tech/standards/universal-profile/lsp3-profile-metadata/
 */
export interface LSP3ProfileMetadata {
  LSP3Profile: {
    name: string;
    description: string;
    links: Array<{ title: string; url: string }>;
    tags: string[];
    avatar?: Array<{
      width: number;
      height: number;
      url: string;
      verification: {
        method: string;
        data: string;
      };
    }>;
    profileImage?: Array<{
      width: number;
      height: number;
      url: string;
      verification: {
        method: string;
        data: string;
      };
    }>;
    backgroundImage?: Array<{
      width: number;
      height: number;
      url: string;
      verification: {
        method: string;
        data: string;
      };
    }>;
    profile?: {
      email?: string;
    };
    attributes?: Array<{
      key: string;
      value: string;
      type: string;
    }>;
  };
}

/**
 * Creates an LSP3 image entry with verification data
 * @param imageUrl - The full URL to the image
 * @param imageData - Optional raw image data (data URL) to compute hash directly
 * @returns LSP3 image entry with verification
 */
export async function createLSP3ImageEntry(imageUrl: string, imageData?: string | null) {
  let hash: string | undefined;
  
  if (imageData) {
    hash = computeHashFromDataUrl(imageData);
  }

  return {
    width: 512,
    height: 512,
    url: imageUrl,
    verification: {
      method: 'keccak256(utf8)',
      data: await encodeVerifiableURI(imageUrl, hash),
    },
  };
}

/**
 * Resolves image URL for LSP3 metadata
 * @param image - Original image URL or data URL
 * @param profileAddress - Profile address for constructing fallback URL
 * @param appHost - Application host URL
 * @returns Resolved image URL
 */
export function resolveImageUrl(image: string, profileAddress: string, appHost: string): string {
  return image.startsWith('http') 
    ? image 
    : `${appHost}/api/public/profile/${profileAddress}/image`;
}

/**
 * Generates LSP3 metadata for a user profile
 *
 * NO EMAIL AND NO INTERNAL USER ID, EVER. This document is public, and its hash is written to
 * the person's profile on a public blockchain, permanently. An email or user id in it would let
 * anyone confirm a guessed "this address is this person's email" forever, even after the
 * profile is made private again. The parameter type does not accept either field, so a caller
 * cannot add them by passing them. What remains is what the person chose to show: a display
 * name and a picture.
 *
 * @param params - User profile parameters
 * @param appHost - Application host URL
 * @returns LSP3 metadata object
 */
export async function generateUserLSP3Metadata(params: {
  name: string;
  image?: string | null;
  profileAddress: string;
}, appHost: string): Promise<LSP3ProfileMetadata> {
  const { name, image, profileAddress } = params;
  
  const publicProfileUrl = `${appHost}/public/profile/${profileAddress}`;
  
  const metadata: LSP3ProfileMetadata = {
    LSP3Profile: {
      name: name || 'Universal Goods User',
      description: 'Universal Goods user profile',
      links: [
        {
          title: 'Universal Goods Profile',
          url: publicProfileUrl,
        },
      ],
      tags: ['universal-goods', 'user'],
    },
  };
  
  // Add avatar/profile image if available
  if (image) {
    const imageUrl = resolveImageUrl(image, profileAddress, appHost);
    const imageEntry = await createLSP3ImageEntry(imageUrl, image);

    metadata.LSP3Profile.avatar = [imageEntry];
    metadata.LSP3Profile.profileImage = [imageEntry];
  }

  return metadata;
}

/** A link that is really an email address (`mailto:` or a bare `name@host`). */
function isEmailLink(link: { title: string; url: string }): boolean {
  const url = link.url.trim().toLowerCase();
  return url.startsWith('mailto:') || /^[^\s/@:]+@[^\s/@]+\.[^\s/@]+$/.test(url);
}

/**
 * Generates LSP3 metadata for an organization profile
 * @param params - Organization profile parameters
 * @param appHost - Application host URL
 * @returns LSP3 metadata object
 */
export async function generateOrganizationLSP3Metadata(params: {
  name: string;
  logo?: string | null;
  image?: string | null;
  profileAddress: string;
  organizationId: string;
  slug?: string | null;
  /** Organisation-supplied description. Optional: without it a default sentence is used. */
  description?: string | null;
  /** Extra organisation-supplied links, added AFTER the organisation's own link, never in place of it. */
  links?: Array<{ title: string; url: string }> | null;
}, appHost: string): Promise<LSP3ProfileMetadata> {
  const { name, logo, image, profileAddress, organizationId, slug } = params;

  const publicProfileUrl = `${appHost}/public/profile/${profileAddress}`;
  const orgUrl = slug ? `${appHost}/o/${slug}` : publicProfileUrl;

  const metadata: LSP3ProfileMetadata = {
    LSP3Profile: {
      name: name || 'Universal Goods Organization',
      description: params.description?.trim() || 'Universal Goods organization profile',
      links: [
        {
          title: 'Universal Goods Organization',
          url: orgUrl,
        },
        // An organisation's public profile never carries a person's email: a `mailto:` link
        // is somebody's inbox, committed by hash to a public chain.
        ...(params.links ?? []).filter((l) => l.title.trim() && l.url.trim() && !isEmailLink(l)),
      ],
      tags: ['universal-goods', 'organization'],
    },
  };
  
  // Add logo or fallback image as avatar/profile image if available
  const primaryImage = logo ?? image ?? null;
  if (primaryImage) {
    const imgUrl = resolveImageUrl(primaryImage, profileAddress, appHost);
    const imageEntry = await createLSP3ImageEntry(imgUrl, primaryImage);
    
    metadata.LSP3Profile.avatar = [imageEntry];
    metadata.LSP3Profile.profileImage = [imageEntry];
  }

  // Add OrganizationId attribute
  if (organizationId) {
    metadata.LSP3Profile.attributes = [
      {
        key: 'OrganizationId',
        value: organizationId,
        type: 'string',
      },
    ];
  }
  
  return metadata;
}
