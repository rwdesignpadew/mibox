import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';

const keyPath = process.env.ASC_KEY_PATH;
const keyId = process.env.ASC_KEY_ID;
const issuerId = process.env.ASC_ISSUER_ID;
const certificateFingerprint = (process.env.CERTIFICATE_SHA1 || '').replaceAll(':', '').toUpperCase();

if (!keyPath || !keyId || !issuerId || !certificateFingerprint) {
  throw new Error('Missing App Store Connect credentials or certificate fingerprint');
}

const encode = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${encode(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))}.${encode(JSON.stringify({ iss: issuerId, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }))}`;
const signature = crypto.sign('sha256', Buffer.from(unsigned), {
  key: fs.readFileSync(keyPath),
  dsaEncoding: 'ieee-p1363',
}).toString('base64url');
const authorization = `Bearer ${unsigned}.${signature}`;

async function request(resourcePath, options = {}) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${resourcePath}`, {
    ...options,
    headers: {
      Authorization: authorization,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${response.status} ${resourcePath}: ${JSON.stringify(body)}`);
  return body;
}

async function findBundleId(identifier) {
  const query = encodeURIComponent(identifier);
  const result = await request(`/v1/bundleIds?filter%5Bidentifier%5D=${query}&limit=10`);
  const item = result.data.find((entry) => entry.attributes.identifier === identifier);
  if (!item) throw new Error(`Bundle ID not found: ${identifier}`);
  return item.id;
}

async function findCertificate() {
  const result = await request('/v1/certificates?filter%5BcertificateType%5D=DISTRIBUTION&limit=100');
  const item = result.data.find((entry) => {
    const certificate = new crypto.X509Certificate(Buffer.from(entry.attributes.certificateContent, 'base64'));
    return certificate.fingerprint.replaceAll(':', '').toUpperCase() === certificateFingerprint;
  });
  if (!item) throw new Error(`Distribution certificate ${certificateFingerprint} not found in Apple Developer`);
  return item.id;
}

async function getOrCreateProfile(name, bundleId, certificateId) {
  const profiles = await request('/v1/profiles?limit=200');
  let profile = profiles.data.find((entry) =>
    entry.attributes.name === name &&
    entry.attributes.profileState === 'ACTIVE' &&
    new Date(entry.attributes.expirationDate) > new Date()
  );

  if (!profile) {
    const result = await request('/v1/profiles', {
      method: 'POST',
      body: JSON.stringify({
        data: {
          type: 'profiles',
          attributes: { name, profileType: 'IOS_APP_STORE' },
          relationships: {
            bundleId: { data: { type: 'bundleIds', id: bundleId } },
            certificates: { data: [{ type: 'certificates', id: certificateId }] },
          },
        },
      }),
    });
    profile = result.data;
    console.log(`Created provisioning profile: ${name}`);
  } else {
    console.log(`Using existing provisioning profile: ${name}`);
  }

  const directory = path.join(os.homedir(), 'Library', 'MobileDevice', 'Provisioning Profiles');
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, `${profile.id}.mobileprovision`), Buffer.from(profile.attributes.profileContent, 'base64'));
}

const certificateId = await findCertificate();
const mainBundleId = await findBundleId('pl.miboxscreen.ios');
const extensionBundleId = await findBundleId('pl.miboxscreen.ios.broadcast');

await getOrCreateProfile('MiBox Screen App Store', mainBundleId, certificateId);
await getOrCreateProfile('MiBox Screen Broadcast App Store', extensionBundleId, certificateId);
