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

- Use `/24` if you want more headroom for growth or higher concurrency
- Treat `/26` as the practical minimum for smaller scenarios
- Leave room for revisions, upgrades, and operational churn
- Validate subnet design early if the environment is tightly controlled

## Validate the deployment

After `azd up` completes, run the **[7 copy-paste CLI checks](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/validation-checklist.md#cli-verification--7-concrete-checks)** to prove the full chain works end-to-end:

1. provisioning state → 2. public network OFF on all 4 data resources → 3. capabilityHost bound to all 3 connections → 4. connections use `authType: AAD` → 5. DNS resolves to private IPs from jumpbox → 6. agent smoke test returns `completed`

BYO-specific things also worth confirming:

- The agent runtime's NIC appears in your **delegated subnet** (`az network nic list -g <rg> --query "[?contains(name, 'agent')].ipConfigurations[].privateIPAddress"`)
- Outbound agent traffic is visible in your **NSG flow logs** (if enabled) — that is the whole reason you picked BYO over Managed VNet
- Delegated subnet has free IP capacity for future scale (see [Capacity and subnet sizing](#capacity-and-subnet-sizing) above)

## Sample data and the test index

The `data/` folder ships with `sample_document.pdf` as a generic placeholder corpus, used purely to prove the private **AI Search** path works end-to-end. During `azd up`, the postprovision hook runs `scripts/setup_aisearch_index.py` on the jumpbox, which:

- Creates an AI Search index named `documents-index` (override with the `AI_SEARCH_INDEX_NAME` env var)
- Reads every `.docx` and `.pdf` file under `data/`, chunks the content, generates embeddings via Azure OpenAI, and uploads them

To test with your own corpus, drop your `.docx` / `.pdf` files into `data/` and re-run either:

```bash
azd provision    # re-runs the full postprovision hook
# or, from the jumpbox directly:
python scripts/setup_aisearch_index.py
```

Once testing is done, you have two options — neither affects the rest of the infrastructure:

- **Delete the sample index** when you no longer need it:
  ```bash
  az search index delete --service-name <ai-search-name> --name documents-index -y
  ```
- **Point the agent at your own existing AI Search index** instead — set `AI_SEARCH_INDEX_NAME` in your `.env` to your index name before `azd provision`, and skip the sample indexer by emptying `data/`.

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

- [Compare with Managed VNet](https://github.com/SridharArrabelly/foundry-private-managed-vnet)
- [Decision hub](https://github.com/SridharArrabelly/foundry-private-networking-samples)
- [BYO VNet architecture](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/byo-vnet.md)
- [Side-by-side architecture comparison](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/architecture-diagrams/side-by-side.md)
- [Design rationale](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/design-rationale.md) — why the BYO triple is required, what happens if you skip `capabilityHost`, and why BYO collapses the dual-PE pattern
- [Shared data plane](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/shared-data-plane.md)
- [capabilityHost, RBAC, and DNS](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/capabilityhost-rbac-dns.md)
- [Validation checklist](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/validation-checklist.md) — 7 copy-paste CLI checks
- [Known limitations](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/master/docs/known-limitations.md)
