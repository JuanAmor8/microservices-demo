# Estrategia de Branching

## Metodología Ágil: Scrum

El proyecto sigue la metodología **Scrum** con sprints de 2 semanas. Cada historia de usuario se
traduce en una o más ramas de trabajo que siguen las estrategias descritas a continuación.

---

## Estructura de Repositorios (Two-Repo Strategy)

El proyecto usa **dos repositorios separados**, siguiendo el patrón **GitOps**:

```
┌──────────────────────────────────┐     ┌───────────────────────────────────┐
│   microservices-demo  (DEV)      │     │  microservices-demo-infra  (OPS)  │
│                                  │     │                                   │
│  Código de aplicación            │     │  Helm charts + configuración      │
│  Dockerfiles                     │     │  Valores por ambiente             │
│  Pipelines CI (build + push)     │     │  Pipeline CD (deploy)             │
│                                  │─────►                                   │
│  Desarrolladores escriben aquí   │     │  Ops equipo gestiona aquí         │
└──────────────────────────────────┘     └───────────────────────────────────┘
         repository_dispatch
    (notifica nueva imagen lista)
```

**Por qué dos repos:**
- Los desarrolladores no tienen acceso a modificar la infraestructura de producción
- Los cambios de infra tienen su propio ciclo de revisión y aprobación
- Historial de cambios separado para auditoría

---

## 1. Estrategia para Desarrolladores — Git Flow (repo: `microservices-demo`)

### Ramas principales

| Rama       | Propósito                                              | Protegida |
|------------|--------------------------------------------------------|-----------|
| `main`     | Código en producción. Solo recibe merges de `release/*` o `hotfix/*` | Sí |
| `develop`  | Rama de integración. Base para nuevas features         | Sí |

### Ramas de soporte

| Patrón                       | Origen    | Destino              | Descripción                                      |
|------------------------------|-----------|----------------------|--------------------------------------------------|
| `feature/TICKET-descripcion` | `develop` | `develop`            | Nueva funcionalidad. Ej: `feature/VOT-12-add-candidate` |
| `release/vX.Y.Z`             | `develop` | `main` + `develop`   | Preparación de release. Solo bugfixes            |
| `hotfix/descripcion`         | `main`    | `main` + `develop`   | Corrección urgente en producción                 |
| `bugfix/descripcion`         | `develop` | `develop`            | Corrección de bugs no urgentes                   |

### Flujo de trabajo completo

```
  feature/VOT-12                develop              release/v1.2.0          main
  ──────────────                ───────              ──────────────          ────
  git checkout -b │
  feature/VOT-12  │
                  │
  [desarrollo]    │
  [commits]       │
                  │ PR + Code Review
                  └──────────────────►│
                                      │
                              CI pasa │
                              (test + │
                              build)  │
                                      │──────────────────►│
                                                          │ QA + bugfixes
                                                          │
                                                          │ PR + aprobación
                                                          └─────────────────►│
                                                                             │
                                                                    Pipeline CI:
                                                                    build + push
                                                                    image :latest
                                                                             │
                                                                    repository_dispatch
                                                                             │
                                                                             ▼
                                                                   [microservices-demo-infra]
                                                                   Pipeline CD: deploy prod
```

### Reglas de protección

- `main` y `develop`: requieren **PR** con al menos **1 aprobación**
- CI pipeline debe pasar antes del merge
- No se permite `force push`
- Conventional Commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`

### Ejemplo práctico

```bash
# Iniciar nueva feature
git checkout develop && git pull origin develop
git checkout -b feature/VOT-15-websocket-improvements

# Desarrollo + commits
git commit -m "feat(result): improve websocket reconnection logic"

# Push + abrir PR hacia develop
git push origin feature/VOT-15-websocket-improvements
# → GitHub: abrir PR → code review → CI verde → merge a develop

# Fin de sprint: crear release
git checkout develop && git checkout -b release/v1.3.0
git commit -m "chore(release): bump version to 1.3.0"
# → PR a main → aprobación → merge → TAG → pipeline dispara infra repo
```

---

## 2. Estrategia para Operaciones — Environment Branching (repo: `microservices-demo-infra`)

### Ramas principales

| Rama            | Ambiente   | Deploy automático | Descripción                             |
|-----------------|------------|-------------------|-----------------------------------------|
| `main`          | Producción | Sí (con aprobación manual en GitHub) | Estado de infra en producción |
| `infra/staging` | Staging    | Sí (automático)   | Infra de pre-producción                 |

### Ramas de soporte

| Patrón               | Origen          | Destino         | Descripción                        |
|----------------------|-----------------|-----------------|------------------------------------|
| `infra/feature/*`    | `infra/staging` | `infra/staging` | Cambios experimentales de infra    |

### Qué va en el repo de infra

- Helm charts de todos los servicios (`charts/`)
- `values.yaml` por ambiente (`environments/`)
- `okteto.yml`
- Pipeline de deploy (`infra-cd.yml`)
- Scripts de migración de base de datos

### Flujo de cambios de infraestructura

```
  infra/feature/              infra/staging              main (prod)
  increase-replicas           ─────────────              ──────────
  ─────────────────
  [modificar values.yaml]
          │ PR + revisión Ops
          └───────────────────►│
                               │ Deploy automático
                               │ a staging
                               │ [validar]
                               │
                               │ PR + aprobación manual
                               └──────────────────────►│
                                                        │ Deploy a producción
                                                        │ (requiere aprobación
                                                        │  en GitHub Environments)
```

### Ejemplo práctico

```bash
# Aumentar replicas del servicio vote en producción
git checkout infra/staging && git pull
git checkout -b infra/feature/increase-vote-replicas

# Modificar environments/production.yaml
# vote.replicaCount: 2 → 3
git commit -m "chore(infra): scale vote to 3 replicas for peak traffic"
git push origin infra/feature/increase-vote-replicas

# PR → infra/staging → deploy automático → validar
# PR → main → aprobación manual → deploy a producción
```

---

## Diagrama Resumen — Dos Repos

```
REPO DEV (microservices-demo)          REPO OPS (microservices-demo-infra)
══════════════════════════════         ══════════════════════════════════════

feature/* ──► develop                  infra/feature/* ──► infra/staging
                │                                               │
         release/* ──► main ──────────────────────────────► main
                │     [CI: push image]  [repository_dispatch]  │
           hotfix/* ──► main                             [CD: deploy]
                                                               │
                                                    staging ◄──┘ (auto)
                                                    prod    ◄──── (aprobación manual)
```
