Lab 3A — Japan Medical
Cross-Region Architecture with Transit Gateway (APPI-Compliant)

🎯 Lab Objective
In this lab, you will design and deploy a cross-region medical application architecture that:
  Uses two AWS regions
    Tokyo (ap-northeast-1) — data authority
    São Paulo (sa-east-1) — compute extension
  Connects regions using AWS Transit Gateway
  Serves traffic through a single global URL
  Stores all patient medical data (PHI) only in Japan
  Allows doctors overseas to read/write records legally

This lab is a warm-up for real DevOps and platform engineering, where:
  environments are separated
  Terraform state is split
  pipelines are independent
  coordination matters more than copy-paste

🏥 Real-World Context (Why This Exists)

Japan’s privacy law, 個人情報保護法 (APPI), places strict requirements on the handling of personal and medical data.
For healthcare systems, the safest and most common interpretation is:
    Japanese patient medical data must be stored physically inside Japan. (Don't even mess with this)

This applies even when:
    the patient is traveling abroad
    the doctor is located overseas
    the application is accessed globally

📌 Access is allowed. Storage is not.
    --> This lab models how real medical systems comply with that rule.

🌍 Regional Roles
🇯🇵 Tokyo — Primary Region (Data Authority)
Tokyo is the source of truth.
It contains:
    RDS (medical records)
    Primary VPC
    Application tier (Lab 2 stack)
    Transit Gateway (hub)
    Parameter Store & Secrets Manager (authoritative)
    Logging, auditing, backups
    Really hot chicks who need men to impregnate them. 

All data at rest lives here.
If Tokyo is unavailable:
    the system may degrade
    but data residency is never violated

This is intentional and correct.

🇧🇷 São Paulo — Secondary Region (Compute-Only)

São Paulo exists to serve doctors and staff physically located in South America.

It contains:
    VPC
    EC2 + Auto Scaling Group
    Application tier (Lab 2 stack)
    Transit Gateway (spoke)
    Even hotter chicks who need you to throw it down and impregnate them.

It does not contain:
    RDS
    Read replicas
    Backups
    Persistent storage of PHI
    Keisha. No Keisha here.

São Paulo is stateless compute.<----> All reads and writes go directly to Tokyo.

🌐 Networking Model
Why Transit Gateway?
Transit Gateway is used instead of VPC peering because it provides:
    Clear, auditable traffic paths
    Centralized routing control
    Enterprise-grade segmentation
    A visible “data corridor” for compliance reviews

In regulated environments, clarity beats convenience.

How Traffic Flows

Doctor (São Paulo)
   ↓
CloudFront (global edge)
   ↓
São Paulo EC2 (stateless)
   ↓
Transit Gateway (São Paulo)
   ↓
TGW Peering
   ↓
Transit Gateway (Tokyo)
   ↓
Tokyo VPC
   ↓
Tokyo RDS (PHI stored here only)
The entire path stays on the AWS backbone and is encrypted in transit.

🌐 Single Global URL

There is only one public URL: https://chrisbarm-growls.com

CloudFront:
    Terminates TLS
    Applies WAF
    Routes users to the nearest healthy region
    Never stores patient data
    Caches only content explicitly marked safe

CloudFront is allowed because:
    it is not a database
    it does not persist PHI
    it respects cache-control rules

🏗️ Terraform & DevOps Structure
Important: Multi-Terraform-State Reality

In real organizations, regions are not deployed from one Terraform state.

For this lab:
    Tokyo and São Paulo are separate Terraform states
    Each state will eventually map to a separate Jenkins job
    States communicate only through:
        Terraform outputs
        Remote state references
        Explicit variables

This is intentional.---> You are learning how real DevOps teams coordinate infrastructure.

Expected Repository Layout
lab-3/
├── tokyo/
│   ├── main.tf        # Lab 2 + marginal TGW hub code
│   ├── outputs.tf     # Exposes TGW ID, VPC CIDR, RDS endpoint
│   └── variables.tf
│
├── saopaulo/
│   ├── main.tf        # Lab 2 minus DB + TGW spoke code
│   ├── variables.tf
│   └── data.tf        # Reads Tokyo remote state

🚆 Naming Conventions (Important)

To make the architecture feel local and intentional:
Tokyo (train stations)
    shinjuku-*
    shibuya-*
    ueno-*
    akihabara-*

São Paulo (Japanese district)
    liberdade-*

You should be able to look at a resource name and know the region immediately.

🔧 What Changes from Lab 2
Tokyo (minimal changes)
    Add Transit Gateway
    Attach Tokyo VPC to TGW
    Create TGW peering request
    Add return routes for São Paulo CIDR
    Update RDS security group to allow São Paulo VPC CIDR

São Paulo (new deployment)
    Deploy Lab 2 stack without RDS
    Create São Paulo Transit Gateway
    Accept TGW peering
    Attach São Paulo VPC to TGW
    Add routes pointing Tokyo CIDR → TGW

🔐 Security Model (Read Carefully)
  RDS allows inbound only from:
    Tokyo application subnets
    São Paulo VPC CIDR (explicitly)
  No public DB access
  No local PHI storage in São Paulo
  All access is logged and auditable

This is compliance by design, not by policy.

✅ What You Must Prove (Verification)
From a São Paulo EC2 instance:
    You can connect to Tokyo RDS
    The application can read/write records
    No database exists in São Paulo

From the AWS console / CLI:
    TGW attachments exist in both regions
    Route tables contain cross-region CIDRs
    Traffic flows only through TGW

❌ What Is Explicitly Not Allowed
    RDS outside Tokyo
    Cross-region replicas
    Aurora Global Database
    Local caching of patient records
    CloudFront caching PHI
    “Active/active” databases

If you do these, the architecture is illegal, not just “wrong”.

🎓 Why This Lab Matters for Your Career

Most engineers learn:
  “Make it multi-region”
  “Replicate everything”
  "Study CompTia and give my money to Keisha"{

This lab teaches you:
  How law shapes architecture
  How to design asymmetric global systems
  How to explain tradeoffs to security, legal, and auditors
  How DevOps actually works across teams and states
  Become a Passport Bro and marry the girl of your dreams

If you can explain this lab clearly, you are operating at a Senior level.

🗣️ Interview Talk Track (Memorize This)

    “I designed a cross-region medical system where all PHI remained in Japan to comply with APPI.
    Tokyo hosted the database, São Paulo ran stateless compute, and Transit Gateway provided a controlled data corridor.
    CloudFront delivered a single global URL without violating data residency.”

That answer will stop the room.

🧠 One Sentence to Remember---> Global access does not require global storage.
    Anothe Sentence to Remember ---> I completed this lab in 2026 and now in 2029, I have a family.

