# Hello World on EKS — Docker, Terraform, Jenkins CI/CD

A minimal Flask "Hello, World!" app, containerized with Docker, deployed to
an autoscaling AWS EKS cluster provisioned by Terraform, behind an ALB,
with a Jenkins pipeline that builds → pushes to ECR → deploys with Helm.

A GitOps alternative (GitHub Actions + Argo CD) lives on the `gitops` branch.

---

## 1. Architecture Overview

```
Developer → git push (main) → Jenkins (build, test)
                                   │
                                   ▼
                          Docker build → push image → Amazon ECR
                                   │
                                   ▼
                    helm upgrade --install → EKS Cluster
                                   │
                    ┌──────────────┼───────────────┐
                    ▼              ▼               ▼
               Node 1 (pod)   Node 2 (pod)   Node 3/4 (pods, on demand)
                    │
                    ▼
        ALB (Application Load Balancer) ← Ingress
                    │
                    ▼
              End user (browser)
```

**Why each piece is there:**

| Component | Purpose |
|---|---|
| **Flask app** | The workload — a simple HTTP service returning "Hello, World!" |
| **Docker** | Packages the app + its dependencies into a portable, reproducible image |
| **Terraform** | Declaratively provisions the AWS infrastructure (VPC, EKS cluster, node group, ECR repo) so the environment is version-controlled and repeatable |
| **EKS** | Managed Kubernetes control plane; runs and schedules our app's containers |
| **Cluster Autoscaler** | Adds/removes EC2 worker nodes (1 → 4) based on pending pod demand |
| **HPA (Horizontal Pod Autoscaler)** | Adds/removes *pods* (up to 3 per node) based on CPU/memory usage |
| **ALB Ingress** | Routes external traffic from the internet into the cluster |
| **ECR** | Private Docker registry to store built images |
| **Jenkins** | CI/CD server — automates build, push, and deploy on every commit |
| **Helm** | Templated Kubernetes manifests, so `kubectl apply` becomes one parameterized command |

---

## 2. Repository Structure

```
.
├── app/                          # Flask application
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── terraform/                    # Infrastructure as Code for AWS
│   ├── providers.tf
│   ├── variables.tf
│   ├── vpc.tf
│   ├── eks.tf
│   ├── autoscaler.tf
│   └── outputs.tf
├── helm/hello-world-app/         # Helm chart for the app
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── hpa.yaml
│       └── ingress.yaml
├── jenkins/
│   └── Jenkinsfile               # CI/CD pipeline definition
├── .github/workflows/ci.yml      # (gitops branch) GitHub Actions CI
├── argocd/application.yaml       # (gitops branch) Argo CD bootstrap manifest
└── README.md
```

---

## 3. Prerequisites

Install these locally before you start:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (`aws configure` with an IAM user that has admin or EKS/EC2/IAM/ECR permissions)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.x
- [Docker](https://docs.docker.com/get-docker/)
- A Jenkins server (see Section 6) — can be run locally in Docker for learning purposes, or on an EC2 instance
- A GitHub account and a **private** repository for this project

---

## 4. Step-by-Step: Provision the Infrastructure

### 4.1 Clone and initialize

```bash
git clone <your-private-repo-url>
cd <repo-name>/terraform
terraform init
```

`terraform init` downloads the AWS/Kubernetes/Helm provider plugins and the
VPC/EKS community modules referenced in the `.tf` files.

### 4.2 Review the plan

```bash
terraform plan
```

This shows you every resource Terraform is about to create — VPC, subnets,
NAT gateway, EKS cluster, managed node group, ECR repo, and the two Helm
releases (Cluster Autoscaler, ALB Controller) — **without** creating anything
yet. Always read this before applying.

### 4.3 Apply

```bash
terraform apply
```

Type `yes` to confirm. This takes **15–20 minutes** (EKS control plane
provisioning is slow). At the end, Terraform prints outputs including your
ECR repository URL and the `aws eks update-kubeconfig` command.

### 4.4 Point kubectl at the new cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name hello-world-eks
kubectl get nodes
```

You should see **1 node** in `Ready` state — that's the `desired_size = 1`
baseline from `variables.tf`. The Cluster Autoscaler will add up to 3 more
only when pods can't be scheduled on the existing node(s).

### 4.5 Install the Metrics Server (required for HPA)

The Horizontal Pod Autoscaler needs CPU/memory metrics, which EKS doesn't
expose by default:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

## 5. Step-by-Step: Build and Deploy the App Manually (first time / sanity check)

Before wiring up Jenkins, it's worth doing one deploy by hand so you
understand what the pipeline automates:

```bash
# 1. Build and tag the image
cd app
docker build -t hello-world-app .

# 2. Authenticate Docker to your ECR repo (URL from terraform output)
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# 3. Tag and push
docker tag hello-world-app:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/hello-world-eks-app:v1
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/hello-world-eks-app:v1

# 4. Deploy with Helm
cd ../helm
helm upgrade --install hello-world-app ./hello-world-app \
  --set image.repository=<account-id>.dkr.ecr.us-east-1.amazonaws.com/hello-world-eks-app \
  --set image.tag=v1

# 5. Watch it come up
kubectl get pods -w
kubectl get ingress hello-world-app
```

The `ingress` command's `ADDRESS` column will show the ALB's public DNS
name once AWS finishes provisioning it (~2–3 minutes). Open that URL in a
browser — you should see the JSON `{"message": "Hello, World!", ...}`.

---

## 6. Step-by-Step: Set Up Jenkins

### 6.1 Run Jenkins (quick option for learning: Docker)

```bash
docker run -d --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
```

Get the initial admin password:

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Browse to `http://localhost:8080`, unlock Jenkins, and install suggested
plugins plus: **Docker Pipeline**, **Amazon ECR**, **AWS Steps**, **Pipeline
AWS Steps**, **Kubernetes CLI**.

> For a "real" deployment (not just learning), run Jenkins on an EC2
> instance or in the cluster itself, so it has native network access to AWS.

### 6.2 Configure credentials

In **Manage Jenkins → Credentials**, add:
- `aws-creds` — AWS access key/secret (or use an IAM instance role if Jenkins runs on EC2)
- `aws-account-id` — Secret text credential with your 12-digit AWS account ID

### 6.3 Create the pipeline job

- New Item → Pipeline
- Under **Pipeline**, choose "Pipeline script from SCM"
- SCM: Git → your repo URL + credentials (for a private repo, use a GitHub
  personal access token)
- Script Path: `jenkins/Jenkinsfile`

### 6.4 What the pipeline does (`jenkins/Jenkinsfile`)

1. **Checkout** — pulls the latest code from GitHub
2. **Build Docker Image** — `docker build` on `app/Dockerfile`
3. **Login & Push to ECR** — authenticates via AWS CLI, pushes the image
   tagged with the Jenkins build number and `latest`
4. **Configure kubectl** — points the Jenkins agent's kubectl at the EKS cluster
5. **Deploy with Helm** — `helm upgrade --install`, passing in the new image tag
6. **Verify Rollout** — waits for the deployment to become healthy and
   prints the ALB's public hostname

Trigger a build (manually, or set up a GitHub webhook so every push to
`main` triggers it automatically) and watch the console output.

---

## 7. How Autoscaling Works (talking point for your presentation)

There are **two independent autoscalers** working together:

1. **Cluster Autoscaler (node-level)** — if pods can't be scheduled because
   existing nodes are full, it asks AWS to launch another `t3.small`
   instance, up to `node_max_size = 4`. If nodes sit idle, it scales back
   down to `node_min_size = 1`.
2. **HPA (pod-level)** — watches CPU/memory usage of the app's pods. Once
   average utilization crosses **50%**, it creates more pod replicas (up to
   3 per node × 4 nodes = 12 total). Those new pods, if unschedulable on
   existing capacity, are what trigger the Cluster Autoscaler in turn.

This two-layer design means the app can absorb both traffic spikes (more
pods) and sustained growth (more nodes), while costing almost nothing
(1 small node) at idle.

---

## 8. GitOps Alternative (`gitops` branch)

The `gitops` branch replaces Jenkins with:

- **GitHub Actions** (`.github/workflows/ci.yml`) — builds the Docker
  image and pushes to ECR on every push to `gitops`, then commits the new
  image tag into `helm/hello-world-app/values.yaml`.
- **Argo CD** (`argocd/application.yaml`) — a Kubernetes controller running
  inside the cluster that continuously watches the Git repo. When it sees
  the updated `values.yaml`, it automatically syncs the cluster to match —
  no external system ever pushes credentials or `kubectl` commands into the
  cluster. This "pull-based" model is the core idea behind GitOps.

To try it:

```bash
git checkout -b gitops
# Bootstrap Argo CD into the cluster (one-time):
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd/application.yaml
```

From then on, every push to `gitops` → GitHub Actions builds & pushes the
image → Argo CD notices the Git change → cluster auto-updates.

---

## 9. Explanation of the Terraform Code

- **`vpc.tf`** — uses the official `terraform-aws-modules/vpc` module to
  create a VPC with public subnets (for the ALB) and private subnets (for
  worker nodes), a NAT gateway so private subnets can reach the internet
  for image pulls, and the specific tags EKS/ALB need for auto-discovery.
- **`eks.tf`** — uses `terraform-aws-modules/eks` to create the EKS control
  plane and a managed node group sized by `node_min_size` /
  `node_max_size` / `node_instance_type` (variables.tf). Also creates the
  ECR repository the pipeline pushes images to.
- **`autoscaler.tf`** — installs the Cluster Autoscaler and AWS Load
  Balancer Controller as Helm releases directly from Terraform, so the
  cluster is fully functional immediately after `terraform apply` — no
  manual `helm install` steps needed for cluster add-ons.
- **`variables.tf` / `outputs.tf`** — all the tunable knobs (region, node
  count, instance type) and the values you need afterward (cluster name,
  ECR URL, the `update-kubeconfig` command).

---

## 10. Cleaning Up (avoid AWS charges)

```bash
helm uninstall hello-world-app
cd terraform
terraform destroy
```

Always double-check the AWS Console afterward — orphaned ALBs, NAT
gateways, or EBS volumes are the most common source of surprise billing.

---

## 11. Known Simplifications (be ready to discuss these when presenting)

- IAM permissions for the Cluster Autoscaler and ALB Controller are
  simplified here for learning purposes. In production, each would get a
  dedicated IAM role scoped via IRSA (IAM Roles for Service Accounts)
  rather than broader permissions.
- `single_nat_gateway = true` saves cost for a learning project; production
  environments typically run one NAT gateway per AZ for high availability.
- Terraform state is local by default; for team use, migrate to an S3
  backend with DynamoDB locking (commented out in `providers.tf`).

---

## 12. Deployed Application URL

_Fill this in after deployment:_

```
## 12. Deployed Application URL

http://k8s-default-hellowor-1fc774817a-1510824594.us-east-1.elb.amazonaws.com