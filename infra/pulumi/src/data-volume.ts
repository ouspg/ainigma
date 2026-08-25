import * as openstack from "@pulumi/openstack";
import * as pulumi from "@pulumi/pulumi";

interface DataVolumeArgs {
  instanceId: pulumi.Input<string>;
  sizeGb: number;
}

export function createDataVolume(args: DataVolumeArgs) {
  const volume = new openstack.blockstorage.Volume(
    "ainigma-data",
    {
      name: "ainigma-data",
      description: "Persistent Ainigma and Supabase data",
      size: args.sizeGb,
      metadata: {
        application: "ainigma",
        purpose: "data",
      },
    },
    {
      protect: true,
      retainOnDelete: true,
    },
  );

  const attachment = new openstack.compute.VolumeAttach("ainigma-data", {
    instanceId: args.instanceId,
    volumeId: volume.id,
    device: "/dev/vdb",
  });

  return { attachment, volume };
}
