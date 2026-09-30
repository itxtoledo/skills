#!/usr/bin/env node
/**
 * Creates an iOS distribution certificate and an App Store provisioning profile
 * through the App Store Connect API, so a release build can be signed locally
 * without a registered physical device.
 *
 * Why this exists: automated credential setup refuses to run non-interactively,
 * and Xcode's automatic signing asks for a development profile first — which
 * requires a device. An IOS_APP_STORE profile does not, so creating it directly
 * sidesteps both.
 *
 * Required environment variables:
 *   ASC_KEY_ID      Key ID of an App Store Connect API key (App Manager or higher)
 *   ASC_ISSUER_ID   Issuer ID from App Store Connect → Users and Access → Integrations
 *   ASC_BUNDLE_ID   Bundle identifier of the app, e.g. com.example.myapp
 *
 * Optional:
 *   ASC_KEY_PATH      Path to the .p8 file
 *                     (default: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8)
 *   ASC_OUT_DIR       Where to write the generated files (default: ./asc-signing)
 *   ASC_PROFILE_NAME  Name for the provisioning profile (default: "<bundle id> App Store")
 *   ASC_CERT_NAME     Subject CN for a newly created certificate (default: the bundle id)
 *
 * Outputs, in ASC_OUT_DIR:
 *   dist.key                 private key (only when a certificate was created)
 *   dist.certSigningRequest  the CSR sent to Apple (only when created)
 *   dist.cer                 the distribution certificate (DER)
 *   profile.mobileprovision  the App Store provisioning profile
 *
 * After running this, follow references/signing-and-upload.md to build the p12,
 * import it into a dedicated keychain, and archive.
 */
import { createSign, generateKeyPairSync } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const KEY_ID = requireEnv("ASC_KEY_ID");
const ISSUER_ID = requireEnv("ASC_ISSUER_ID");
const BUNDLE_ID = requireEnv("ASC_BUNDLE_ID");

const KEY_PATH =
  process.env.ASC_KEY_PATH ??
  join(homedir(), ".appstoreconnect", "private_keys", `AuthKey_${KEY_ID}.p8`);
const OUT = resolve(process.env.ASC_OUT_DIR ?? "./asc-signing");
const PROFILE_NAME = process.env.ASC_PROFILE_NAME ?? `${BUNDLE_ID} App Store`;
const CERT_NAME = process.env.ASC_CERT_NAME ?? BUNDLE_ID;

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`Missing required environment variable: ${name}`);
    console.error("See the header of this file for what each one is.");
    process.exit(1);
  }
  return value;
}

mkdirSync(OUT, { recursive: true });

const b64url = (buf) =>
  Buffer.from(buf).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

let privateKey;
try {
  privateKey = readFileSync(KEY_PATH, "utf8");
} catch {
  console.error(`Could not read the API key at ${KEY_PATH}`);
  console.error("Set ASC_KEY_PATH if it lives somewhere else.");
  process.exit(1);
}

/**
 * App Store Connect rejects tokens older than 20 minutes, so each request signs
 * a fresh one rather than caching.
 */
function jwt() {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const payload = { iss: ISSUER_ID, iat: now, exp: now + 900, aud: "appstoreconnect-v1" };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const signature = createSign("SHA256")
    .update(signingInput)
    .sign({ key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${b64url(signature)}`;
}

async function api(path, init = {}) {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${jwt()}`,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = text;
  }
  if (!res.ok) {
    const hint =
      res.status === 403
        ? " (the API key's role may be too low — it needs App Manager or higher)"
        : "";
    throw new Error(
      `${init.method || "GET"} ${path} -> ${res.status}${hint}: ${JSON.stringify(body).slice(0, 400)}`
    );
  }
  return body;
}

// 1. Resolve the bundle id resource. The profile has to point at it.
const bundle = await api(`/v1/bundleIds?filter[identifier]=${encodeURIComponent(BUNDLE_ID)}&limit=1`);
const bundleResourceId = bundle?.data?.[0]?.id;
if (!bundleResourceId) {
  throw new Error(
    `Bundle id ${BUNDLE_ID} not found on this team. Create the app record and its bundle id in App Store Connect first.`
  );
}
console.log(`bundle id resource: ${bundleResourceId}`);

// 2. Reuse a valid distribution certificate, or create one.
let certificateId = null;
const existing = await api("/v1/certificates?filter[certificateType]=IOS_DISTRIBUTION&limit=50");
const valid = (existing?.data ?? []).find(
  (cert) => !cert.attributes?.expirationDate || new Date(cert.attributes.expirationDate) > new Date()
);

if (valid) {
  console.log(`reusing distribution certificate: ${valid.id} (${valid.attributes?.name})`);
  console.log(
    "note: reusing a certificate only works if its private key is on this machine.\n" +
      "      If the archive later fails with 'No signing certificate found', delete the\n" +
      "      certificate in App Store Connect and run this again to create a new one."
  );
} else {
  const { privateKey: generatedKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const keyPath = join(OUT, "dist.key");
  writeFileSync(keyPath, generatedKey.export({ type: "pkcs8", format: "pem" }).toString());

  const csrPath = join(OUT, "dist.certSigningRequest");
  const csr = execFileSync("openssl", [
    "req", "-new", "-key", keyPath,
    "-subj", `/CN=${CERT_NAME}/C=US`,
  ]).toString();
  writeFileSync(csrPath, csr);

  const created = await api("/v1/certificates", {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "certificates",
        attributes: { certificateType: "IOS_DISTRIBUTION", csrContent: csr },
      },
    }),
  });
  certificateId = created.data.id;
  writeFileSync(join(OUT, "dist.cer"), Buffer.from(created.data.attributes.certificateContent, "base64"));
  console.log(`created distribution certificate: ${certificateId} (${created.data.attributes.name})`);
}

// 3. Reuse the profile if it already exists, otherwise create it.
const profiles = await api(`/v1/profiles?filter[name]=${encodeURIComponent(PROFILE_NAME)}&limit=10`);
let profile = (profiles?.data ?? [])[0];

if (profile) {
  console.log(`reusing provisioning profile: ${profile.id} (${profile.attributes.name})`);
} else {
  if (!certificateId) {
    // Reusing a certificate we do not hold the key for would produce a profile
    // that cannot sign anything on this machine.
    throw new Error(
      "A distribution certificate exists but this run did not create it, so there is no\n" +
        "private key here to build the profile from. Either revoke that certificate in App\n" +
        "Store Connect and run again, or set ASC_CERT_NAME and create a new one explicitly."
    );
  }
  const created = await api("/v1/profiles", {
    method: "POST",
    body: JSON.stringify({
      data: {
        type: "profiles",
        attributes: { name: PROFILE_NAME, profileType: "IOS_APP_STORE" },
        relationships: {
          bundleId: { data: { type: "bundleIds", id: bundleResourceId } },
          certificates: { data: [{ type: "certificates", id: certificateId }] },
        },
      },
    }),
  });
  profile = created.data;
  console.log(`created provisioning profile: ${profile.id} (${profile.attributes.name})`);
}

writeFileSync(
  join(OUT, "profile.mobileprovision"),
  Buffer.from(profile.attributes.profileContent, "base64")
);

console.log("");
console.log(`files written to ${OUT}`);
console.log(`PROFILE_NAME=${profile.attributes.name}`);
console.log(`PROFILE_UUID=${profile.attributes.uuid}`);
console.log("");
console.log("Next: build the p12, import it into a dedicated keychain, and archive.");
console.log("See references/signing-and-upload.md.");
