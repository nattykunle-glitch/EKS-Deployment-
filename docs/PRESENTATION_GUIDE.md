# Presentation Guide

Use this as a script/outline when you demo or present this project.

## 1. The problem (30 sec)
"I built a small web app and needed to deploy it in a way that's automated,
scalable, and reflects real production practice — not just running it on
one server."

## 2. The architecture (2 min)
Walk through the diagram in the README:
App → Docker → ECR → EKS → ALB → user, with Jenkins (or GitHub
Actions + Argo CD) automating the middle steps.

Say *why* each tool is there, not just *what* it is:
- "Docker so the app runs identically everywhere."
- "Terraform so the infrastructure is defined as code — reproducible, and
  I can tear it down and rebuild it exactly the same way."
- "EKS because I need something to actually run and heal the containers,
  and Kubernetes is the industry standard for that."
- "Jenkins to remove manual deploy steps — every push builds, tests, and
  ships automatically."

## 3. The two autoscaling layers (1–2 min) — good technical depth signal
Explain the distinction clearly, since it's easy to garble:
- **HPA** scales **pods** based on CPU/memory (up to 3 pods per node).
- **Cluster Autoscaler** scales **nodes** (EC2 instances) when pods can't
  fit anywhere (1 → 4 nodes).
- They work together: HPA creates more pods under load → if there's no
  room, Cluster Autoscaler adds a node → HPA's new pods land there.

## 4. Live or recorded demo (2–3 min)
1. Show `terraform apply` output (or a pre-recorded clip — it takes ~15 min live)
2. `kubectl get nodes` / `kubectl get pods`
3. Push a code change, show the Jenkins pipeline running through its stages
4. Refresh the ALB URL in a browser to show the new version deployed

## 5. GitOps alternative (1 min)
"I also implemented a second approach on a `gitops` branch, using GitHub
Actions and Argo CD instead of Jenkins. The key difference is *push* vs
*pull*: Jenkins pushes changes into the cluster; Argo CD runs inside the
cluster and pulls changes from Git. That pull-based model is what people
mean by 'GitOps' — it's increasingly standard because nothing outside the
cluster ever needs deploy credentials."

## 6. What you'd do differently in production (shows maturity)
Pull straight from README section 11:
- Scope IAM permissions tightly per-component (IRSA) instead of broad access
- NAT gateway per AZ for high availability
- Remote Terraform state (S3 + DynamoDB locking) for team collaboration

## Anticipated questions & answers

**"Why Kubernetes instead of just ECS or a single EC2 instance?"**
Kubernetes is portable across clouds, has a huge ecosystem (Helm, Argo CD,
autoscalers), and demonstrates skills that transfer to most companies'
existing infrastructure, which is often the deciding factor for a learning
project like this.

**"Why both Jenkins and GitHub Actions/Argo CD?"**
To understand both major CI/CD paradigms — traditional push-based
pipelines (Jenkins) versus modern pull-based GitOps (Argo CD) — since
different companies use different models.

**"How much does this cost to run?"**
Mainly the EKS control plane (~$0.10/hr flat fee), 1 `t3.small` node
(~$0.02/hr) at idle, and one NAT gateway (~$0.045/hr + data). Roughly
$3–4/day when idle; scaling to 4 nodes under load costs more only while
that load lasts. Always `terraform destroy` when done.
