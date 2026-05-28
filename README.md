# Foundry Private Networking — BYO VNet

Deploy Azure AI Foundry Agents with agent compute injected into your **delegated subnet**, plus private access to **Cosmos DB**, **Storage**, and **AI Search**.

Use this sample when agent compute must live inside the customer VNet.

> **New here?** Start with the [decision hub](https://github.com/SridharArrabelly/foundry-private-networking-samples) to choose between Managed VNet and BYO VNet.

## Why use this sample

Choose this sample when you need:

- Agent IPs inside the customer VNet
- Customer-visible flows in NSG or firewall logs
- Customer ownership of the agent runtime network path (for downstream allow-listing or auditing)
- Explicit IP-aware integration with downstream systems
- A design aligned to stricter regulatory or network-control requirements

If you do **not** need those things, start with the [Managed VNet sample](https://github.com/SridharArrabelly/foundry-private-managed-vnet) instead.

## What is different from Managed VNet

Compared with Managed VNet, this sample adds or changes the following:

- Agent compute is injected into a **delegated subnet**
- A **Data Proxy** is part of the network path
- Subnet sizing and IP planning matter
- Operational complexity is higher
- Traffic visibility is higher because it lives in the customer network boundary

For a full visual comparison, see the [Side-by-side architecture comparison](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/side-by-side.md).

## What this repo deploys

- Azure AI Foundry account and project
- Delegated-subnet network model
- Data Proxy path
- BYO Cosmos DB, Storage, and AI Search
- `capabilityHost` binding to the data layer
- Private networking and required RBAC chain
- Jumpbox / Bastion access pattern for private portal access
- One-command deployment with `azd up`
- One-command teardown with `azd down`

## Architecture

See the detailed architecture walkthrough here:

- [BYO VNet architecture](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/byo-vnet.md)
- [Side-by-side comparison with Managed VNet](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/side-by-side.md)

At a high level:

- Private endpoints live in a private endpoint subnet
- Agent compute is injected into a delegated subnet
- Data Proxy brokers the agent-side network path
- Cosmos DB, Storage, and AI Search remain private
- Jumpbox / Bastion provides a path to access the private Foundry experience

## Quick start

### Prerequisites

- An Azure subscription you can deploy into
- Azure CLI
- Azure Developer CLI (`azd`)
- Rights to create resources and assign required roles
- A target region that supports your chosen Foundry setup
- A delegated subnet plan for the agent-side network path
- **VNet address space must be RFC 1918** (`10.0.0.0/8`, `172.16.0.0/12`, or `192.168.0.0/16`). CGNAT (`100.64.0.0/10`) and other Azure-reserved ranges fail at `capabilityHost` create — see [known limitations #10](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/known-limitations.md#10-rfc-1918-only--cgnat-and-reserved-ranges-fail-at-capabilityhost-create).
- **Resource providers registered:** the agent runtime needs both `Microsoft.App` and `Microsoft.ContainerService` registered on the target subscription before `azd up`. Without them, `capabilityHost` create fails.
  ```bash
  az provider register --namespace 'Microsoft.App'
  az provider register --namespace 'Microsoft.ContainerService'
  # Wait until both report Registered:
  az provider show -n 'Microsoft.App' --query registrationState -o tsv
  az provider show -n 'Microsoft.ContainerService' --query registrationState -o tsv
  ```

### Deploy

```bash
git clone https://github.com/SridharArrabelly/foundry-private-byo-vnet.git
cd foundry-private-byo-vnet
azd auth login

# Required: set the jumpbox local-admin password before `azd up` (12+ chars, mixed case + digits + symbols).
# `main.parameters.json` requires this and has no default — `azd up` will fail without it.
azd env set VM_ADMIN_PASSWORD '<your-strong-password>'

# Optional: pin a short prefix used in resource names (3–10 lowercase letters/digits)
azd env set PREFIX 'fun'

# Optional: keep one public IP/CIDR reachable (your laptop) while everything else stays private.
# Leave unset to disable all public exposure.
azd env set ALLOWED_IP_ADDRESS '<your-public-ip>'

azd up
```

You'll be prompted for `AZURE_ENV_NAME` and `AZURE_LOCATION` on first run. The samples are validated in `swedencentral`; other regions may require Foundry / capabilityHost preview availability checks.

### Tear down

```bash
azd down
```

## Capacity and subnet sizing

Subnet planning matters in this model. Rules of thumb:

- **VNet address space must be RFC 1918.** CGNAT (`100.64.0.0/10`) and other Azure-reserved ranges will fail at `capabilityHost` create. See [Prerequisites](#prerequisites).
- **`/27` (32 addresses) is the floor, not a recommendation.** ACA scale-out on the agent subnet and any future BYO PEs will hit a `/27` ceiling fast.
- **Plan for `/26` minimum** on net-new deployments; use `/24` if you want real headroom for growth or higher concurrency.
- Leave room for revisions, upgrades, and operational churn (ACA allocates ~1 IP per 10 pods + 1 per Hosted-agent revision).
- Validate subnet design early if the environment is tightly controlled.

## Validate the deployment

After `azd up` completes, run the **[copy-paste CLI checks](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/validation-checklist.md#cli-verification--7-concrete-checks)** to prove the full chain works end-to-end. For BYO VNet, **6 of the 7 checks apply** — Check 3 (`networkInjections` for the managed VNet) is informational only since BYO uses subnet injection instead.

Checks 1–6 run from your dev box (`az` CLI + `nslookup` from a Bastion session). **Check 7** is a Python smoke test that runs from the jumpbox — to use it you need Python + the project's dependencies on the jumpbox, which is what `scripts/bootstrap-jumpbox.{ps1,sh}` sets up (see [Optional: populate sample data + bootstrap the jumpbox](#optional-populate-sample-data--bootstrap-the-jumpbox) below).

BYO-specific things also worth confirming:

- The agent runtime's NIC appears in your **delegated subnet** (`az network nic list -g <rg> --query "[?contains(name, 'agent')].ipConfigurations[].privateIPAddress"`)
- Outbound agent traffic is visible in your **NSG flow logs** (if enabled) — that is the whole reason you picked BYO over Managed VNet
- Delegated subnet has free IP capacity for future scale (see [Capacity and subnet sizing](#capacity-and-subnet-sizing) above)

## Optional: populate sample data + bootstrap the jumpbox

> `azd up` provisions infrastructure only. It does **not** install Python on the jumpbox or index any sample data. Run this step **only** if you want the AI Search smoke test (validation Check 7) or File Search to have data to query. Most real customers will skip this and bring their own data + their own indexer.

The repo ships `data/sample_document.pdf` as a generic test corpus, and `scripts/bootstrap-jumpbox.{ps1,sh}` automates one-time setup of the jumpbox.

### What it does

Run from your dev box, against the active `azd` environment. It:

1. Reads `AZURE_RESOURCE_GROUP`, `JUMPBOX_VM_NAME`, `AI_SEARCH_ENDPOINT`, `AI_FOUNDRY_ENDPOINT` from `azd env get-values`
2. Calls `az vm run-command invoke` to push `scripts/jumpbox-bootstrap.ps1` to the jumpbox over the Azure backplane (no Bastion / RDP required)
3. The jumpbox-side script installs Python 3.12, downloads the repo zip, runs `scripts/setup_aisearch_index.py` (auth via the VM's system-assigned managed identity), and uploads embeddings for every `.pdf` / `.docx` under `data/`

### Run it

```bash
./scripts/bootstrap-jumpbox.sh      # macOS / Linux / WSL
./scripts/bootstrap-jumpbox.ps1     # Windows PowerShell
```

Takes ~5–10 minutes on first run. Re-running it is safe — Python install is skipped if already present, and the index is upserted.

### Use your own corpus

Drop `.pdf` / `.docx` files into `data/`, then re-run `bootstrap-jumpbox`. Override the index name with `AI_SEARCH_INDEX_NAME` before running if you want a non-default name.

### Point the agent at an existing index instead

If you already have an AI Search index you want to use, **skip this step entirely**. Set `AI_SEARCH_INDEX_NAME` to your index name when wiring up your agent — the infrastructure deployment does not assume `documents-index` exists.

### Clean up the sample index

```bash
az search index delete --service-name <ai-search-name> --name documents-index -y
```

Doesn't affect the rest of the infrastructure.

## Troubleshooting

The single most common silent failure — same as Managed VNet — is an agent run that returns:

```
Invalid endpoint or connection failed
```

That almost always means `capabilityHost` is missing or unbound. Start with [Design rationale → What happens if you skip capabilityHost](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/design-rationale.md#2-what-happens-if-you-skip-capabilityhost), then run [validation check #4](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/validation-checklist.md#check-4--capabilityhost-is-bound-to-all-3-connections).

BYO-specific failure modes:

- **Agent provisioning hangs or fails with subnet errors** — the delegated subnet is full, mis-delegated, or has an NSG that blocks `Microsoft.Cognitive Services`. Check `az network vnet subnet show -g <rg> --vnet-name <vnet> -n <delegated-subnet>` for `delegations` and free IP count.
- **DNS resolves to public IPs from inside the VNet** — your VNet is not linked to one of the 6 `privatelink.*` zones. See the [DNS zones table](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/capabilityhost-rbac-dns.md#private-dns-zones).
- **Traffic does not appear in NSG flow logs** — flow logs are not enabled on the delegated subnet's NSG, or the agent traffic is taking a different egress path than expected.

For deployment-time errors (`azd down` SDK bug, `CustomDomainInUse`, region capacity), see [Known limitations](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/known-limitations.md). For the full troubleshooting decision tree, see [Troubleshooting order](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/capabilityhost-rbac-dns.md#troubleshooting-order).

## Related docs

- [Decision hub (parent)](https://github.com/SridharArrabelly/foundry-private-networking-samples) — when to pick BYO vs Managed VNet
- [Compare with Managed VNet](https://github.com/SridharArrabelly/foundry-private-managed-vnet) — the other sample in this family
- [BYO VNet architecture](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/byo-vnet.md) — diagram + component walkthrough
- [Side-by-side architecture comparison](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/side-by-side.md)
