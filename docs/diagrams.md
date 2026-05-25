# Architecture Diagrams — BYO VNet flavor

Four diagrams, each answering one question. Read them top-to-bottom on first visit; jump straight to a specific one on follow-ups. All diagrams use the same colour legend so concepts stay recognisable across views.

## Colour legend

| Colour | Meaning |
|---|---|
| 🟦 Blue | **Your** VNet, subnets, resources, identities |
| 🟪 Purple | **Microsoft-managed** components (only the Foundry control plane in this flavor — the agent runtime is in *your* VNet) |
| 🟧 Orange | **Private Endpoint / DNS** — every PE in this template is yours |
| 🟩 Green | **Identity / RBAC** — managed identities and role assignments |

There is **no grey path** — the entire architecture is private. If you ever see a "public internet" arrow, that's a bug.

---

## 1. Solution context — what did we deploy and why?

The big picture. One VNet, all PEs in your subnet, the agent compute lives in *your* delegated subnet (this is what makes it "BYO"). Foundry's control plane is the only Microsoft-managed piece — and it's reached through a PE too.

```mermaid
flowchart TB
  USER(("👤 You<br/>(laptop)"))

  subgraph YOUR["🟦 Your VNet — vnet-PREFIX (10.0.0.0/16)"]
    direction TB

    subgraph SNET_PE["snet-pe — 10.0.1.0/24"]
      PE_FND["pep-foundry"]:::pe
      PE_SRCH["pep-search"]:::pe
      PE_COSMOS["pep-cosmos"]:::pe
      PE_BLOB["pep-blob"]:::pe
      PE_AMPLS["pep-ampls"]:::pe
    end

    subgraph SNET_AGENT["snet-agent — 10.0.4.0/24<br/>(delegated Microsoft.App/environments)"]
      AGENT["Agent runtime<br/>Data Proxy<br/>Hosted / Prompt agent MicroVMs"]:::yours
    end

    subgraph SNET_VM["snet-vm — 10.0.2.0/24"]
      VM["Jumpbox VM<br/>(Win11 + system MI)"]:::yours
      NAT["NAT Gateway<br/>(egress for pip / git)"]:::yours
    end

    subgraph SNET_BAS["AzureBastionSubnet — 10.0.3.0/26"]
      BAS["Azure Bastion<br/>(browser RDP)"]:::yours
    end
  end

  subgraph BACKEND["🟦 Data plane — publicNetworkAccess: Disabled on every resource"]
    FND["Foundry account<br/>ais-PREFIX"]:::yours
    SRCH["AI Search<br/>srch-PREFIX"]:::yours
    COSMOS["Cosmos DB<br/>cosmos-PREFIX"]:::yours
    BLOB["Storage<br/>stPREFIX"]:::yours
    OBS["App Insights + LAW<br/>via AMPLS"]:::yours
  end

  USER ==HTTPS==> BAS
  BAS --> VM
  VM ==Foundry portal==> PE_FND
  AGENT ==AI Search tool==> PE_SRCH
  AGENT ==thread state==> PE_COSMOS
  AGENT ==files==> PE_BLOB
  AGENT -.telemetry.-> PE_AMPLS

  PE_FND --> FND
  PE_SRCH --> SRCH
  PE_COSMOS --> COSMOS
  PE_BLOB --> BLOB
  PE_AMPLS --> OBS

  classDef yours fill:#dbeafe,stroke:#1e3a8a,color:#000
  classDef pe fill:#fed7aa,stroke:#9a3412,color:#000
```

**Three things to notice:**

1. There is **one** VNet. The agent runtime lives in your `snet-agent`, not in a separate Microsoft VNet. That's the "BYO" essence.
2. Every arrow into a data resource passes through a 🟧 PE. There is no public internet path on any flow.
3. The jumpbox + Bastion exist purely so you can reach the *portal* privately — they're not in the agent's hot path.

---

## 2. Network topology — where does every packet go?

Same components, drawn to make the **DNS resolution path** explicit. This is the diagram you want during troubleshooting.

```mermaid
flowchart LR
  subgraph YOUR["🟦 Your VNet"]
    direction TB
    DNS_LINK["Private DNS Zones<br/>linked to VNet:<br/>• cognitiveservices<br/>• openai<br/>• services.ai<br/>• search.windows.net<br/>• documents.azure.com<br/>• blob.core.windows.net<br/>• monitor.azure.com (+3 AMPLS)"]:::pe

    subgraph AGENT_SUB["snet-agent (delegated)"]
      RUNTIME["Agent runtime"]:::yours
    end

    subgraph PE_SUB["snet-pe"]
      PEs["5 Private Endpoints<br/>(Foundry, Search, Cosmos, Blob, AMPLS)"]:::pe
    end

    subgraph VM_SUB["snet-vm"]
      JMP["Jumpbox"]:::yours
    end
  end

  RUNTIME -->|"1. resolve srch-PREFIX.search.windows.net"| DNS_LINK
  JMP -->|"1. resolve same FQDN"| DNS_LINK
  DNS_LINK -->|"2. returns 10.0.1.x (PE IP)"| RUNTIME
  DNS_LINK -->|"2. returns 10.0.1.x (PE IP)"| JMP
  RUNTIME -->|"3. TCP to 10.0.1.x"| PEs
  JMP -->|"3. TCP to 10.0.1.x"| PEs
  PEs -->|"4. through MS backbone"| TARGETS

  subgraph TARGETS["🟦 Data resources (no public IP)"]
    T1["Search / Cosmos / Storage / Foundry / App Insights"]:::yours
  end

  classDef yours fill:#dbeafe,stroke:#1e3a8a,color:#000
  classDef pe fill:#fed7aa,stroke:#9a3412,color:#000
```

**Debugging tip:** if any consumer (`RUNTIME` *or* `JMP`) can't reach a backend, step through this diagram in order:

1. **DNS** — does `nslookup` return a `10.0.1.x` IP? If not, the private DNS zone isn't linked to your VNet.
2. **NSG** — does the source subnet allow outbound to PE subnet on the target port?
3. **PE state** — is the PE `Approved`? `az network private-endpoint show` will tell you.
4. **RBAC** — separate concern; covered in diagram #3.

---

## 3. Identity & RBAC chain — who is allowed to do what, in what order?

The two-phase RBAC dance is the most counter-intuitive part of the deployment. This diagram makes it linear.

```mermaid
flowchart TB
  subgraph PHASE1["Phase 1 — Pre-capabilityHost (set BEFORE capHost is created)"]
    direction LR
    PROJ_MI(("Project MI<br/>(system-assigned)")):::id
    PROJ_MI -->|Storage Blob Data Contributor| ST1["Storage account"]:::yours
    PROJ_MI -->|Cosmos DB Operator| CX1["Cosmos DB"]:::yours
    PROJ_MI -->|Search Index Data Contributor<br/>+ Search Service Contributor| SR1["AI Search"]:::yours
  end

  CAPHOST{{"capabilityHost provisioning<br/>(binds 3 connections to runtime)"}}:::id

  subgraph PHASE2["Phase 2 — Post-capabilityHost (granted AFTER caphost, needs the workspace GUID)"]
    direction LR
    PROJ_MI2(("Project MI<br/>(same identity)")):::id
    PROJ_MI2 -->|Storage Blob Data Owner<br/>ABAC: container LIKE '*-azureml-agent'| ST2["Storage account<br/>(scoped to agent containers)"]:::yours
    PROJ_MI2 -->|Cosmos SQL Data Contributor<br/>built-in role 0000...0002| CX2["Cosmos DB<br/>(data-plane RBAC)"]:::yours
  end

  PHASE1 --> CAPHOST
  CAPHOST --> PHASE2

  JMP_MI(("Jumpbox VM MI")):::id
  JMP_MI -->|Search Index Data Contributor<br/>Cognitive Services OpenAI User| SR2["AI Search + Foundry<br/>(for indexer script)"]:::yours

  classDef yours fill:#dbeafe,stroke:#1e3a8a,color:#000
  classDef id fill:#d1fae5,stroke:#047857,color:#000
```

**Why two phases?**

- **Phase 1 roles** must exist *before* `capabilityHost` is provisioned — Foundry validates that the project MI can read the BYO resources during caphost bootstrap. If they're missing, caphost hangs or fails.
- **Phase 2 roles** can only be granted *after* caphost completes — they reference the project's *workspace GUID*, which only comes into existence as a side effect of caphost provisioning. The ABAC condition on Storage scopes the project to its own containers (`<workspaceGuid>*-azureml-agent`), preventing cross-project blast radius.

The **Jumpbox MI** roles are entirely independent — they let the postprovision indexer script write to Search and call OpenAI without sharing the project's identity.

---

## 4. Request flow — what happens between prompt and answer?

A timeline view of one user message. Useful for explaining the system to someone who's never seen it.

```mermaid
sequenceDiagram
  autonumber
  actor U as You (jumpbox)
  participant Portal as Foundry portal<br/>ai.azure.com
  participant Proj as Foundry project
  participant Runtime as Agent runtime<br/>(snet-agent)
  participant Search as AI Search
  participant Cosmos as Cosmos DB
  participant Blob as Storage
  participant Model as gpt-4.1-mini

  U->>Portal: HTTPS via pep-foundry
  Portal->>Proj: POST /agents/{id}/runs
  Proj->>Runtime: dispatch (via capabilityHost binding)
  Runtime->>Cosmos: write new thread (project MI, through pep-cosmos)
  Runtime->>Search: AI Search tool query (through pep-search)
  Search-->>Runtime: top-k document chunks
  Runtime->>Blob: persist citations (through pep-blob)
  Runtime->>Model: chat completion (intra-account, no PE)
  Model-->>Runtime: streaming tokens
  Runtime-->>Proj: SSE
  Proj-->>Portal: stream
  Portal-->>U: rendered answer
```

**Where things typically break:**

| Step | Failure | Root cause |
|---|---|---|
| 1 | `nslookup` returns public IP | `privatelink.cognitiveservices.azure.com` zone not linked to VNet |
| 3 | "Invalid endpoint or connection failed" | `capabilityHost` missing or its 3 connections not bound |
| 4 | 403 from Cosmos | Phase 2 RBAC missing (Cosmos SQL Data Contributor) |
| 5 | 403 from Search | Phase 1 RBAC missing (Search Index Data Contributor on project MI) |
| 8 | model timeout | model quota / deployment SKU mismatch — *not* a network issue |

---

## Where these diagrams live (and how to keep them in sync)

- **Source of truth:** this file (`docs/diagrams.md`). All mermaid blocks render natively on GitHub — no images to maintain.
- The repo `README.md` embeds **diagram #1** inline and links here for #2–#4 so a quick reader gets the gist without scrolling through four diagrams.
- If you change the topology (new subnet, new PE, new connection), update **only this file**. The README link still works.
- The Managed VNet flavor has a parallel `docs/diagrams.md` with the same 4 diagrams — placing them side by side is the fastest way to grok the difference between the two flavors.
