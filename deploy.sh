#!/usr/bin/env bash
set -e

echo "=== [1/5] Deploying EKS Cluster & Infrastructure via Terraform ==="
terraform init
terraform apply -auto-approve

CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)

echo "=== [2/5] Updating Local Kubeconfig ==="
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "=== [3/5] Installing Kong API Gateway & Ingress Controller ==="
kubectl create namespace kong || true
helm repo add kong https://charts.konghq.com
helm repo update
helm upgrade --install kong kong/kong \
  --namespace kong \
  -f helm-values/kong-values.yaml

kubectl apply -f kong-ingress-alb.yaml

echo "=== [4/5] Deploying Observability Stack (Prometheus, Loki, Tempo, Grafana) ==="
kubectl create namespace observability || true

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Prometheus & Grafana
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f helm-values/kube-prometheus-stack-values.yaml

# Install Loki
helm upgrade --install loki grafana/loki \
  --namespace observability \
  --set loki.auth_enabled=false

# Install Tempo
helm upgrade --install tempo grafana/tempo \
  --namespace observability

echo "=== [5/5] Deploying OpenTelemetry Collector ==="
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  -f helm-values/otel-collector-values.yaml

echo "========================================================================="
echo "DEPLOYMENT COMPLETE!"
echo "AWS ALB is provisioning for Kong Proxy. Check status using:"
echo "  kubectl get ingress -n kong"
echo "Grafana Credentials: user: admin / pass: adminpassword123"
echo "========================================================================="
