# 1. Set up an organisation

**In the console:** create an account, then a six-step setup: your name, your workspace, a passkey on this device, optionally a passkey on your phone, colleagues for recovery, and a summary.

**Underneath:** the organisation gets a Universal Profile. Your browser key and your passkeys become controllers of it through its LSP6 Key Manager, each passkey through its own signer proxy. Colleagues you invite can later be set up as LSP11 guardians. See [Identities, keys and recovery](/overview/identities).

## Create an account

Sign up at [app.universalgoods.xyz/signup](https://app.universalgoods.xyz/signup) with an email address and password, or continue with Google.

<figure>
  <img src="/screenshots/v3/organisation/create-account.png" alt="The Create account page with empty Email, Password and Confirm password fields, a Create account button, a Continue with Google option and a Sign in link." />
  <figcaption>Create account. Testnet.</figcaption>
</figure>

This sign-in is for the hosted console only. It is not a key and has no authority on chain.

## Your name

<figure>
  <img src="/screenshots/v3/organisation/step-your-name.png" alt="The What should we call you? step with the name Alex Demo entered and a Continue button. The left rail lists the six setup steps, with Your name as step 1. The sign-up email is blurred." />
  <figcaption>Step 1, your name. The left rail shows all six steps. The sign-up email is blurred.</figcaption>
</figure>

## Your workspace

The workspace is your organisation. Give it a name, choose whether its profile is public, confirm you can act for the organisation, and choose a passphrase.

<figure>
  <img src="/screenshots/v3/organisation/step-workspace.png" alt="The Name your workspace step: a Workspace name field, optional Customise branding and Description and links sections, a switch reading Your organisation will be public, a checkbox reading I can act for this organisation, and two passphrase fields." />
  <figcaption>Step 2, your workspace, before anything is entered. Testnet.</figcaption>
</figure>

**What setup does on chain.** During setup the organisation's Universal Profile is created, with LSP3 metadata built from what you enter here (name, description, links, logo). A browser key is created in this browser and becomes a controller of the profile. The passphrase encrypts that key in the browser. The platform never sees the passphrase or the key, and cannot reset either.

:::danger The passphrase cannot be reset
If you forget it, the browser key cannot be unlocked. Your passkeys and colleague recovery are then the only ways back in.
:::

## This device

<figure>
  <img src="/screenshots/v3/organisation/step-this-device.png" alt="The Add this device's key step. A This device card for Touch ID, Windows Hello or your device PIN reads Added, with an Add another button, and Continue below it." />
  <figcaption>Step 3, a passkey on this computer, after it was added. Testnet.</figcaption>
</figure>

Your device asks twice: once to create the passkey and once to prove you hold it. **Underneath:** the credential is registered with `WebAuthnController`, its own signer proxy is deployed at the address derived from `(profile, credentialId)`, and the proxy is granted permissions on the profile. The passkey has to sign its own enrolment, so a key that cannot sign can never be enrolled.

## Your phone

<figure>
  <img src="/screenshots/v3/organisation/step-your-phone.png" alt="The Add a key from your phone step. A Your phone card says to scan a code with your camera and touch the sensor there, and that it needs Bluetooth on both devices. It has an Add button, and Continue is active." />
  <figcaption>Step 4, an optional second passkey on your phone. Testnet.</figcaption>
</figure>

A second passkey on another device is a second, independent controller, with its own proxy and its own permissions.

## Colleagues

<figure>
  <img src="/screenshots/v3/organisation/step-colleagues.png" alt="The Add trusted colleagues step. A notice reads: You have not added anyone yet. Without 2 colleagues, losing your devices means losing the account. Below are an email field, Invite a colleague, Send invitations and Skip for now." />
  <figcaption>Step 5, colleagues, before anyone is invited. Testnet.</figcaption>
</figure>

Recovery needs two colleagues who have accepted. **Underneath:** this is LSP11 social recovery, 2 of 3 by default with a 48 hour delay from the first vote, and the LSP11 contract receives only `ADDCONTROLLER` on your profile. LSP11 is deployed on testnet and not yet on mainnet.

## Your setup

<figure>
  <img src="/screenshots/v3/organisation/step-your-setup.png" alt="The Ready for your next step review. A warning reads Recovery is not set up yet. Tiles show 2 keys hold this account, 0 colleagues invited and 1 permission granted. Platform permissions lists Act on your behalf, with a Revoke button. A Go to my workspace button is at the bottom." />
  <figcaption>Step 6, the summary, for an account with no phone passkey and no colleagues yet. Testnet.</figcaption>
</figure>

The summary counts the keys that control the profile (here the passkey and the browser key), the colleagues invited, and any permission granted to the hosted platform. **Act on your behalf** is an LSP6 permission on your profile that lets the platform fill in and publish passport data for you. It cannot add or remove keys, change permissions or move value, and **Revoke** removes it.

## Check before moving on

- The organisation appears in the organisation switcher.
- You have a second way in: a second passkey, or two colleagues who have accepted.
