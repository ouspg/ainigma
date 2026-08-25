import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import * as openstack from "@pulumi/openstack";
import * as pulumi from "@pulumi/pulumi";

import { createDataVolume } from "./data-volume.ts";
import { createNixosImage } from "./image.ts";
import { createDataSecurityGroup } from "./security-groups.ts";

const scope = openstack.identity.getAuthScopeOutput({
  name: "current",
  setTokenId: false,
});
const config = new pulumi.Config();

const infrastructureDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const imagePath = resolve(infrastructureDirectory, "nix/result/ainigma-nixos-csc-pouta.qcow2");

const { image, sha256: imageSha256, sizeBytes: imageSize } = await createNixosImage(imagePath);

const serverName = "ainigma-data";
const keyPairName = "ainigma-main";
const publicNetworkName = config.get("publicNetworkName") ?? "public";
const sshCidr = config.get("sshCidr") ?? "0.0.0.0/0";
const supabaseCidr = config.get("supabaseCidr") ?? "0.0.0.0/0";
const dataVolumeSizeGb = config.requireNumber("dataVolumeSizeGb"); // At least 40GB recommended.
if (!Number.isSafeInteger(dataVolumeSizeGb) || dataVolumeSizeGb < 1) {
  throw new Error("dataVolumeSizeGb must be a positive integer");
}
const expectedSshPublicKey =
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDO/2G0mCCGzuDPWc7CJ2HrgxRXZp9Cm6FSUAI7GH3xVGDfI0GvvkIVXC3jLfW+/uj8dPaDryqRuRojEWdnkzouxceT2WwL3ozKZXo6N4Ofrtad9LuTKgyT2E1tGt7Ri5fRQ2VcsF8t5h4e578+NNlfygjP9XY2JMtu9RcGyf9FDcED7O3Om6Is1Kt5ROLHMyoLGLjM7c+QxUtFr99cYfnkFeMZR5VAGWbaX8GKDFPcd6mEz3LsLBToHhfWH7JFMTXYjc9RRfv7wR/KDxtD2n3XA1hEp8R37rCXxQYbTY+n5XjWwRiUp4y01Mu/Itp1enbHckryWR8JlI2VXVprpNLL";

const privateNetworkName = config.get("networkName");
const privateNetwork = openstack.networking.getNetworkOutput(
  privateNetworkName
    ? { name: privateNetworkName, external: false }
    : { tenantId: scope.projectId, external: false },
);
openstack.networking.getNetworkOutput({ name: publicNetworkName, external: true });

const keyPair = openstack.compute.getKeypairOutput({ name: keyPairName });
const verifiedKeyPairName = keyPair.publicKey.apply((publicKey) => {
  if (sshKeyMaterial(publicKey) !== sshKeyMaterial(expectedSshPublicKey)) {
    throw new Error(`OpenStack key pair ${keyPairName} does not match the expected public key`);
  }
  return keyPairName;
});

const securityGroup = createDataSecurityGroup({ name: serverName, sshCidr, supabaseCidr });

const serverPort = new openstack.networking.Port("ainigma-data", {
  name: serverName,
  description: "Primary port for the Ainigma data host",
  networkId: privateNetwork.id,
  adminStateUp: true,
  securityGroupIds: [securityGroup.id],
  tags: ["ainigma", "data"],
});

const server = new openstack.compute.Instance("ainigma-data", {
  name: serverName,
  flavorName: "standard.large",
  imageId: image.id,
  keyPair: verifiedKeyPairName,
  configDrive: true,
  networks: [{ port: serverPort.id }],
  stopBeforeDestroy: true,
  tags: ["ainigma", "data"],
});

const { attachment: dataVolumeAttachment, volume: dataVolume } = createDataVolume({
  instanceId: server.id,
  sizeGb: dataVolumeSizeGb,
});

const floatingIp = new openstack.networking.FloatingIp("ainigma-data", {
  pool: publicNetworkName,
  portId: serverPort.id,
  description: "Public address for the Ainigma data host",
  tags: ["ainigma", "data"],
});

// Supabase is a headless API/auth backend, IP printed for now, maybe this should be removed later on
export const supabasePublicUrl = pulumi.interpolate`http://${floatingIp.address}:8000`;
export const supabaseAuthUrl = pulumi.interpolate`http://${floatingIp.address}:8000/auth/v1`;

export const project = {
  id: scope.projectId,
  name: scope.projectName,
};

export const user = {
  id: scope.userId,
  name: scope.userName,
};

export const region = scope.region;
export const openstackImage = {
  id: image.id,
  name: image.name,
  sha256: imageSha256,
  glanceChecksum: image.checksum,
  sizeBytes: imageSize,
};
export const dataServer = {
  id: server.id,
  name: server.name,
  fixedIpv4: serverPort.allFixedIps.apply((addresses) => addresses[0]),
  floatingIpv4: floatingIp.address,
  flavor: "standard.large",
  keyPair: keyPair.name,
  keyFingerprint: keyPair.fingerprint,
  network: privateNetwork.name,
  securityGroup: securityGroup.name,
  dataVolume: {
    id: dataVolume.id,
    name: dataVolume.name,
    sizeGb: dataVolume.size,
    device: dataVolumeAttachment.device,
  },
};

function sshKeyMaterial(publicKey: string): string {
  return publicKey.trim().split(/\s+/, 2).join(" ");
}
