import { createHash } from "node:crypto";
import { createReadStream, statSync } from "node:fs";

import * as openstack from "@pulumi/openstack";

export async function createNixosImage(imagePath: string) {
  const sizeBytes = statSync(imagePath).size;
  const digests = await hashFile(imagePath);
  const name = `ainigma-nixos-csc-pouta-${digests.sha256.slice(0, 12)}`;

  const image = new openstack.images.Image(
    "ainigma-nixos-csc-pouta",
    {
      name,
      containerFormat: "bare",
      diskFormat: "qcow2",
      localFilePath: imagePath,
      visibility: "private",
      verifyChecksum: true,
      properties: {
        ainigma_sha256: digests.sha256,
        ainigma_md5: digests.md5,
      },
      tags: ["ainigma", "nixos"],
    },
    {
      deleteBeforeReplace: false,
      replaceOnChanges: ["name"],
      customTimeouts: { create: "60m" },
    },
  );

  return { image, sha256: digests.sha256, sizeBytes };
}

async function hashFile(filePath: string): Promise<{ md5: string; sha256: string }> {
  const md5 = createHash("md5");
  const sha256 = createHash("sha256");

  for await (const chunk of createReadStream(filePath)) {
    md5.update(chunk);
    sha256.update(chunk);
  }

  return {
    md5: md5.digest("hex"),
    sha256: sha256.digest("hex"),
  };
}
