import * as openstack from "@pulumi/openstack";

interface DataSecurityGroupArgs {
  name: string;
  sshCidr: string;
  supabaseCidr: string;
}

export function createDataSecurityGroup(args: DataSecurityGroupArgs) {
  const securityGroup = new openstack.networking.SecGroup("ainigma-data", {
    name: args.name,
    description: "Ingress for the Ainigma data host",
    deleteDefaultRules: false,
    tags: ["ainigma", "data"],
  });

  new openstack.networking.SecGroupRule("ainigma-data-ssh-ipv4", {
    securityGroupId: securityGroup.id,
    direction: "ingress",
    ethertype: "IPv4",
    protocol: "tcp",
    portRangeMin: 22,
    portRangeMax: 22,
    remoteIpPrefix: args.sshCidr,
    description: "SSH administration",
  });

  const publicTcpRules = [
    {
      resourceName: "ainigma-data-https-ipv4",
      port: 443,
      cidr: "0.0.0.0/0",
      description: "HTTPS",
    },
    {
      resourceName: "ainigma-data-supabase-api-ipv4",
      port: 8000,
      cidr: args.supabaseCidr,
      description: "Supabase API gateway",
    },
    {
      resourceName: "ainigma-data-supabase-session-ipv4",
      port: 5432,
      cidr: args.supabaseCidr,
      description: "Supabase session pooler",
    },
    {
      resourceName: "ainigma-data-supabase-transaction-ipv4",
      port: 6543,
      cidr: args.supabaseCidr,
      description: "Supabase transaction pooler",
    },
  ];

  for (const rule of publicTcpRules) {
    new openstack.networking.SecGroupRule(rule.resourceName, {
      securityGroupId: securityGroup.id,
      direction: "ingress",
      ethertype: "IPv4",
      protocol: "tcp",
      portRangeMin: rule.port,
      portRangeMax: rule.port,
      remoteIpPrefix: rule.cidr,
      description: rule.description,
    });
  }

  return securityGroup;
}
