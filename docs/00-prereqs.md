# Fase 0 — Prerrequisitos

Checklist antes de empezar. El cluster corre en **AWS EKS** (managed node group).

## Herramientas en tu máquina

- [ ] **Docker** corriendo (`docker ps` responde) — para construir imágenes
- [ ] **AWS CLI v2** (`aws --version`) autenticado (`aws sts get-caller-identity`)
- [ ] **eksctl** (`eksctl version`) — crea el cluster EKS
- [ ] **kubectl** (`kubectl version --client`)
- [ ] **helm** (`helm version`) — para instalar el Dynatrace Operator
- [ ] **dtctl** (`dtctl version`) — CLI de Dynatrace, para push del RCA / Notebook
- [ ] **gh** (`gh auth status`) — CLI de GitHub, para abrir el PR
- [ ] **Claude Code** con:
  - [ ] el **MCP de Dynatrace** configurado
  - [ ] el skill **dt-custom-rca** instalado (de https://github.com/Edunzz/dynatrace_ai_skills_rca)

## Cuenta AWS

- [ ] Usuario/role con permisos para EKS, EC2, ECR, IAM, CloudFormation
      (eksctl crea el cluster vía CloudFormation)
- [ ] Region elegida (por defecto `us-east-1` en `eks/cluster.yaml`)
- [ ] Presupuesto en mente: EKS cobra ~$0.10/h por el control plane + los EC2
      (`t3.medium`). **Borra el cluster al terminar** (`eksctl delete cluster`).

> OneAgent `cloudNativeFullStack` **no** funciona en Fargate (necesita acceso a
> nivel de nodo). Por eso el cluster usa un managed node group con EC2.

## Cuenta Dynatrace

- [ ] Environment ID a mano (`https://<ENVIRONMENTID>.live.dynatrace.com`)
- [ ] **Operator token** (token de plataforma) con scopes para Kubernetes monitoring
- [ ] **Data ingest token** con `Ingest metrics` + `Ingest logs`
- [ ] **Token de plataforma para MCP/dtctl** (dt0s16) con permisos de lectura
      (problems, entities, DQL) y escritura de Notebooks

> Recordatorio Gen3: los tokens de plataforma (dt0s16) usan header `Bearer` y
> heredan permisos de tu IAM. Los clásicos (dt0c01, header `Api-Token`) están
> deprecados en Gen3.

## Verificación rápida

```bash
docker ps
aws sts get-caller-identity
eksctl version
kubectl version --client
helm version
dtctl version
gh auth status
```

Cuando todo esto pase, sigue con la Fase 1 (crear EKS + deploy) del README.
