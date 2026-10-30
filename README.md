# Dynatrace AIOps — Loop de auto-remediación

Lab personal: una app real en Kubernetes (**AWS EKS**), instrumentada con
**OneAgent** (Dynatrace Operator). Un agente (Claude Code + skill **dt-custom-rca**
+ **MCP de Dynatrace** + **gh**) cierra el loop:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │  1. DIAGNÓSTICO        Davis detecta el problema; el agente lo     │
  │     (MCP Dynatrace)    investiga read-only vía MCP + DQL           │
  │            │                                                        │
  │            ▼                                                        │
  │  2. RCA + FIX          skill dt-custom-rca arma el Notebook        │
  │     (dtctl)            (resumen, timeline, 5 whys, plan) y lo      │
  │            │           publica con dtctl                           │
  │            ▼                                                        │
  │  3. PULL REQUEST       el agente edita el manifiesto K8s con el    │
  │     (gh)               fix y abre un PR en GitHub                  │
  │            │                                                        │
  │            ▼                                                        │
  │  4. LINK EN NOTEBOOK   deja el link del PR dentro del Notebook     │
  │     (dtctl)            que contiene el RCA                         │
  └──────────────────────────────────────────────────────────────────┘
```

> BindPlane y Arize **no** forman parte de este proyecto.

## La app

Dos microservicios FastAPI en el namespace `aiops-demo`:

- **storefront** → llama a **payments** en `/checkout`
- **payments** → endpoint `/charge`

**La falla inyectada** vive en `k8s/payments.yaml` como variable de entorno:
`FAIL_RATE: "0.4"` → el 40% de los `/charge` devuelven HTTP 500. Eso dispara el
problema en Dynatrace. **El fix = editar ese manifiesto** (bajar `FAIL_RATE` a
`"0.0"`) → PR → link en el Notebook. Por eso la remediación es un cambio de
configuración limpio y versionable.

## Estructura

```
app/
  payments/     main.py · requirements.txt · Dockerfile   (FAIL_RATE, SLOW_MS)
  storefront/   main.py · requirements.txt · Dockerfile   (llama a payments)
k8s/
  namespace.yaml      aiops-demo
  payments.yaml       Deployment (falla) + Service   (imagen = __PAYMENTS_IMAGE__)
  storefront.yaml     Deployment + Service           (imagen = __STOREFRONT_IMAGE__)
  loadgen.yaml        genera tráfico a /checkout
eks/
  cluster.yaml        config de eksctl (managed node group EC2)
scripts/
  deploy.sh           build -> push a ECR -> kubectl apply
dynatrace/
  dynakube.example.yaml   plantilla DynaKube (copiar a dynakube.yaml)
docs/
  00-prereqs.md       Fase 0: checklist de herramientas y tokens
```

## Fases

### Fase 0 — Prerrequisitos
Ver `docs/00-prereqs.md`.

### Fase 1 — Cluster EKS + app
```bash
# 1. Crear el cluster EKS (tarda ~15-20 min; usa CloudFormation)
eksctl create cluster -f eks/cluster.yaml

# 2. kubectl queda apuntando al cluster. Verifica:
kubectl get nodes

# 3. Build + push a ECR + deploy (crea repos ECR, sustituye las imágenes)
export AWS_REGION=us-east-1
chmod +x scripts/deploy.sh
./scripts/deploy.sh

# 4. Ver que el loadgen empieza a ver 502/500
kubectl -n aiops-demo logs -l app=loadgen -f
```

> El `deploy.sh` hace login en ECR, crea los repos `aiops-demo/payments` y
> `aiops-demo/storefront`, construye y sube las imágenes, y aplica los manifiestos
> sustituyendo `__PAYMENTS_IMAGE__` / `__STOREFRONT_IMAGE__` por las URIs de ECR.

### Fase 2 — Instrumentación OneAgent
```bash
# Namespace del operador
kubectl create namespace dynatrace

# Secret con los tokens (ver dynatrace/dynakube.example.yaml)
kubectl -n dynatrace create secret generic dynakube \
  --from-literal="apiToken=<OPERATOR_TOKEN>" \
  --from-literal="dataIngestToken=<DATA_INGEST_TOKEN>"

# Instalar el operador (Helm, recomendado)
helm install dynatrace-operator oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --create-namespace --namespace dynatrace --atomic

# Aplicar el DynaKube (copia la plantilla y pon tu ENVIRONMENTID)
cp dynatrace/dynakube.example.yaml dynatrace/dynakube.yaml
#   edita apiUrl -> https://<ENVIRONMENTID>.live.dynatrace.com/api
kubectl apply -f dynatrace/dynakube.yaml

# Verificar
kubectl get dynakube -n dynatrace
kubectl get pods -n dynatrace
```
Reinicia los pods de la app para que tomen la auto-instrumentación:
```bash
kubectl -n aiops-demo rollout restart deploy/payments deploy/storefront
```

### Fase 3 — Diagnóstico (MCP)
En Claude Code, con el MCP de Dynatrace conectado: pedir que liste los problemas
abiertos del namespace `aiops-demo` y seleccione el de `payments` (error rate alto).

### Fase 4 — RCA en Notebook (dt-custom-rca + dtctl)
Invocar el skill **dt-custom-rca** sobre ese problema. Genera el Notebook basado en
evidencia (resumen ejecutivo, timeline, 5 whys, plan de acción, diagramas) y lo
publica con `dtctl`. Valida con `build_notebook.py --strict` y `dtctl apply --dry-run`
antes de publicar.

### Fase 5 — Fix + PR + link
1. El agente edita `k8s/payments.yaml`: `FAIL_RATE: "0.4"` → `"0.0"`.
2. Abre el PR:
   ```bash
   gh pr create --title "fix(payments): baja FAIL_RATE a 0 (RCA Dynatrace)" \
     --body "Corrige el error rate de payments detectado por Davis. Ver RCA: <link notebook>"
   ```
3. Toma la URL del PR y la escribe dentro del Notebook del RCA (vía `dtctl`),
   cerrando el loop.

### Limpieza (importante por costo)
```bash
eksctl delete cluster -f eks/cluster.yaml
# opcional: borrar las imágenes/repos de ECR si ya no los usas
```

## Notas

- `imagePullPolicy: Always` + imágenes en **ECR**: los nodos las jalan del registry
  (el node group tiene el addon policy de ECR).
- OneAgent `cloudNativeFullStack` requiere **EC2 managed node group** (no Fargate).
- Nada de secretos en git: `.env`, `dynatrace/dynakube.yaml` y tokens están en
  `.gitignore`.
- El skill dt-custom-rca es **read-only** sobre Dynatrace y **no** abre PRs; esa
  parte (Fases 3→5) la orquesta el agente con MCP + gh.
- Acuérdate de **borrar el cluster** al terminar para no acumular costo de AWS.
