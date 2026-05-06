# Scalable-Disk-Monitoring-Solution-for-EC2

**Ansible-based solution to monitor EC2 disk usage across multiple AWS accounts using CloudWatch Agent and centralized reporting.**


## Background

The enterprise operates in a multi-cloud environment (AWS, Azure, GCP) due to organic growth and acquisitions. Each cloud provider has multiple accounts/subscriptions/projects with hundreds of virtual machines (VMs). Leadership has asked for a monitoring solution to proactively detect low disk space, leveraging Ansible (already in use) wherever possible and considering cloud-native options only if they provide substantial benefits.

This document proposes a secure scalable disk usage monitoring solution for AWS.


## Problem Statement

1. Multiple AWS accounts, each hosting EC2 instances.
2. Risk of downtime from disk exhaustion.
3. Need for centralized monitoring and early detection, Alarming.
4. Leadership prefers existing Ansible stack unless cloud-native options provide significant benefits.


## Solution Approaches Considered

1. SSH-based Monitoring + Ansible

Approach: Use Ansible from a central control node to SSH into managed EC2 instances across multiple AWS accounts, runs df -h, parses output to collect disk usage metrics.

Challenges with this approach:

* Need port 22 open on all VMs (security risk)
* Need SSH keys distributed to 500+ machines
* Need VPC peering or Transit GW for private subnet instances
* Only checks when you run it - if disk fills between runs, you're blind
* If control node goes down => no monitoring at all

--

2. Systems manager (SSM) + Ansible based Monitoring

Approach: Use AWS Systems Manager to remotely execute disk usage commands on instances and collect disk metrics — no SSH access required.

Challenges:

* Requires SSM Agent on instances and an IAM instance role with SSM permissions. However, most modern EC2 AMIs ship with SSM Agent pre-installed, so this is rarely a blocker.
* Although this works without any installations, this needs to be invoked everytime via a cron job which might run 5-30 mins, but if any instance gets memory exhaust with in short span, this solution might fail in alerting the Administrators. [Major Drawback, not relaible for Production Env's]

* Still poll-based. Cron runs every 15 min? You have 14 minutes of blindness
* Control node is still a single point of failure
* At scale (500 VMs x 24 checks/day = 12000 SSM sessions) gets expensive
* This approach is better for on-demand checks, but not great as primary monitoring.

--

> [!IMPORTANT]
> Below is the choosen method for our implementation.

## 3. CloudWatch Agent + SSM based monitoring

![Dashboard](aws_architecture_cross_account_disk_monitoring.png)

Approach: In this approach - CloudWatch Agent is installed on every target EC2 via Ansible (one-time deployment using SSM — no SSH needed). Once running, each agent independently collects disk metrics every 60 seconds and pushes them directly to the central monitoring account's CloudWatch using cross-account IAM role assumption. CloudWatch Alarms continuously evaluate these metrics against configured thresholds (75%/90%/95%) and automatically trigger SNS notifications to the ops team when breached. These benefits of no polling, no cron, no human in the loop made me stick to this approach of using CW Agent + SSM based monitoring solution.

In short it looks like:

> Install CW Agent on each EC2 → agent pushes disk metrics every 60s to a central monitoring account → CloudWatch alarms evaluate continuously → SNS fires alerts.

Advantages:

* Entirely managed on the cloud side → minimal operational overhead.
* Push-based and real-time → metrics flow continuously into CloudWatch.
* Secure → uses IAM and service-to-service communication, no inbound ports or SSH keys.
* Scales automatically across 100s of instances and accounts.
* Provides dashboards, alarms and logs natively in CloudWatch.

Challenges:

* Requires installation/configuration of CloudWatch Agent or equivalent to publish disk metrics.
* Limited flexibility if the same workflow needs to extend to non-AWS environments. 


## High level Data Flow

```

-----------------------------------------------------------------------
 > AWS Organization 
┌─────────────────────────────────────────────────────────────────────┐
│  MANAGEMENT ACCOUNT (5070XXXXXXXX)                                  │
│                                                                     │
│  ┌──────────────────┐       ┌──────────────────────────────────┐    │
│  │ Ansible Control  │       │ CloudWatch                        │   │
│  │ Node (EC2)       │       │                                   │   │
│  │                  │       │ Namespace: Custom/DiskMonitoring  │   │
│  │ - Ansible        │       │ Alarms: WARNING 75% / CRIT 90%    │   │
│  │ - boto3          │       │          EMERGENCY 95%            │   │
│  │ - aws cli        │       │                                   │   │
│  └────────┬─────────┘       │ SNS Topics:                       │   │
│           │                 │  - disk-monitoring-warning        │   │
│           │ SSM             │  - disk-monitoring-critical       │   │
│           │ (one-time       │  - disk-monitoring-emergency      │   │
│           │  deployment)    │                                   │   │
│           │                 │ Dashboard: single pane view       │   │
│           │                 └────────────────▲──────────────────┘   │
│           │                                  │                      │
├───────────┼──────────────────────────────────┼──────────────────────┤
│           │    CROSS-ACCOUNT BOUNDARY        │ PutMetricData        │
├───────────┼──────────────────────────────────┼──────────────────────┤
│           │                                  │                      │
│  SPOKE ACCOUNT -1  (8045XXXXXXXX)            │                      │
│           │                                  │                      │
│           ▼                                  │                      │
│   ┌──────────────┐  ┌──────────────┐  ┌──────┴───────┐              │
│   │ EC2 (Prod DB)│  │ EC2 (App)    │  │ EC2 (Web)    │              │
│   │              │  │              │  │              │              │
│   │ [CW Agent]   │  │ [CW Agent]   │  │ [CW Agent]   │              │
│   │ push q60s ───┼──┼──────────────┼──┼──────────────┘              │
│   └──────────────┘  └──────────────┘  └──────────────┘              │
│                                                                     │
│  IAM Roles:                                                         │
│  - DiskMonitoringRole (for Ansible cross-account access)            │
│  - DiskMonitoring-EC2-SSM-CW (instance profile on each EC2)         │
└─────────────────────────────────────────────────────────────────────┘
├───────────┼──────────────────────────────────┼──────────────────────┤
│              SPOKE ACCOUNT-2  (3645XXXXXXXX)                        |
├───────────┼──────────────────────────────────┼──────────────────────┤
├───────────┼──────────────────────────────────┼──────────────────────┤
│              SPOKE ACCOUNT-3  (3178XXXXXXXX)                        |
├───────────┼──────────────────────────────────┼──────────────────────┤

└─────────────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Ansible assumes role** into spoke account via `aws_profile` in dynamic inventory
2. **Dynamic inventory** discovers all running EC2s automatically (no hardcoded IPs)
3. **Ansible deploys CW Agent** via SSM (no SSH needed)
4. **CW Agent config** has a `role_arn` pointing to the monitoring account
5. **Agent pushes metrics** every 60s by assuming `CWAgentCrossAccountPush` role
6. **CloudWatch alarms** evaluate thresholds continuously
7. **SNS** sends email/SMS when alarm fires

After step 3, Ansible is no longer needed. The agents run autonomously.

## Prerequisites Identified (as per my replication)

- AWS CLI configured on control node
- Ansible 2.14+ with `amazon.aws` and `community.aws` collections
- Python 3.9+ with boto3
- IAM roles created (see `roles/iam_policies/`)
- SSM Agent running on target EC2s (pre-installed on Amazon Linux)
- EC2 instances need instance profile with `AmazonSSMManagedInstanceCore` + `CloudWatchAgentServerPolicy`

## Directory Structure

```
.
├── README.md
├── ansible.cfg
├── group_vars/
│   └── all.yml
├── inventories/
│   └── spoke_a.aws_ec2.yml
├── playbooks/
│   └── deploy_monitoring.yml
├── roles/
│   ├── ssm_verify/
│   │   └── tasks/main.yml
│   ├── cloudwatch_agent/
│   │   ├── tasks/main.yml
│   │   ├── templates/cw_agent_config.json.j2
│   │   └── handlers/main.yml
│   └── iam_policies/
│       ├── control_node_role.json
│       ├── cw_push_role.json
│       ├── spoke_monitoring_role.json
│       └── ec2_instance_profile.json
├── scripts/
│   ├── setup_control_node.sh
│   ├── provision_sns.sh
│   └── create_alarms.sh
└── images/
    ├── architecture.png
    └── dashboard.png
```

## Setup

### 1. Bootstrap the control node

```bash
bash scripts/setup_control_node.sh
```

This installs ansible, boto3, aws collections, etc.

### 2. Configure cross-account access

Add this to `~/.aws/config` on the control node:

```ini
[profile spoke-a]
role_arn = arn:aws:iam::8045XXXXXXXX:role/DiskMonitoringRole
credential_source = Ec2InstanceMetadata
region = us-east-1
```

Verify it works:
```bash
aws sts get-caller-identity --profile spoke-a
```

Should show account `8045XXXXXXXX`.

### 3. Test inventory discovery

```bash
ansible-inventory --graph
```

### 4. Create SNS topics

```bash
bash scripts/provision_sns.sh your-email@company.com
```

Check email and confirm all 3 subscription links.

### 5. Deploy CW Agent to all instances

```bash
ansible-playbook playbooks/deploy_monitoring.yml
```

### 6. Wait ~5 min, verify metrics are flowing

```bash
aws cloudwatch list-metrics --namespace "Custom/DiskMonitoring" --region us-east-1
```

### 7. Create alarms

```bash
bash scripts/create_alarms.sh
```

## IAM Roles Required

### Management Account (5070XXXXXXXX)

**ControlNodeRole** (attached to control node EC2):
- `sts:AssumeRole` → spoke account's DiskMonitoringRole
- `sns:CreateTopic`, `sns:Subscribe`, `sns:Publish`
- `cloudwatch:PutMetricAlarm`, `cloudwatch:PutDashboard`, `cloudwatch:ListMetrics`

**CWAgentCrossAccountPush** (CW agents from spoke accounts assume this):
- Trust: `arn:aws:iam::8045XXXXXXXX:role/DiskMonitoring-EC2-SSM-CW`
- Permissions: `cloudwatch:PutMetricData`, `cloudwatch:GetMetricData`

### Spoke Account (8045XXXXXXXX)

**DiskMonitoringRole** (Ansible assumes this for discovery + SSM):
- Trust: `arn:aws:iam::5070XXXXXXXX:role/ControlNodeRole`
- Permissions: `ec2:DescribeInstances`, `ssm:SendCommand`, `ssm:GetCommandInvocation`

**DiskMonitoring-EC2-SSM-CW** (instance profile on each EC2):
- Managed: `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`
- Inline: `sts:AssumeRole` → `arn:aws:iam::5070XXXXXXXX:role/CWAgentCrossAccountPush`

All policy JSONs are in `roles/iam_policies/`.

## Results

### Inventory Discovery
```
$ ansible-inventory --graph
@all:
  |--@aws_ec2:
  |  |--i-0a1b2c3d4e5f60001
  |  |--i-0a1b2c3d4e5f60002
  |  |--i-0a1b2c3d4e5f60003
  |--@name_prod_db_01:
  |  |--i-0a1b2c3d4e5f60001
  |--@name_app_server_01:
  |  |--i-0a1b2c3d4e5f60002
  |--@name_web_frontend_01:
  |  |--i-0a1b2c3d4e5f60003
```


### Metrics Verified
```
$ aws cloudwatch list-metrics --namespace "Custom/DiskMonitoring" --region us-east-1 \
  --query "Metrics[].{Metric:MetricName,Instance:Dimensions[?Name=='InstanceId'].Value|[0]}" \
  --output table

---------------------------------------------------
|                   ListMetrics                    |
+--------------------+----------------------------+
|      Instance      |         Metric             |
+--------------------+----------------------------+
| i-0a1b2c3d4e5f60001|  disk_used_percent        |
| i-0a1b2c3d4e5f60001|  disk_free                |
| i-0a1b2c3d4e5f60001|  mem_used_percent         |
| i-0a1b2c3d4e5f60002|  disk_used_percent        |
| i-0a1b2c3d4e5f60002|  disk_free                |
| i-0a1b2c3d4e5f60003|  disk_used_percent        |
| i-0a1b2c3d4e5f60003|  disk_free                |
| i-0a1b2c3d4e5f60003|  mem_used_percent         |
+--------------------+----------------------------+
```

### Output Report

* "Show me all instances and their current disk usage"
```
for id in $(aws cloudwatch list-metrics --namespace "Custom/DiskMonitoring" \
  --metric-name "disk_used_percent" --region us-east-1 \
  --query "Metrics[].Dimensions[?Name=='InstanceId'].Value|[]" \
  --output text | sort -u); do

  usage=$(aws cloudwatch get-metric-statistics \
    --namespace "Custom/DiskMonitoring" \
    --metric-name "disk_used_percent" \
    --dimensions Name=InstanceId,Value=$id Name=path,Value=/ \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 --statistics Average --region us-east-1 \
    --query "Datapoints.Average" --output text)

  echo "$id → ${usage}%"
done

>> Output :

i-0a1b2c3d4e5f60001 → 34.2%
i-0a1b2c3d4e5f60002 → 61.8%
i-0a1b2c3d4e5f60003 → 78.1%

```

## Key Design Decisions

1. **Why aws_profile instead of assume_role in inventory?**
   The inventory plugin's `assume_role` parameter has known issues in some versions. Using `aws_profile` with `credential_source = Ec2InstanceMetadata` delegates the role assumption to boto3 natively - much more reliable.

2. **Why treat_missing_data = breaching?**
   If an agent stops reporting (instance crash, agent failure, network issue), we want the alarm to fire, not go silent. Better to get a false positive than miss a real outage.

3. **Why push to a central account?**
   Single pane of glass. All metrics from all spoke accounts land in one place. One dashboard, one set of alarms, one team to manage.

## Adding More Accounts

1. Create `DiskMonitoringRole` and `DiskMonitoring-EC2-SSM-CW` in the new account
2. Add trust entry to `CWAgentCrossAccountPush` in management account
3. Add profile to `~/.aws/config`
4. Create `inventories/spoke_b.aws_ec2.yml` pointing to new profile
5. Run `ansible-playbook playbooks/deploy_monitoring.yml`

Takes about 10 minutes per new account.
