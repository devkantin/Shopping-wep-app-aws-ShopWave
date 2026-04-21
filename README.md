<div align="center">

# 🛍️ ShopWave — Cloud-Native E-Commerce on AWS

**A production-ready, full-stack e-commerce application deployed on AWS with Terraform, GitLab CI/CD, and enterprise DevSecOps practices.**

[![Pipeline](https://img.shields.io/badge/CI%2FCD-GitLab-FC6D26?logo=gitlab&logoColor=white)](https://gitlab.com/engineer-lab-group/Engineer-LAB-project)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Backend-Python%203.11-3776AB?logo=python&logoColor=white)](https://python.org)
[![Flask](https://img.shields.io/badge/Framework-Flask-000000?logo=flask&logoColor=white)](https://flask.palletsprojects.com/)
[![Coverage](https://img.shields.io/badge/Test%20Coverage-90%25-brightgreen)](https://gitlab.com/engineer-lab-group/Engineer-LAB-project)

</div>

---

## 📸 Architecture Overview

![ShopWave AWS Architecture](docs/architecture.png)

> See [`docs/architecture.html`](docs/architecture.html) for the full interactive diagram.

---

## 🏗️ Infrastructure at a Glance

```
Internet → Route 53 → ALB (Public Subnets AZ-a/b)
                        ↓
              EC2 Auto Scaling Group (Private App Subnets AZ-a/b)
                        ↓
              RDS MySQL 8.0 (Private DB Subnets AZ-a/b)
```

| Layer | Service | Detail |
|-------|---------|--------|
| DNS / CDN | AWS ALB | Application Load Balancer across 2 AZs |
| Compute | EC2 + ASG | t3.micro, min 1 / max 4, CPU-based scaling |
| Database | RDS MySQL 8.0 | db.t3.micro, private subnet, encrypted |
| Storage | S3 | App package delivery to EC2 via IAM role |
| Networking | VPC | 3-tier: public / private-app / private-db |
| Egress | NAT Gateway | Private EC2 outbound internet access |
| Security | Security Groups | ALB → EC2 → RDS, no SSH from internet |

---

## 🚀 Features

- **Dynamic storefront** — 12 products across 4 categories with live search, filters, cart
- **Customer accounts** — Sign-up / login with bcrypt password hashing stored in RDS
- **Order management** — Multi-item checkout, order history per customer
- **Auto Scaling** — CloudWatch CPU alarm scales EC2 fleet at 70% threshold
- **Zero-downtime deploys** — ASG rolling update via GitLab CI/CD

---

## 🗂️ Project Structure

```
shopwave-ecommerce/
├── app/
│   ├── app.py              # Flask API — models, routes, seed data
│   ├── requirements.txt    # Python dependencies
│   ├── static/             # CSS, JS assets
│   └── templates/
│       └── index.html      # Bootstrap 5 + vanilla JS frontend
├── terraform/
│   ├── main.tf             # Provider, locals, AMI data source
│   ├── vpc.tf              # 3-tier VPC, subnets, NAT Gateway, route tables
│   ├── ec2.tf              # S3 bucket, IAM, launch template, ASG, CloudWatch
│   ├── alb.tf              # ALB, target group, listener
│   ├── rds.tf              # RDS MySQL subnet group + instance
│   ├── security_groups.tf  # ALB / EC2 / RDS security groups
│   ├── variables.tf        # Typed input variables
│   ├── outputs.tf          # ALB DNS, RDS endpoint, S3 bucket
│   └── user_data.sh        # EC2 bootstrap: install, configure, start app
├── tests/
│   ├── conftest.py         # pytest fixtures (SQLite in-memory)
│   └── test_app.py         # 20 tests — API, auth, orders
├── .gitlab-ci.yml          # 6-stage CI/CD pipeline
├── .pre-commit-config.yaml # antonbabenko/pre-commit-terraform hooks
├── .tflint.hcl             # TFLint AWS ruleset config
├── .checkov.yaml           # Checkov security scan config
└── docs/
    └── architecture.html   # Interactive AWS architecture diagram
```

---

## 🔄 CI/CD Pipeline

```
┌─────────┐  ┌──────────────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│  test   │→ │      lint        │→ │ validate │→ │   plan   │→ │   cost   │→ │  deploy  │
│         │  │ tflint + checkov │  │  tf fmt  │  │ tf plan  │  │infracost │  │ (manual) │
│ pytest  │  │                  │  │ tf valid │  │          │  │          │  │ tf apply │
│ 90% cov │  │                  │  │          │  │          │  │          │  │          │
└─────────┘  └──────────────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
```

| Stage | Tool | Purpose |
|-------|------|---------|
| **test** | pytest + pytest-cov | 20 unit tests, 90% coverage, Cobertura report |
| **lint** | TFLint (AWS ruleset) | Terraform best-practice rules |
| **lint** | Checkov | 96+ security checks across all `.tf` files |
| **validate** | terraform validate + fmt | HCL syntax and canonical formatting |
| **plan** | terraform plan | Preview infrastructure changes |
| **cost** | Infracost | Monthly AWS cost estimate before deploy |
| **deploy** | terraform apply | Manual gate — one-click deploy to AWS |

---

## 🔐 Security Highlights

- EC2 instances in **private subnets** — no direct internet exposure
- RDS in **isolated private DB subnets** — reachable only from EC2 SG
- **No SSH** open to internet — use AWS Systems Manager Session Manager
- **IAM least-privilege** — EC2 role has `s3:GetObject` on the app bucket only
- Passwords **bcrypt-hashed** before storage in RDS
- DB credentials injected via **environment file** (600 permissions), never in code

---

## 🛠️ Local Development

### Prerequisites
- Python 3.11+
- Terraform 1.6+
- AWS CLI configured

### Run tests
```bash
cd shopwave-ecommerce
pip install -r app/requirements.txt pytest pytest-cov
TESTING=1 pytest tests/ -v --cov=app --cov-report=term-missing
```

### Deploy to AWS
```bash
cd terraform

# Create terraform.tfvars (gitignored)
echo 'db_password = "YourSecurePassword123!"' > terraform.tfvars

terraform init
terraform plan
terraform apply
```

### Access the app
```bash
terraform output app_url
# → http://<alb-dns-name>
```

---

## 📦 API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/api/products` | All products (optional `?category=electronics`) |
| GET | `/api/products/<id>` | Single product |
| POST | `/api/customers/register` | Register `{name, email, password}` |
| POST | `/api/customers/login` | Login `{email, password}` |
| POST | `/api/orders` | Place order `{customer_id, items:[{product_id, qty}]}` |
| GET | `/api/orders?customer_id=<id>` | Order history |

---

## 💰 Estimated Monthly Cost

| Resource | Cost |
|----------|------|
| EC2 t3.micro × 2 | ~$15 |
| RDS db.t3.micro | ~$15 |
| NAT Gateway | ~$33 |
| ALB | ~$17 |
| S3 | ~$0.01 |
| **Total** | **~$80/month** |

> Costs generated by Infracost on every pipeline run.

---

## 👤 Author

**Engineer AWS** — Cloud & DevOps Engineer

[![GitHub](https://img.shields.io/badge/GitHub-devkantin-181717?logo=github)](https://github.com/devkantin)
[![GitLab](https://img.shields.io/badge/GitLab-EngineerAWS-FC6D26?logo=gitlab)](https://gitlab.com/engineer-lab-group)

---

<div align="center">
<sub>Built with ❤️ using Flask · Terraform · AWS · GitLab CI/CD</sub>
</div>
