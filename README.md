# Foundry Private Networking — BYO VNet (Delegated Subnet) flavor

End-to-end private-networking reference for **Azure AI Foundry Agents** using the **BYO VNet** pattern: agent compute (Data Proxy + Hosted/Prompt agent Micro VMs) is injected into a delegated subnet in **your** virtual network. BYO Cosmos + Storage + AI Search are wired to the agent runtime via a project `capabilityHost`, with `publicNetworkAccess: Disabled` on every data resource and **zero public network exposure**.

> **Two flavors of private Foundry — pick the one you need:**
>
> | Flavor | Repo | When to use |
> |---|---|---|
> | **Managed VNet** | [foundry-private-managed-vnet](https://github.com/SridharArrabelly/foundry-private-managed-vnet) | Default. Agent compute runs in a Microsoft-managed VNet you don't see. Simpler — no subnet-IP planning. |
> | **BYO VNet (delegated subnet)** *(this repo)* | [foundry-private-byo-vnet](https://github.com/SridharArrabelly/foundry-private-byo-vnet) | For highly regulated workloads (banks/gov/health) that require agent compute IPs to live in the customer's own VNet. Hosted + Prompt agent types via a Data Proxy. |
>
> See the [decision hub](https://github.com/SridharArrabelly/foundry-private-networking-samples) for a side-by-side comparison and "which one should I use?" walkthrough.

> ⚠️ **Status: documentation-derived baseline.** This template implements the BYO-VNet pattern strictly from the [Foundry Agent Service docs](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks) and the [networking deep-dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive). The data layer (BYO Cosmos/Storage/Search + capabilityHost + RBAC + DNS) is identical to and reuses the validated modules from the [Managed VNet flavor](https://github.com/SridharArrabelly/foundry-private-managed-vnet). The **network injection layer** (delegated subnet + `networkInjections.useMicrosoftManagedNetwork: false`) is new and awaits first-deploy validation. PRs welcome from anyone who runs `azd up` and refines.

## What this repo does (at a glance)

- Deploys an Azure AI Foundry account with **agent compute injected into your delegated subnet** (`Microsoft.App/environments` delegation) — every agent IP lives in your VNet, visible in your NSG/Firewall logs.
- BYO Cosmos (thread state) + Storage (file/agent dirs) + AI Search (vector store), each behind its own private endpoint in your VNet.
- Project `capabilityHost` binds the three connections to the agent runtime — same as in the Managed VNet flavor.
- Two-phase RBAC chain (pre-caphost + post-caphost) — same as in the Managed VNet flavor.
- Windows jumpbox + Azure Bastion for reaching the private Foundry portal without VPN/peering.
- Single-command `azd up` / `azd down`.

## Architecture

```
┌─ Your VNet (vnet-<prefix>) ──────────────────────────────────────────────┐
│                                                                          │
│  ┌─ snet-<prefix>-pe ─────────────┐    ┌─ snet-<prefix>-agent ─────────┐ │
│  │  /24                            │    │  /24, DELEGATED               │ │
│  │                                 │    │  to Microsoft.App/environments│ │
│  │  ▾ pep-foundry  ───→ Foundry    │    │                               │ │
│  │  ▾ pep-search   ───→ AI Search  │◀───┤  Data Proxy (1 per project)   │ │
│  │  ▾ pep-cosmos   ───→ Cosmos     │    │  Hosted-agent Micro VMs       │ │
│  │  ▾ pep-blob     ───→ Storage    │    │  Prompt-agent infra (shared)  │ │
│  └─────────────────────────────────┘    └───────────────────────────────┘ │
│                                                                          │
│  ┌─ snet-<prefix>-vm ─────────────┐    ┌─ AzureBastionSubnet ──────────┐ │
│  │  Jumpbox VM + NAT Gateway      │    │  Bastion (browser RDP/SSH)    │ │
│  └─────────────────────────────────┘    └───────────────────────────────┘ │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
       ▲                              ▲
       │ Bastion in-browser           │ HTTPS via PE
   You (laptop)                  Foundry portal calls
```

**Key difference vs Managed VNet:**
- ✅ Agent compute IPs are in **your** VNet (auditable, allow-listable)
- ✅ No "hidden" Microsoft VNet
- ❌ You manage subnet IP budget (`/24` recommended, `/26` minimum for 50 concurrent sessions)
- ❌ You create all PEs yourself — Foundry does not auto-create managed PEs in this model

## Why a delegated subnet?

The platform deploys agent compute as **Container Apps environments** inside your subnet. That delegation tells Azure: *"Microsoft.App may create network interfaces, configure routing, and manage IP allocation in this subnet."* Two things flow from it:

1. **Data Proxy** — one per Foundry project, runs in your subnet as a Container Apps replica. **All tool-server calls** (Cosmos writes, Search queries, Storage uploads) route through the Data Proxy → out via private endpoints to your data resources.
2. **Hosted agents** — your own container image (via your ACR). Each runs as a Micro VM with its own NIC in your subnet. Tool calls still go through the Data Proxy, but the agent's *own* outbound (e.g., LLM API calls) uses its dedicated NIC.

**Prompt agents** are MS-managed compute — they share the project's Data Proxy infra and don't consume per-agent IPs.

## Subnet sizing (the math that matters)

Per the [deep-dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive):

| Subnet size | Usable IPs | Approximate concurrent sessions |
|---|---|---|
| `/27` | ~27 | ~17 |
| `/26` | ~59 | ~50 (platform maximum per subscription per region) |
| `/24` *(this template)* | ~250 | 50 + headroom for upgrades, scaling, revisions |

**IP consumption ratio:** ~1 IP per 10 pods. Each project starts with 1 Data Proxy replica (~1 IP) and scales out under load. Heavy traffic on 10 projects × 10 replicas = ~10 IPs just for proxies. Add Hosted-agent revisions (parallel old + new during rollout) and the budget tightens quickly.

**Rule of thumb:** **target 80% max utilization** to absorb platform upgrade spikes. This template uses `/24` because it's the production-recommended size and leaves plenty of room.

## What's deployed

| Resource | Why it exists |
|---|---|
| **VNet + 4 subnets** | PE subnet (data PEs), VM subnet (jumpbox), Bastion subnet, **delegated agent subnet** |
| **NAT Gateway** on VM subnet | Default outbound is being retired by Azure; jumpbox needs egress for `pip install` + GitHub |
| **AI Foundry account** | With `networkInjections.subnetArmId = agent-subnet-id` + `useMicrosoftManagedNetwork: false` |
| **AI Foundry project** | With three BYO connections (Cosmos, Storage, Search), all `authType: AAD` |
| **Model deployments** | `gpt-4.1-mini` + `text-embedding-3-large` (30 K TPM default) |
| **AI Search** (Basic) | `publicNetworkAccess: Disabled`, BYO trio's vector-store backend |
| **Cosmos DB NoSQL** | `publicNetworkAccess: Disabled`, BYO trio's thread store |
| **Storage account** | `publicNetworkAccess: Disabled`, BYO trio's file/agent-dir storage |
| **6 Private DNS zones** | Foundry needs `cognitiveservices`, `openai`, `services.ai`. Plus `search`, `documents` (Cosmos), `blob` |
| **4 Private endpoints** | One each for Foundry, Search, Cosmos, Storage — all in your PE subnet |
| **`capabilityHost`** | The non-optional resource that binds the three BYO connections to the agent runtime |
| **Two-phase RBAC** | Pre-caphost (project MI → BYO resources) + post-caphost (Storage Blob Data Owner with ABAC + Cosmos SQL data role) |
| **Jumpbox VM** | Windows + System MI; used for indexer + Bastion-based portal access |
| **Azure Bastion** | Browser-based RDP without exposing the jumpbox publicly |

## Two layers of private endpoints in this architecture (important!)

If you read the [Foundry networking deep-dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive) before this README, you'll notice its example diagram shows **Storage, SQL DB, and Key Vault** behind PEs — not Cosmos and AI Search. That's not a contradiction; it's two **different layers** of PEs that need to coexist in a real BYO-VNet deployment.

| Layer | What it is | What sits behind PEs | Required? | Where it's documented |
|---|---|---|---|---|
| **1. Foundry runtime infrastructure** *(this template)* | The data layer the Agent Service itself uses internally — thread state, agent files, vector stores | **Cosmos + Storage + AI Search** (the BYO data trio) | ✅ Mandatory. The project `capabilityHost` literally has `threadStorageConnections + storageConnections + vectorStoreConnections` as required fields. Skip any and the runtime fails with *"Invalid endpoint or connection failed"*. | [how-to/virtual-networks](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks) |
| **2. Your tool-server backends** *(out of scope here)* | The downstream resources **your agent's tools** call to do business logic — query a customer DB, fetch a secret, hit your API | Whatever your tools need — examples in the docs are Storage, SQL DB, Key Vault, but it could be Postgres, Redis, a private REST API, anything | Optional. Only needed if your agents call tools against your own backends. | [concepts/agents-networking-deep-dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive) (the "egress to customer resources" section) |

**Why the deep-dive uses Storage/SQL DB/Key Vault as examples:** they're the most common "PaaS behind a PE" examples Microsoft writers reach for when illustrating *outbound* traffic from the Data Proxy. The deep-dive is **purely about network traffic flow** (IPs, subnets, Data Proxy, revisions) and *assumes* the BYO data trio is already configured — it cross-links to the how-to for that.

```
Foundry Agent Service request
        │
        ▼
┌─ Layer 1: Foundry runtime (BYO data trio) ────────────┐
│  needs (mandatory, what THIS template builds):        │
│    • Cosmos    → thread state                         │
│    • Storage   → agent files                          │
│    • AI Search → vector stores                        │
└───────────────────────────────────────────────────────┘
        │
        │ (your agent decides to call a tool)
        ▼
┌─ Layer 2: Your tool-server backends (your additions) ─┐
│  egresses to (optional, add as needed):               │
│    • SQL DB / Postgres / Cosmos for your app data     │
│    • Key Vault for your secrets                       │
│    • A different Storage account for your blobs       │
│    • A private REST API in another VNet               │
│    • Anything else your tools need                    │
└───────────────────────────────────────────────────────┘
```

**Adding Layer 2 resources** is straightforward — provision them in `infra/resources.bicep`, add a private endpoint into `snet-<prefix>-pe`, link the matching `privatelink.*` DNS zone to your VNet, and grant your tool's identity the right RBAC. The Data Proxy in `snet-<prefix>-agent` will reach them over the PE automatically.

## What's the same as the Managed VNet flavor

The following modules are **byte-identical** to the validated [Managed VNet repo](https://github.com/SridharArrabelly/foundry-private-managed-vnet):

- `cosmos.bicep`, `storage.bicep`, `ai-search.bicep` — the data resources
- `ai-foundry-project.bicep` — project + model deployments + BYO connections
- `capability-host.bicep` — the project `capabilityHost`
- `byo-role-assignments.bicep` — pre-caphost RBAC
- `post-caphost-role-assignments.bicep` — post-caphost RBAC + ABAC
- `format-workspace-id.bicep` — helper for the post-caphost workspace GUID
- `jumpbox.bicep` — VM + Bastion
- All `scripts/*` files — postprovision hooks + jumpbox bootstrap + indexer

## What's different

| Module | Difference |
|---|---|
| `network.bicep` | **+1 subnet** — `snet-<prefix>-agent` `/24` with `delegations: Microsoft.App/environments` |
| `ai-foundry-account.bicep` | `networkInjections.subnetArmId = <agent subnet>`, `useMicrosoftManagedNetwork: false`, **removed** the `managednetworks` child resource (Managed VNet only), **removed** the auto-approver role (no managed PEs to auto-approve in BYO model) |
| `private-endpoints.bicep` | Functionally identical, but you should **assume Foundry won't auto-create a second set** of PEs from any hidden VNet — your PEs are the only path |
| `role-assignments.bicep` | **Removed** the `Azure AI Enterprise Network Connection Approver` role (only needed by Managed VNet flavor) |

## Prerequisites

- Azure subscription with Owner or User Access Administrator + Cognitive Services Contributor roles
- `azd` CLI (`>= 1.10`)
- `az` CLI installed and authenticated
- Git
- A clone of this repository

The following **resource providers must be registered** in your subscription:

```bash
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.MachineLearningServices
az provider register --namespace Microsoft.Search
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.App         # required for subnet delegation
az provider register --namespace Microsoft.ContainerService
```

## Deploy

```bash
azd auth login
azd env new fun-byo-dev
azd env set AZURE_LOCATION swedencentral
azd env set VM_ADMIN_PASSWORD '<a-strong-password>'
azd up
```

`azd up` takes ~15–20 min:
- ~5 min for network + data resources + Foundry account
- ~3 min for project + BYO connections
- ~30 sec for capabilityHost binding *(faster than Managed VNet — no managed-PE auto-provisioning step)*
- ~5–10 min for jumpbox bootstrap + indexer

### Smoke-test from the jumpbox

The postprovision hook automatically:
1. Pulls this repo onto the jumpbox via `az vm run-command`
2. Installs Python 3.12 + dependencies
3. Runs `scripts/setup_aisearch_index.py` to create `documents-index` from `data/*.docx`

After it succeeds, RDP to the jumpbox via Bastion and open the Foundry portal at `https://ai.azure.com` — you're now inside the VNet, so the portal works against the private endpoint.

Create an agent, attach the **AI Search** tool pointing at `documents-index`, and ask a question. If the response is grounded in the indexed content, you've proven:
- Agent compute (in your delegated subnet) → Data Proxy (in your delegated subnet) → AI Search PE (in your PE subnet) → results.

### Adapting the indexer

Same as the Managed VNet flavor — see `scripts/setup_aisearch_index.py`. It's a demonstration of the private path, not a runtime requirement. Foundry creates its own `vs_*` / `chunks_*` indexes on demand when the File Search tool is used.

## Verify the deployment

After `azd up` completes, walk these seven checks. Set the shell vars once:

```bash
RG=rg-fun-byo-dev
PREFIX=funbyodev                    # confirm with: azd env get-values | grep PREFIX
ACCT=ais-$PREFIX
PROJ=$(az cognitiveservices account project list -n $ACCT -g $RG --query "[0].name" -o tsv)
SUB=$(az account show --query id -o tsv)
```

**1. Provisioning succeeded**

```bash
az group show -n $RG --query "properties.provisioningState" -o tsv    # → Succeeded
azd env get-values | grep -E 'AI_FOUNDRY|AI_SEARCH|JUMPBOX|BASTION|VNET_ID|AGENT_SUBNET_ID'
```

**2. Agent subnet is delegated** *(BYO-specific — this is what makes it BYO)*

```bash
az network vnet subnet show -g $RG -n snet-$PREFIX-agent --vnet-name vnet-$PREFIX \
  --query "delegations[].serviceName" -o tsv
# → Microsoft.App/environments
```

**3. Public network is OFF on all 4 data resources**

```bash
az cognitiveservices account show -n ais-$PREFIX   -g $RG --query properties.publicNetworkAccess -o tsv
az search service show           -n srch-$PREFIX   -g $RG --query publicNetworkAccess           -o tsv
az cosmosdb show                 -n cosmos-$PREFIX -g $RG --query publicNetworkAccess           -o tsv
az storage account show          -n st$PREFIX      -g $RG --query publicNetworkAccess           -o tsv
# All four → Disabled  (Enabled is also OK only if you set ALLOWED_IP_ADDRESS for first-deploy access)
```

**4. CapabilityHost is bound to all 3 connections**

```bash
az rest --method get --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCT/projects/$PROJ/capabilityHosts?api-version=2025-10-01-preview" \
  --query "value[0].properties.{thread:threadStorageConnections, storage:storageConnections, vector:vectorStoreConnections}" -o json
# Expect each array to have exactly 1 entry. Empty arrays = capabilityHost failed to bind.
```

**5. The 3 project connections all use Entra ID (AAD)**

```bash
az rest --method get --url "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$ACCT/projects/$PROJ/connections?api-version=2025-10-01-preview" \
  --query "value[].{name:name, category:properties.category, auth:properties.authType}" -o table
# All three rows → authType: AAD
```

**6. From the jumpbox — DNS resolves to private IPs**

RDP to `vm-$PREFIX` via Bastion (`bas-$PREFIX`), then in PowerShell:

```powershell
nslookup ais-$env:PREFIX.cognitiveservices.azure.com    # → 10.0.1.x  (PE subnet)
nslookup srch-$env:PREFIX.search.windows.net            # → 10.0.1.x
nslookup cosmos-$env:PREFIX.documents.azure.com         # → 10.0.1.x
nslookup st$env:PREFIX.blob.core.windows.net            # → 10.0.1.x
```

A public IP back means the matching `privatelink.*` DNS zone isn't linked to your VNet — check `modules/private-endpoints.bicep` outputs.

**7. End-to-end agent smoke test (the one that actually proves it)**

Still on the jumpbox, open `https://ai.azure.com` → your project → **Agents → New agent**:

1. Model: `gpt-4.1-mini` (or whichever deployment was created)
2. Add tool: **Azure AI Search** → connection auto-selected → index = `documents-index`
3. Prompt: *"Summarize the February 15 board meeting decisions."*

✅ **Grounded answer** = full BYO-VNet path works: Agent compute (your delegated `snet-$PREFIX-agent`) → Data Proxy (same subnet) → AI Search PE (your `snet-$PREFIX-pe`) → results. Zero traffic over the public internet at any hop.

❌ **"Invalid endpoint or connection failed."** = capabilityHost or connection auth — see [Troubleshooting](#troubleshooting) below.

## Brownfield: deploying into an existing customer VNet

The default template builds a **greenfield** VNet (with NAT Gateway, jumpbox, Bastion) so you can `azd up` and have everything just work. If your customer already runs other workloads in their own VNet (hub-spoke / landing zone / etc.), you don't deploy a new VNet — you **point Foundry at their existing subnet** and skip everything the customer already provides.

### What the customer VNet must provide

| # | Requirement | Why |
|---|---|---|
| 1 | **Dedicated subnet, `/24` recommended** (`/26` minimum, ~50 concurrent sessions) | Foundry deploys Data Proxy + Hosted-agent Micro VMs here. ~1 IP per 10 pods + 1 per active Hosted-agent revision. |
| 2 | That subnet is **empty** and **delegated to `Microsoft.App/environments`** | Subnet delegation is exclusive; the platform owns the subnet. |
| 3 | **Explicit outbound** from that subnet — NAT Gateway, Azure Firewall, or UDR → NVA | Azure default-outbound retired Sep 30 2025. Foundry pulls model API + ACR images. |
| 4 | A subnet for **private endpoints** with `privateEndpointNetworkPolicies: Disabled` (can be shared with other workloads) | Houses the 4 PEs (Foundry, Cosmos, Storage, AI Search). |
| 5 | The 4 `privatelink.*` DNS zones reachable from the VNet — either VNet-linked, or resolvable via a Private DNS Resolver / customer DNS forwarder | So the agent subnet resolves `*.cognitiveservices.azure.com` etc. to PE IPs. |
| 6 | No NSG/firewall rules blocking: `agent → PE subnet:443`, `agent → internet (model API + ACR)` | Required outbound paths. |

### Pre-flight check (send this to the customer before deploying)

```bash
VNET_ID=<their VNet ARM ID>
AGENT_SUBNET=<their delegated subnet ARM ID>
PE_SUBNET=<their PE subnet ARM ID>
DNS_RG=<RG containing the privatelink zones>

# 1. Agent subnet is empty and delegated
az network vnet subnet show --ids $AGENT_SUBNET \
  --query "{delegation:delegations[0].serviceName, ipConfigs:ipConfigurations}" -o json
# → delegation: "Microsoft.App/environments", ipConfigs: null

# 2. PE subnet has policies disabled
az network vnet subnet show --ids $PE_SUBNET --query "privateEndpointNetworkPolicies" -o tsv
# → Disabled

# 3. Agent subnet has explicit outbound
az network vnet subnet show --ids $AGENT_SUBNET --query "{nat:natGateway.id, udr:routeTable.id}" -o json
# At least one non-null

# 4. The 4 privatelink DNS zones exist and link to the VNet
for zone in privatelink.cognitiveservices.azure.com privatelink.search.windows.net privatelink.documents.azure.com privatelink.blob.core.windows.net; do
  echo "=== $zone ==="
  az network private-dns link vnet list --zone-name $zone -g $DNS_RG \
    --query "[?virtualNetwork.id=='$VNET_ID'].name" -o tsv
done
# Each should output a link name (empty = not linked, fix before deploy)

# 5. Required resource providers registered
for rp in Microsoft.CognitiveServices Microsoft.Search Microsoft.Storage Microsoft.DocumentDB Microsoft.App Microsoft.Network Microsoft.MachineLearningServices; do
  echo -n "$rp: "; az provider show --namespace $rp --query registrationState -o tsv
done
```

### What to change in this template

The data-layer modules (`cosmos.bicep`, `storage.bicep`, `ai-search.bicep`), the Foundry account/project, the `capabilityHost`, and both RBAC modules **stay exactly the same** — they're brand-new Foundry-dedicated resources. The changes are all in the networking edges:

| Change | What to do |
|---|---|
| Stop creating the VNet/NAT Gateway/subnets | **Delete** `module network` from `infra/resources.bicep`. Add three params to `main.bicep`: `existingAgentSubnetId`, `existingPeSubnetId`, `existingVnetId`. Replace every `network.outputs.X` reference with the matching param. |
| Stop creating DNS zones | In `modules/private-endpoints.bicep`, **remove** the `Microsoft.Network/privateDnsZones` resources and their VNet links. On each PE's `privateDnsZoneGroups`, reference the customer's existing zones via `resourceId('<dns-rg>', 'Microsoft.Network/privateDnsZones', 'privatelink.X')`. Add a `dnsZoneResourceGroupName` param. |
| Skip the jumpbox if they already have VNet access | Delete the `jumpbox` module and the `jumpboxPrincipalId` line in `role-assignments.bicep`. They'll RDP via their existing Bastion / ExpressRoute / VPN / Dev Box. |
| Run the indexer from inside the VNet | The `postprovision` hook needs an in-VNet runner. Three options: (a) keep the jumpbox just for first-deploy indexing then delete it; (b) point the hook at any existing VM/Dev Box/self-hosted runner via `az vm run-command`; (c) skip the indexer entirely and let Foundry create `vs_*`/`chunks_*` indexes on demand. |

### Cross-RG / cross-subscription notes

- **Cross-RG VNet** (common): the deployment principal needs `Microsoft.Network/virtualNetworks/subnets/join/action` on both subnets — grant **Network Contributor** scoped to each subnet (or their RG).
- **Cross-subscription VNet**: split into two `azd` deployments, or use a subscription-scope deployment with explicit RG targeting. Foundry account + data resources go in your workload subscription; PEs reference the foreign-subscription subnets by full ARM ID (works fine).
- **DNS zones in a separate RG** (Cloud Adoption Framework default): use `existing` references and grant **Private DNS Zone Contributor** on the zones to whoever creates the `A` records (auto-created by `privateDnsZoneGroups` on each PE).

### Verify against the customer VNet

Use the same [7-step Verify recipe](#verify-the-deployment) above — just substitute the customer's vnet/subnet names. Step 2 (subnet delegation) now points at the customer's subnet ID instead of `snet-$PREFIX-agent`; the rest is identical.

## Hosted vs Prompt agents

This template deploys the infrastructure for **both**. You choose which one to use when creating an agent:

| | **Hosted agent** | **Prompt agent** |
|---|---|---|
| Compute | Your container image (via ACR — **see note below**) | Microsoft-managed |
| You control CPU/memory? | ✅ | ❌ |
| Consumes subnet IPs per revision? | ✅ (~1 IP per Hosted agent + 1 per active revision during rollout) | ❌ (shares project Data Proxy) |
| Max active revisions per agent | 100 | n/a |
| Max instances per Foundry account | ~200 Hosted agents | ~250 projects total |
| Use when | You need custom packages, full control, predictable performance | You just want to define agent behavior in config; MS handles scaling |

> ⚠️ **Not included in this template:** an **Azure Container Registry (ACR)** for Hosted-agent images. If you only use **Prompt agents**, you need nothing extra. To use **Hosted agents**, add an ACR (with a private endpoint into the same `snet-<prefix>-pe` subnet and the `privatelink.azurecr.io` DNS zone), grant the project MI `AcrPull`, and reference image tags when creating each agent. The Foundry Agent Service docs cover the ACR wiring in the same [virtual-networks how-to](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks).

## Deeper background

The data layer (Cosmos/Storage/Search + `capabilityHost` + two-phase RBAC + DNS) is identical to the Managed VNet flavor. The "**why**" behind every piece of that layer — why all three BYO resources are mandatory, why RBAC is split into two phases, why the `capabilityHost` is the linchpin — is documented at length in the sibling repo. Read it once and you understand both flavors:

👉 [Managed VNet repo → Understanding the design](https://github.com/SridharArrabelly/foundry-private-managed-vnet#understanding-the-design-why-is-this-so-complex)

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `agent subnet must be delegated to Microsoft.App/environments` | Subnet delegation didn't apply — check `network.bicep` and re-run `azd provision` |
| `Subnet too small / IP exhaustion` | Increase subnet size to `/24` minimum. Existing template uses `/24`. |
| Agent fails with `RoleAssignmentExists` | A `(principal, role, scope)` triple was assigned twice. Check `byo-role-assignments.bicep` vs `role-assignments.bicep`. |
| Indexer "fails" with stderr warnings but stdout shows `Indexing complete.` | The postprovision script checks for the success marker — should pass. If you see false-positives, see the [Managed VNet flavor troubleshooting](https://github.com/SridharArrabelly/foundry-private-managed-vnet#troubleshooting). |
| `CustomDomainInUse` on redeploy | Cognitive Services subdomain soft-deleted for 48h. `az cognitiveservices account purge -n ais-<prefix> -g <rg> -l <loc>` or change `prefix`. |
| Region capacity errors | `eastus` exhausted for Cosmos; `eastus2` exhausted for Search. **`swedencentral` tested working** for Managed VNet variant. Try also `westus3`, `australiaeast`, `uksouth`. |

## Cleanup

```bash
azd down --force --purge
```

⚠️ If `azd down` fails with `cannot unmarshal array into Go value of type map[string]json.RawMessage` (known azd SDK bug with `networkInjections`):

```bash
az group delete -n rg-fun-byo-dev --yes --no-wait
az cognitiveservices account purge -n ais-<prefix> -g rg-fun-byo-dev -l swedencentral
```

## References

- [Foundry Agent Service — Set up private networking](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks?tabs=portal)
- [Foundry Agent Service — Networking deep-dive](https://learn.microsoft.com/azure/foundry/agents/concepts/agents-networking-deep-dive)
- [Container Apps environments — VNet integration](https://learn.microsoft.com/azure/container-apps/networking)
- [Managed VNet flavor (sibling repo)](https://github.com/SridharArrabelly/foundry-private-managed-vnet) — the more battle-tested counterpart
- [Decision hub](https://github.com/SridharArrabelly/foundry-private-networking-samples) — pick the right flavor for your scenario
