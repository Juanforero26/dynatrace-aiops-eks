#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Build -> push a ECR -> deploy en EKS
# -----------------------------------------------------------------------------
# Uso:
#   export AWS_REGION=us-east-1
#   ./scripts/deploy.sh
#
# Requiere: aws cli autenticado, docker, kubectl apuntando al cluster EKS.
# -----------------------------------------------------------------------------
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

PAYMENTS_IMAGE="${REGISTRY}/aiops-demo/payments:v2"
STOREFRONT_IMAGE="${REGISTRY}/aiops-demo/storefront:v1"

echo ">> ECR login"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo ">> Crear repos ECR (si no existen)"
for repo in aiops-demo/payments aiops-demo/storefront; do
  aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" >/dev/null
done

echo ">> Build + push payments"
docker build -t "$PAYMENTS_IMAGE" app/payments
docker push "$PAYMENTS_IMAGE"

echo ">> Build + push storefront"
docker build -t "$STOREFRONT_IMAGE" app/storefront
docker push "$STOREFRONT_IMAGE"

echo ">> Aplicar manifiestos (sustituyendo imágenes)"
kubectl apply -f k8s/namespace.yaml
sed "s#__PAYMENTS_IMAGE__#${PAYMENTS_IMAGE}#g"   k8s/payments.yaml   | kubectl apply -f -
sed "s#__STOREFRONT_IMAGE__#${STOREFRONT_IMAGE}#g" k8s/storefront.yaml | kubectl apply -f -
kubectl apply -f k8s/loadgen.yaml

echo ">> Listo. Logs del loadgen:"
echo "   kubectl -n aiops-demo logs -l app=loadgen -f"
