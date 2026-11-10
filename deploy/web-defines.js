// Turns `firebase apps:sdkconfig WEB <appId> --json` (stdin) into the Flutter
// --dart-define arguments of the production web build (stdout, one per line).
// Fails loudly when a value is missing, so a broken build never ships.
const chunks = [];
process.stdin.on('data', (chunk) => chunks.push(chunk));
process.stdin.on('end', () => {
  const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  const config = parsed.result?.sdkConfig ?? parsed.result;
  const defines = {
    FIREBASE_PROJECT_ID: config?.projectId,
    FIREBASE_API_KEY: config?.apiKey,
    FIREBASE_APP_ID: config?.appId,
    FIREBASE_MESSAGING_SENDER_ID: config?.messagingSenderId,
    FIREBASE_STORAGE_BUCKET: config?.storageBucket,
    FIREBASE_AUTH_DOMAIN: config?.authDomain,
  };
  for (const [name, value] of Object.entries(defines)) {
    if (typeof value !== 'string' || value === '') {
      console.error(`web app config has no ${name}`);
      process.exit(1);
    }
    console.log(`--dart-define=${name}=${value}`);
  }
});
