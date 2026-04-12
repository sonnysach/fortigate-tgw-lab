# FortiGate + TGW + AWS Network Firewall Lab

Deploys a FortiGate-VM in AWS with TGW Connect (GRE + BGP) and a centralized Inspection VPC running AWS Network Firewall. This guide assumes you have never used Terraform or the AWS CLI before.

---

## Why This Lab Exists

Enterprise customers increasingly want to run their SD-WAN fabric into AWS the same way they run it everywhere else: terminate branches on a FortiGate, plug that FortiGate into the cloud network, and let workloads in AWS talk to on-prem sites through the same routing, policy, and visibility plane they already trust. At the same time, those customers have internal security teams mandating that all traffic — east-west between VPCs and north-south between AWS and the data center — pass through a central inspection point before reaching its destination.

Done right, these two requirements fit together cleanly. Done wrong, you end up with asymmetric routing, inspection bypasses, policy gaps, and finger-pointing between the network and security teams. As Fortinet SEs, we get asked to whiteboard this design constantly, and customers expect us to have working answers — not just architecture diagrams.

This lab exists so that any Fortinet SE can stand up the full design in under 15 minutes, break things on purpose, and walk into a customer meeting having actually built it. Reading a reference architecture is not the same as watching BGP come up between a FortiGate and a Transit Gateway, or watching a ping silently fail because appliance mode was off on the wrong attachment. Hands-on experience is what separates an SE who describes the design from one who owns it.

## What This Lab Builds

A minimal-but-complete version of the most common Fortinet-in-AWS hybrid design pattern:

1. **A FortiGate-VM in a dedicated "SDWAN VPC"**, acting as the cloud-side SD-WAN hub. In a real deployment it would terminate IPsec tunnels from on-prem FortiGates at branches and data centers; here we fake the on-prem side with a test EC2 so we can focus on the AWS-side mechanics.

2. **An AWS Transit Gateway with a Connect attachment to the FortiGate.** Connect attachments are AWS's purpose-built mechanism for letting third-party network appliances participate in TGW routing as a BGP peer via a GRE tunnel. This is how the FortiGate learns about AWS VPC CIDRs and advertises on-prem CIDRs back into AWS — exactly like a CE router in an MPLS L3VPN.

3. **A centralized Inspection VPC running AWS Network Firewall (ANF)** with endpoints in two Availability Zones. All east-west spoke traffic and all north-south DC-to-AWS traffic is forced through ANF before reaching its destination. Appliance mode on the Inspection VPC's TGW attachment guarantees flow symmetry so stateful inspection works correctly.

4. **Two spoke VPCs with test EC2 instances**, to validate east-west traffic actually traverses ANF instead of short-cutting directly through the TGW.

5. **A three-route-table TGW design** that enforces the "force everything through inspection" policy using ingress-attachment-based routing (the TGW equivalent of VRF + PBR). Two of the three route tables contain a single static default route each; the third is populated entirely by BGP propagation. The asymmetry between associations and propagations is what makes the design work, and understanding it is the main educational goal of the lab.

**What the lab is not:** a production-ready reference architecture. There's no HA FortiGate pair, no real on-prem IPsec tunnel, no ADVPN, no centralized egress, only two spokes instead of five, and the ANF policy is deliberately permissive so you can get pings flowing before you start locking things down. Every one of these simplifications was a deliberate trade-off to keep the lab cheap (~$12/day), fast to stand up, and focused on the two things that actually matter: (1) watching BGP come up between a FortiGate and a TGW Connect attachment, and (2) proving that multi-route-table TGW routing actually forces traffic through inspection. Once you understand those two things, scaling to the full customer design is mechanical.

## How It Works (At a Glance)

1. **Terraform provisions the entire AWS environment** — four VPCs (SDWAN, Inspection, Spoke 1, Spoke 2), a Transit Gateway with three route tables, all attachments, the FortiGate-VM, AWS Network Firewall with a permissive starter policy, test EC2s, and a $50/month budget alert. Everything is in a single `terraform apply` so you can tear it all down just as easily with `terraform destroy`.

2. **You SSH into the FortiGate once after deployment and paste in a GRE tunnel + BGP neighbor config** from `fortigate-cli.txt`. Terraform intentionally does not configure the FortiGate itself — this step is where you actually learn how the FortiGate talks to the TGW, and it's the single most important hands-on exercise in the lab. You'll watch the BGP session come up and routes populate the Firewall RT automatically via propagation.

3. **You validate the design by sending pings** between spoke test EC2s and between the fake DC host and the spokes, confirming via ANF flow logs that every packet was inspected. Then, for bonus learning, you deliberately break appliance mode on the Inspection VPC attachment and watch return traffic drop because of asymmetric AZ hashing — the single most common production failure mode of this design.

4. **When you're done for the day, you destroy everything with one command.** No lingering resources, no surprise bills, nothing to clean up manually.

The goal is that by the end of a single afternoon, you've built the design end-to-end, watched it work, watched it break in the characteristic ways, and can confidently walk a customer through both the architecture and the failure modes from direct experience.

### Why Three Route Tables? (The Core Concept)

If you come from a traditional networking background, the fastest way to understand TGW is this: a TGW route table is a VRF, an association is an interface-to-VRF binding, and the whole multi-route-table design is just policy-based routing with a cloud paint job.

TGW's forwarding algorithm is two steps:

1. **Which route table do I use?** Answered by the association of the attachment the packet arrived on. Every attachment is associated with exactly one route table, and that association determines which table TGW consults for ingress traffic on that attachment.
2. **Where do I send it?** Answered by a longest-prefix-match on the destination IP in that table, which returns a next-hop attachment.

The powerful consequence: the same destination IP can be forwarded completely differently depending on which attachment it arrived on. A packet to `10.1.0.50` arriving on the Connect attachment hits the SDWAN RT and gets sent to Inspection. The exact same packet to `10.1.0.50` arriving on the Inspection attachment hits the Firewall RT and gets sent directly to Spoke 1. Same destination, different ingress, different outcome. That asymmetry is what makes service chaining through a central inspection point possible.

With that mental model in place, the three-table design almost writes itself:

- **SDWAN RT** — associated with the Connect attachment. Its only job is "force everything coming from the FortiGate through inspection." One static default route to the Inspection VPC attachment. Nothing propagated.
- **Spoke RT** — associated with both spoke VPC attachments. Its only job is "force everything coming from a spoke through inspection." One static default route to the Inspection VPC attachment. Nothing propagated. Critically, spoke CIDRs are deliberately not propagated into this table — if they were, longest-prefix-match would beat the default route and spoke-to-spoke traffic would bypass ANF entirely. Keeping this table empty is what enforces east-west inspection.
- **Firewall RT** — associated with the Inspection VPC attachment. This is the only "smart" table in the design. After ANF inspects a packet and hands it back to TGW, the Firewall RT decides where it actually goes: to a spoke, or back out through the FortiGate to the DC. All routes in this table are populated via propagation — spoke CIDRs come from the spoke attachments, and the DC CIDR comes dynamically via BGP from the FortiGate over the Connect attachment. No static routes needed.

The design pattern you should remember is **"dumb ingress tables + one smart post-inspection table."** Two tables with a single static default route each, and one table populated entirely by BGP propagation. The rule of thumb is: topology belongs in propagation, policy belongs in static routes. Spoke CIDRs and DC CIDRs are topology (learned from peers), so they're propagated. Default routes forcing traffic to inspection are policy (an enforcement decision you're making), so they're static.

The same attachment often plays different roles in different tables. The spoke attachments are associated with the Spoke RT (ingress decisions) but propagated into the Firewall RT (egress destinations after inspection). Association and propagation are completely independent settings — an attachment can be propagated into tables it isn't associated with, and that's the normal case, not a special one.

**One last critical piece: appliance mode.** Because the Inspection VPC has ANF endpoints in two AZs, both actively processing traffic, TGW needs to deterministically send the forward and return halves of every flow to the same AZ endpoint — otherwise ANF's stateful engine sees only half the flow and drops the return traffic. Appliance mode (enabled on the Inspection VPC's TGW attachment) uses a symmetric 5-tuple hash to guarantee this. It's the one setting in TGW that has no traditional-networking analog, because traditional routers don't have AZs. Appliance mode is OFF on every other attachment in this lab (spokes, SDWAN VPC) because those attachments don't have the multi-AZ stateful appliance problem. Forgetting appliance mode is the #1 cause of "worked in testing, silently broke in production" incidents with this design, which is why one of the validation exercises in this lab is to deliberately turn it off and watch traffic break.

---

## Architecture

```
                    ┌──────────────┐
                    │  TGW (64512) │
          ┌─────────┤              ├──────────┐
          │  Connect │  3 Route    │ VPC      │
          │  (GRE)  │  Tables     │ Attach   │
          │         └──────┬───────┘          │
          ▼                ▼                  ▼
  ┌───────────────┐ ┌──────────────┐  ┌────────────┐
  │ SDWAN VPC     │ │ Inspection   │  │ Spoke VPCs │
  │ 10.10.0.0/16  │ │ VPC          │  │ 10.1.0.0/16│
  │               │ │ 10.200.0.0/16│  │ 10.2.0.0/16│
  │ ┌───────────┐ │ │ ┌──────────┐ │  │            │
  │ │ FortiGate │ │ │ │ AWS NFW  │ │  │ test EC2s  │
  │ │ (65000)   │ │ │ │ (ANF)    │ │  │            │
  │ └───────────┘ │ │ └──────────┘ │  └────────────┘
  │ ┌───────────┐ │ └──────────────┘
  │ │ Fake DC   │ │
  │ │ 10.100/16 │ │
  │ └───────────┘ │
  └───────────────┘
```

## TGW Route Table Design

| Route Table | Associated With | Routes |
|-------------|----------------|--------|
| **SDWAN RT** | Connect attachment | Static 0.0.0.0/0 → Inspection VPC |
| **Spoke RT** | Spoke 1 + Spoke 2 VPC attachments | Static 0.0.0.0/0 → Inspection VPC |
| **Firewall RT** | Inspection VPC attachment | Propagated: Spoke 1, Spoke 2, Connect (BGP) |

---

## Step 0: Install the Tools

You need two command-line tools: the **AWS CLI** (talks to your AWS account) and **Terraform** (reads the `.tf` files and creates the infrastructure).

### macOS (using Homebrew)

If you don't have Homebrew, install it first by pasting this into Terminal:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then install both tools:

```bash
brew install awscli terraform
```

### Windows

Download and run the installers from these links:
- AWS CLI: https://awscli.amazonaws.com/AWSCLIV2.msi
- Terraform: https://developer.hashicorp.com/terraform/install (download the Windows AMD64 zip, extract `terraform.exe`, and place it in a folder that's on your PATH, e.g. `C:\Windows\`)

### Verify installation

Open a new terminal window and run:

```bash
aws --version
terraform --version
```

Both should print a version number. If either says "command not found", close and reopen your terminal.

---

## Step 1: Log In to AWS

Terraform needs AWS credentials to create resources. Choose whichever method matches your setup.

### Option A: AWS IAM Identity Center (SSO) — most corporate accounts

If your organization uses AWS SSO (IAM Identity Center), you need two pieces of information from your SSO portal. Log into your portal in a browser, then click on your account and look for **"Access keys"** or **"Command line or programmatic access"**. That page will show you:

- **SSO start URL** (e.g. `https://mycompany.awsapps.com/start/#`)
- **SSO region** (e.g. `us-west-2`)

> **Important:** The SSO region is where your Identity Center lives, which is often *different* from the region where you'll deploy resources. Don't guess — copy it from the portal.

Run the one-time setup:

```bash
aws configure sso
```

| Prompt | Value |
|--------|-------|
| SSO session name | Any name you like (e.g. `my-sso`) |
| SSO start URL | Copy from your portal (include the `/#` if shown) |
| SSO region | Copy from your portal |
| SSO registration scopes | Press **Enter** to accept the default |

Your browser will open for authentication (MFA, etc.). After signing in, return to the terminal. It will list the AWS accounts and roles available to you. Pick the account you want to use, then set:

| Prompt | Value |
|--------|-------|
| CLI default client Region | `us-east-1` |
| CLI default output format | `json` |
| CLI profile name | Any name you like (e.g. `lab`) |

From now on, log in before any Terraform session:

```bash
aws sso login --profile lab
```

Then tell your terminal to use that profile:

```bash
export AWS_PROFILE=lab
```

> **Windows PowerShell users:** Use `$env:AWS_PROFILE = "lab"` instead.

### Option B: IAM access keys — personal accounts or non-SSO setups

If you have a regular IAM user with an Access Key ID and Secret Access Key:

```bash
aws configure
```

| Prompt | Value |
|--------|-------|
| AWS Access Key ID | Your access key |
| AWS Secret Access Key | Your secret key |
| Default region name | `us-east-1` |
| Default output format | `json` |

### Option C: Temporary credentials from SSO portal

If `aws configure sso` isn't working or you just want a quick way in, you can copy temporary credentials directly from your SSO portal. Log in, click your account, click **"Access keys"** or **"Command line or programmatic access"**, and choose **"Option 1: Set AWS environment variables"**. Copy-paste the three `export` lines into your terminal, then add the region:

```bash
export AWS_ACCESS_KEY_ID="paste_from_portal"
export AWS_SECRET_ACCESS_KEY="paste_from_portal"
export AWS_SESSION_TOKEN="paste_from_portal"
export AWS_DEFAULT_REGION="us-east-1"
```

> **Note:** These credentials expire after a few hours. You'll need to repeat this step if your session times out.

### Verify

Whichever option you chose, verify it works:

```bash
aws sts get-caller-identity
```

You should see your account number and role/user. If you get an error, your credentials are expired or misconfigured — redo the login step above.

---

## Step 2: Create an EC2 Key Pair

A key pair lets you SSH into the test EC2 instances. You only need to do this once.

```bash
aws ec2 create-key-pair \
  --key-name lab-key \
  --key-type rsa \
  --query "KeyMaterial" \
  --output text > lab-key.pem
```

Then lock down the file permissions (required for SSH to accept the key):

```bash
chmod 400 lab-key.pem
```

> **Windows users:** Skip `chmod`. Instead, right-click `lab-key.pem` → Properties → Security → Advanced → Disable inheritance → Remove all users except your own account.

Keep this file safe — you'll need it to SSH into instances later. Don't share it or commit it to Git.

---

## Step 3: Subscribe to the FortiGate AMI in AWS Marketplace

Terraform needs permission to launch the FortiGate AMI. This is a one-time step per AWS account.

1. Open https://aws.amazon.com/marketplace/pp/prodview-wory773oau6wq
2. Click **"View purchase options"** or **"Try for free"**
3. Accept the terms and subscribe (you won't be charged until you launch an instance)

> **Note:** If your work account restricts Marketplace subscriptions, ask your AWS admin to approve it, or request a BYOL license from our internal team. Set `deploy_fortigate = false` in `terraform.tfvars` to deploy everything else while you wait.

---

## Step 4: Find Your Public IP

The lab locks down SSH and management access to your IP address only. Run:

```bash
curl ifconfig.me
```

This prints your public IP (e.g., `203.0.113.42`). Write it down — you'll need it in the next step.

> **Note:** If you're on VPN, this returns your VPN exit IP. That's fine — just be aware that if you disconnect from VPN, you'll lose access and will need to update the config with your new IP.

---

## Step 5: Edit terraform.tfvars

Open the file `terraform.tfvars` in any text editor and replace the three `CHANGE_ME` values:

```hcl
# Set to true once you have the FortiGate BYOL license and Marketplace sub
deploy_fortigate = false

# The key pair name you created in Step 2
key_pair_name = "lab-key"

# Your public IP from Step 4, with /32 at the end
allowed_mgmt_cidrs = ["203.0.113.42/32"]

# Your email for AWS budget alerts (50%, 80%, 100% of $50/month)
budget_alert_email = "you@fortinet.com"
```

Save the file.

---

## Step 6: Deploy the Lab

Open your terminal, navigate to this folder, and run three commands:

```bash
cd /path/to/FortiGate-TGW-Terraform
```

**Initialize Terraform** — downloads the AWS provider plugins (run once, or after changing providers):

```bash
terraform init
```

You should see "Terraform has been successfully initialized!" in green.

**Preview what will be created** — this is a dry run, nothing is built yet:

```bash
terraform plan
```

Review the output. It will say something like "Plan: 45 to add, 0 to change, 0 to destroy." This tells you how many AWS resources Terraform will create.

**Apply** — this actually creates the resources in AWS:

```bash
terraform apply
```

Terraform will show the plan again and ask: `Do you want to perform these actions?` Type **yes** and press Enter.

This takes about 5–10 minutes (the Network Firewall is the slowest part). When it finishes, you'll see the outputs: IP addresses, SSH commands, etc.

To see all outputs including the FortiGate password:

```bash
terraform output -json
```

---

## Step 7: Test Connectivity

Once deployed, SSH into the spoke test EC2s using the key you created:

```bash
ssh -i lab-key.pem ec2-user@<spoke1_public_ip>
```

(Replace `<spoke1_public_ip>` with the actual IP from the Terraform output.)

From inside the spoke1 EC2, try pinging spoke2's private IP:

```bash
ping 10.2.1.x
```

If `deploy_fortigate = true` and you've configured BGP (Step 8), also try pinging the fake DC:

```bash
ping 10.100.0.1
```

---

## Step 8: Configure FortiGate GRE + BGP (only when deploy_fortigate = true)

This step is manual — Terraform sets up the EC2 instance but the GRE/BGP config needs to be pasted into the FortiGate CLI.

1. Log into FortiGate at the URL shown in `fortigate_mgmt_url` output (port 8443)
2. Username: `admin`, Password: from `terraform output fortigate_admin_password`
3. Open the CLI console (or SSH on port 2222)
4. Open the file `fortigate-cli.txt` in this repo
5. Replace the `<PLACEHOLDER>` values with the actual IPs from `terraform output -json`
6. Paste the commands into the FortiGate CLI
7. Verify BGP is up: `get router info bgp summary`

---

## Step 9: Clean Up (IMPORTANT!)

This lab costs approximately **$12/day**. When you're done testing, tear everything down:

```bash
terraform destroy
```

Type **yes** when prompted. This removes all AWS resources created by this config. Verify in the AWS Console (EC2, VPC, TGW sections) that everything is gone.

---

## Troubleshooting

**"command not found: terraform"** — Terraform isn't installed or isn't on your PATH. Reinstall per Step 0 and open a new terminal window.

**"Error: No valid credential sources found"** — Your AWS session expired. Run `aws sso login --profile fortinet-lab` again and make sure `AWS_PROFILE` is set.

**"Error: creating EC2 Instance: OptInRequired"** — You haven't subscribed to the FortiGate AMI in Marketplace. Complete Step 3, or set `deploy_fortigate = false`.

**"Error: UnauthorizedAccess"** — Your SSO role may not have sufficient permissions. Contact your AWS admin.

**"terraform plan" shows changes you didn't expect** — Someone else may have modified resources manually in the console. Run `terraform apply` to reconcile, or `terraform destroy` and start fresh.

**Can't SSH into test EC2** — Check that your current public IP matches what's in `allowed_mgmt_cidrs`. If you switched networks or VPN, your IP changed. Update `terraform.tfvars` and run `terraform apply`.

---

## Estimated Cost

~$12/day when all resources are running. The $50/month AWS Budget will email you at 50%, 80%, and 100%.

**Always run `terraform destroy` when you're done for the day.**

---

## File Reference

| File | What it does |
|------|-------------|
| `versions.tf` | Tells Terraform which AWS provider version to use |
| `variables.tf` | Defines all configurable inputs (CIDRs, instance types, etc.) |
| `vpc.tf` | Creates the 4 VPCs, their subnets, internet gateways, and route tables |
| `tgw.tf` | Creates the Transit Gateway, VPC attachments, Connect (GRE), and 3 route tables |
| `fortigate.tf` | Creates the FortiGate-VM EC2 instance, network interfaces, and security groups |
| `anf.tf` | Creates AWS Network Firewall with inspection policy and CloudWatch flow logs |
| `test_instances.tf` | Creates t3.micro test EC2s in each spoke VPC and the fake-DC in SDWAN VPC |
| `budget.tf` | Creates a $50/month AWS Budget with email alerts |
| `outputs.tf` | Displays IP addresses, SSH commands, and other info after deployment |
| `terraform.tfvars` | **Your config file** — edit this with your key pair, IP, and email |
| `fortigate-cli.txt` | GRE + BGP CLI commands to paste into the FortiGate after deployment |
