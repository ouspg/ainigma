# Supported openstack extensions in CSC

```bash
openstack extension list --network --long
+--------------------------------+--------------------------------+--------------------------------+-----------+---------------------------+-------+
| Name                           | Alias                          | Description                    | Namespace | Updated At                | Links |
+--------------------------------+--------------------------------+--------------------------------+-----------+---------------------------+-------+
| Address group                  | address-group                  | Support address group          |           | 2020-07-15T10:00:00-00:00 | []    |
| Address scope                  | address-scope                  | Address scopes extension.      |           | 2015-07-26T10:00:00-00:00 | []    |
| Enforce Router's Admin State   | router-admin-state-down-       | Ensure that the admin state of |           | 2019-07-02T15:56:00       | []    |
| Down Before Update Extension   | before-update                  | a router is DOWN               |           |                           |       |
|                                |                                | (admin_state_up=False) before  |           |                           |       |
|                                |                                | updating the distributed       |           |                           |       |
|                                |                                | attribute                      |           |                           |       |
| agent                          | agent                          | The agent management           |           | 2013-02-03T10:00:00-00:00 | []    |
|                                |                                | extension.                     |           |                           |       |
| Agent's Resource View Synced   | agent-resources-synced         | Stores success/failure of last |           | 2018-12-19T00:00:00-00:00 | []    |
| to Placement                   |                                | sync to Placement              |           |                           |       |
| Allowed Address Pairs          | allowed-address-pairs          | Provides allowed address pairs |           | 2013-07-23T10:00:00-00:00 | []    |
| Auto Allocated Topology        | auto-allocated-topology        | Auto Allocated Topology        |           | 2016-01-01T00:00:00-00:00 | []    |
| Services                       |                                | Services.                      |           |                           |       |
| Availability Zone              | availability_zone              | The availability zone          |           | 2015-01-01T10:00:00-00:00 | []    |
|                                |                                | extension.                     |           |                           |       |
| Availability Zone Filter       | availability_zone_filter       | Add filter parameters to       |           | 2018-06-22T10:00:00-00:00 | []    |
| Extension                      |                                | AvailabilityZone resource      |           |                           |       |
| Default Subnetpools            | default-subnetpools            | Provides ability to mark and   |           | 2016-02-18T18:00:00-00:00 | []    |
|                                |                                | use a subnetpool as the        |           |                           |       |
|                                |                                | default.                       |           |                           |       |
| DHCP Agent Scheduler           | dhcp_agent_scheduler           | Schedule networks among dhcp   |           | 2013-02-07T10:00:00-00:00 | []    |
|                                |                                | agents                         |           |                           |       |
| Distributed Virtual Router     | dvr                            | Enables configuration of       |           | 2014-06-1T10:00:00-00:00  | []    |
|                                |                                | Distributed Virtual Routers.   |           |                           |       |
| Empty String Filtering         | empty-string-filtering         | Allow filtering by attributes  |           | 2018-05-01T10:00:00-00:00 | []    |
| Extension                      |                                | with empty string value        |           |                           |       |
| Neutron external network       | external-net                   | Adds external network          |           | 2013-01-14T10:00:00-00:00 | []    |
|                                |                                | attribute to network resource. |           |                           |       |
| Neutron Extra DHCP options     | extra_dhcp_opt                 | Extra options configuration    |           | 2013-03-17T12:00:00-00:00 | []    |
|                                |                                | for DHCP. For example PXE boot |           |                           |       |
|                                |                                | options to DHCP clients can be |           |                           |       |
|                                |                                | specified (e.g. tftp-server,   |           |                           |       |
|                                |                                | server-ip-address, bootfile-   |           |                           |       |
|                                |                                | name)                          |           |                           |       |
| Neutron Extra Route            | extraroute                     | Extra routes configuration for |           | 2013-02-01T10:00:00-00:00 | []    |
|                                |                                | L3 router                      |           |                           |       |
| Atomically add/remove extra    | extraroute-atomic              | Edit extra routes of a router  |           | 2019-07-10T00:00:00+00:00 | []    |
| routes                         |                                | on server side by atomically   |           |                           |       |
|                                |                                | adding/removing extra routes   |           |                           |       |
| Filter parameters validation   | filter-validation              | Provides validation on filter  |           | 2018-07-04T10:00:00-00:00 | []    |
|                                |                                | parameters.                    |           |                           |       |
| Floating IP Port Details       | fip-port-details               | Add port_details attribute to  |           | 2018-04-09T10:00:00-00:00 | []    |
| Extension                      |                                | Floating IP resource           |           |                           |       |
| Neutron Service Flavors        | flavors                        | Flavor specification for       |           | 2015-09-17T10:00:00-00:00 | []    |
|                                |                                | Neutron advanced services.     |           |                           |       |
| Floating IP Pools Extension    | floatingip-pools               | Provides a floating IP pools   |           | 2018-03-21T10:00:00-00:00 | []    |
|                                |                                | API.                           |           |                           |       |
| IP address substring filtering | ip-substring-filtering         | Provides IP address substring  |           | 2017-11-28T09:00:00-00:00 | []    |
|                                |                                | filtering when listing ports   |           |                           |       |
| Neutron L3 Router              | router                         | Router abstraction for basic   |           | 2012-07-20T10:00:00-00:00 | []    |
|                                |                                | L3 forwarding between L2       |           |                           |       |
|                                |                                | Neutron networks and access to |           |                           |       |
|                                |                                | external networks via a NAT    |           |                           |       |
|                                |                                | gateway.                       |           |                           |       |
| Neutron L3 Configurable        | ext-gw-mode                    | Extension of the router        |           | 2013-03-28T10:00:00-00:00 | []    |
| external gateway mode          |                                | abstraction for specifying     |           |                           |       |
|                                |                                | whether SNAT should occur on   |           |                           |       |
|                                |                                | the external gateway           |           |                           |       |
| HA Router extension            | l3-ha                          | Adds HA capability to routers. |           | 2014-04-26T00:00:00-00:00 | []    |
| Router Flavor Extension        | l3-flavors                     | Flavor support for routers.    |           | 2016-05-17T00:00:00-00:00 | []    |
| Prevent L3 router ports IP     | l3-port-ip-change-not-allowed  | Prevent change of IP address   |           | 2018-10-09T10:00:00-00:00 | []    |
| address change extension       |                                | for some L3 router ports       |           |                           |       |
| L3 Agent Scheduler             | l3_agent_scheduler             | Schedule routers among l3      |           | 2013-02-07T10:00:00-00:00 | []    |
|                                |                                | agents                         |           |                           |       |
| Multi Provider Network         | multi-provider                 | Expose mapping of virtual      |           | 2013-06-27T10:00:00-00:00 | []    |
|                                |                                | networks to multiple physical  |           |                           |       |
|                                |                                | networks                       |           |                           |       |
| Network MTU                    | net-mtu                        | Provides MTU attribute for a   |           | 2015-03-25T10:00:00-00:00 | []    |
|                                |                                | network resource.              |           |                           |       |
| Network MTU (writable)         | net-mtu-writable               | Provides a writable MTU        |           | 2017-07-12T00:00:00-00:00 | []    |
|                                |                                | attribute for a network        |           |                           |       |
|                                |                                | resource.                      |           |                           |       |
| Network Availability Zone      | network_availability_zone      | Availability zone support for  |           | 2015-01-01T10:00:00-00:00 | []    |
|                                |                                | network.                       |           |                           |       |
| Network IP Availability        | network-ip-availability        | Provides IP availability data  |           | 2015-09-24T00:00:00-00:00 | []    |
|                                |                                | for each network and subnet.   |           |                           |       |
| Pagination support             | pagination                     | Extension that indicates that  |           | 2016-06-12T00:00:00-00:00 | []    |
|                                |                                | pagination is enabled.         |           |                           |       |
| Port device profile            | port-device-profile            | Expose the port device profile |           | 2020-12-17T10:00:00-00:00 | []    |
|                                |                                | (Cyborg)                       |           |                           |       |
| Neutron Port MAC address       | port-mac-address-regenerate    | Network port MAC address       |           | 2018-05-03T10:00:00-00:00 | []    |
| regenerate                     |                                | regenerate                     |           |                           |       |
| Port NUMA affinity policy      | port-numa-affinity-policy      | Expose the port NUMA affinity  |           | 2020-07-08T10:00:00-00:00 | []    |
|                                |                                | policy                         |           |                           |       |
| Port Binding                   | binding                        | Expose port bindings of a      |           | 2014-02-03T10:00:00-00:00 | []    |
|                                |                                | virtual port to external       |           |                           |       |
|                                |                                | application                    |           |                           |       |
| Port Bindings Extended         | binding-extended               | Expose port bindings of a      |           | 2017-07-17T10:00:00-00:00 | []    |
|                                |                                | virtual port to external       |           |                           |       |
|                                |                                | application                    |           |                           |       |
| project_id field enabled       | project-id                     | Extension that indicates that  |           | 2016-09-09T09:09:09-09:09 | []    |
|                                |                                | project_id field is enabled.   |           |                           |       |
| Provider Network               | provider                       | Expose mapping of virtual      |           | 2012-09-07T10:00:00-00:00 | []    |
|                                |                                | networks to physical networks  |           |                           |       |
| Quota engine limit check       | quota-check-limit              | Support for checking the       |           | 2021-09-08T16:00:00-00:00 | []    |
|                                |                                | resource usage before applying |           |                           |       |
|                                |                                | a new quota limit              |           |                           |       |
| Quota management support       | quotas                         | Expose functions for quotas    |           | 2012-07-29T10:00:00-00:00 | []    |
|                                |                                | management per project         |           |                           |       |
| Quota details management       | quota_details                  | Expose functions for quotas    |           | 2017-02-10T10:00:00-00:00 | []    |
| support                        |                                | usage statistics per project   |           |                           |       |
| RBAC Policies                  | rbac-policies                  | Allows creation and            |           | 2015-06-17T12:15:12-00:00 | []    |
|                                |                                | modification of policies that  |           |                           |       |
|                                |                                | control tenant access to       |           |                           |       |
|                                |                                | resources.                     |           |                           |       |
| Add address_group type to RBAC | rbac-address-group             | Add address_group type to      |           | 2021-01-20T00:00:00-00:00 | []    |
|                                |                                | network RBAC                   |           |                           |       |
| Add address_scope type to RBAC | rbac-address-scope             | Add address_scope type to RBAC |           | 2020-02-12T00:00:00-00:00 | []    |
| Add security_group type to     | rbac-security-groups           | Add security_group type to     |           | 2019-02-14T00:00:00-00:00 | []    |
| network RBAC                   |                                | network RBAC                   |           |                           |       |
| Add subnetpool type to RBAC    | rbac-subnetpool                | Add subnetpool type to RBAC    |           | 2020-02-05T00:00:00-00:00 | []    |
| If-Match constraints based on  | revision-if-match              | Extension indicating that If-  |           | 2016-12-11T00:00:00-00:00 | []    |
| revision_number                |                                | Match based on revision_number |           |                           |       |
|                                |                                | is supported.                  |           |                           |       |
| Resource revision numbers      | standard-attr-revisions        | This extension will display    |           | 2016-04-11T10:00:00-00:00 | []    |
|                                |                                | the revision number of neutron |           |                           |       |
|                                |                                | resources.                     |           |                           |       |
| Router Availability Zone       | router_availability_zone       | Availability zone support for  |           | 2015-01-01T10:00:00-00:00 | []    |
|                                |                                | router.                        |           |                           |       |
| Normalized CIDR field for      | security-groups-normalized-    | Add new field with normalized  |           | 2020-07-28T10:00:00-00:00 | []    |
| security group rules           | cidr                           | remote_ip_prefix cidr in SG    |           |                           |       |
|                                |                                | rule                           |           |                           |       |
| Port filtering on security     | port-security-groups-filtering | Provides security groups       |           | 2018-01-09T09:00:00-00:00 | []    |
| groups                         |                                | filtering when listing ports   |           |                           |       |
| Remote address group id field  | security-groups-remote-        | Add new field of remote        |           | 2020-08-25T10:00:00-00:00 | []    |
| for security group rules       | address-group                  | address group id in SG rules   |           |                           |       |
| Security group filtering on    | security-groups-shared-        | Support filtering security     |           | 2021-10-05T09:00:00-00:00 | []    |
| the shared field               | filtering                      | groups on the shared field     |           |                           |       |
| security-group                 | security-group                 | The security groups extension. |           | 2012-10-05T10:00:00-00:00 | []    |
| Neutron Service Type           | service-type                   | API for retrieving service     |           | 2013-01-20T00:00:00-00:00 | []    |
| Management                     |                                | providers for Neutron advanced |           |                           |       |
|                                |                                | services                       |           |                           |       |
| Sorting support                | sorting                        | Extension that indicates that  |           | 2016-06-12T00:00:00-00:00 | []    |
|                                |                                | sorting is enabled.            |           |                           |       |
| standard-attr-description      | standard-attr-description      | Extension to add descriptions  |           | 2016-02-10T10:00:00-00:00 | []    |
|                                |                                | to standard attributes         |           |                           |       |
| Stateful security group        | stateful-security-group        | Indicates if the security      |           | 2019-11-26T09:00:00-00:00 | []    |
|                                |                                | group is stateful or not       |           |                           |       |
| Subnet Onboard                 | subnet_onboard                 | Provides support for           |           | 2018-12-18T09:00:00-00:00 | []    |
|                                |                                | onboarding subnets into subnet |           |                           |       |
|                                |                                | pools                          |           |                           |       |
| Subnet service types           | subnet-service-types           | Provides ability to set the    |           | 2016-03-15T18:00:00-00:00 | []    |
|                                |                                | subnet service_types field     |           |                           |       |
| Subnet Allocation              | subnet_allocation              | Enables allocation of subnets  |           | 2015-03-30T10:00:00-00:00 | []    |
|                                |                                | from a subnet pool             |           |                           |       |
| Subnet Pool Prefix Operations  | subnetpool-prefix-ops          | Provides support for adjusting |           | 2019-02-08T10:00:00-00:00 | []    |
|                                |                                | the prefix list of subnet      |           |                           |       |
|                                |                                | pools                          |           |                           |       |
| Tag support for resources with | standard-attr-tag              | Enables to set tag on          |           | 2017-01-01T00:00:00-00:00 | []    |
| standard attribute: port,      |                                | resources with standard        |           |                           |       |
| subnet, subnetpool, network,   |                                | attribute.                     |           |                           |       |
| security_group, router,        |                                |                                |           |                           |       |
| floatingip, policy, trunk,     |                                |                                |           |                           |       |
| network_segment_range          |                                |                                |           |                           |       |
| Resource timestamps            | standard-attr-timestamp        | Adds created_at and updated_at |           | 2016-09-12T10:00:00-00:00 | []    |
|                                |                                | fields to all Neutron          |           |                           |       |
|                                |                                | resources that have Neutron    |           |                           |       |
|                                |                                | standard attributes.           |           |                           |       |
+--------------------------------+--------------------------------+--------------------------------+-----------+---------------------------+-------+
```
