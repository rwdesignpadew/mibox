import fs from 'node:fs';
import crypto from 'node:crypto';

const screenshotPath = process.argv[2];
const iapId = process.env.IAP_ID;
const keyPath = process.env.ASC_KEY_PATH;
const keyId = process.env.ASC_KEY_ID;
const issuerId = process.env.ASC_ISSUER_ID;

if (!screenshotPath || !iapId || !keyPath || !keyId || !issuerId) {
  throw new Error('Missing screenshot path, IAP ID, or App Store Connect credentials');
}

const encode = (value) => Buffer.from(value).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const unsigned = `${encode(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))}.${encode(JSON.stringify({ iss: issuerId, iat: now, exp: now + 900, aud: 'appstoreconnect-v1' }))}`;
const signature = crypto.sign('sha256', Buffer.from(unsigned), {
  key: fs.readFileSync(keyPath),
  dsaEncoding: 'ieee-p1363',
}).toString('base64url');
const authorization = `Bearer ${unsigned}.${signature}`;

async function api(resourcePath, options = {}) {
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

const image = fs.readFileSync(screenshotPath);
const fileName = 'mibox-screen-pro-review.png';
const reservation = await api('/v1/inAppPurchaseAppStoreReviewScreenshots', {
  method: 'POST',
  body: JSON.stringify({
    data: {
      type: 'inAppPurchaseAppStoreReviewScreenshots',
      attributes: { fileName, fileSize: image.length },
      relationships: {
        inAppPurchaseV2: { data: { type: 'inAppPurchases', id: iapId } },
      },
    },
  }),
});

const screenshot = reservation.data;
for (const operation of screenshot.attributes.uploadOperations) {
  const headers = Object.fromEntries(operation.requestHeaders.map(({ name, value }) => [name, value]));
  const part = image.subarray(operation.offset, operation.offset + operation.length);
  const response = await fetch(operation.url, { method: operation.method, headers, body: part });
  if (!response.ok) throw new Error(`Asset upload failed: ${response.status} ${await response.text()}`);
}

const checksum = crypto.createHash('md5').update(image).digest('hex');
await api(`/v1/inAppPurchaseAppStoreReviewScreenshots/${screenshot.id}`, {
  method: 'PATCH',
  body: JSON.stringify({
    data: {
      type: 'inAppPurchaseAppStoreReviewScreenshots',
      id: screenshot.id,
      attributes: { uploaded: true, sourceFileChecksum: checksum },
    },
  }),
});

await api(`/v2/inAppPurchases/${iapId}`, {
  method: 'PATCH',
  body: JSON.stringify({
    data: {
      type: 'inAppPurchases',
      id: iapId,
      attributes: {
        reviewNote: 'Jednorazowy zakup MiBox Screen Pro usuwa reklamy wyświetlane na telewizorze podczas udostępniania ekranu. Zakup można przywrócić przyciskiem „Przywróć zakup”.',
      },
    },
  }),
});

console.log(`Uploaded App Review screenshot ${screenshot.id} for IAP ${iapId}`);
