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

For a full visual comparison, see the [Side-by-side architecture comparison](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/architecture-diagrams/side-by-side.md).

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

- [BYO VNet architecture](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/architecture-diagrams/byo-vnet.md)
- [Side-by-side comparison with Managed VNet](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/architecture-diagrams/side-by-side.md)

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
azd up
```

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

After deployment, validate the following:

- You can reach the Foundry experience through the intended private access path
- The agent can call AI Search
- Thread state is written to Cosmos DB
- File operations land in Storage
- Traffic is visible in the customer network boundary where expected
- Private endpoints, DNS, and RBAC are all functioning end-to-end

For a full checklist, see the [Validation checklist](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/validation-checklist.md).

## Known caveats

Before using this as a production baseline, confirm:

- Region support for your exact scenario
- Feature support for the agent capabilities you plan to use
- Delegated subnet sizing and network policy alignment
- Validation of the network-injection path in your target environment

See [Known limitations](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/known-limitations.md) for the full list.

## Related docs

- [Compare with Managed VNet](https://github.com/SridharArrabelly/foundry-private-managed-vnet)
- [Decision hub](https://github.com/SridharArrabelly/foundry-private-networking-samples)
- [BYO VNet architecture](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/architecture-diagrams/byo-vnet.md)
- [Side-by-side architecture comparison](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/architecture-diagrams/side-by-side.md)
- [Shared data plane](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/shared-data-plane.md)
- [capabilityHost, RBAC, and DNS](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/capabilityhost-rbac-dns.md)
- [Validation checklist](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/validation-checklist.md)
- [Known limitations](https://github.com/SridharArrabelly/foundry-private-networking-samples/blob/docs/lean-readme/docs/known-limitations.md)

## Why this repo exists

This repo is designed for scenarios where private access alone is not enough and the customer also needs control and visibility over the agent network path. Use it to:

- Validate a delegated-subnet design with Foundry Agents
- Show the trade-off between simplicity and network control
- Give regulated customers a reference starting point they can evolve further
