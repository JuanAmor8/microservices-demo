# Microservices Demo — Aplicación de Votación Distribuida

Aplicación distribuida donde los usuarios votan entre **Burritos** y **Tacos** en tiempo real,
implementada con una arquitectura de microservicios polyglot, comunicación asíncrona y
un pipeline CI/CD completo bajo la estrategia GitOps.

---

## Tabla de Contenidos

1. [Demo en Vivo](#1-demo-en-vivo)
2. [Metodología Ágil](#2-metodología-ágil)
3. [Arquitectura del Sistema](#3-arquitectura-del-sistema)
4. [Patrones de Diseño de Nube](#4-patrones-de-diseño-de-nube)
5. [Estrategia de Branching — Desarrolladores](#5-estrategia-de-branching--desarrolladores)
6. [Estrategia de Branching — Operaciones](#6-estrategia-de-branching--operaciones)
7. [Pipelines de Desarrollo CI](#7-pipelines-de-desarrollo-ci)
8. [Pipeline de Infraestructura CD](#8-pipeline-de-infraestructura-cd)
9. [Implementación de la Infraestructura](#9-implementación-de-la-infraestructura)
10. [Ejecución Local](#10-ejecución-local)

---

## 1. Demo en Vivo

| Servicio | URL |
|----------|-----|
| **Vote** (interfaz de votación) | https://microservices-demo-production.up.railway.app |
| **Result** (resultados en tiempo real) | https://loving-balance-production-ecc4.up.railway.app |

> Los resultados se actualizan automáticamente cada segundo vía WebSocket.

---

## 2. Metodología Ágil

El proyecto sigue **Scrum** con sprints de 2 semanas.

| Ceremonia | Frecuencia | Propósito |
|-----------|------------|-----------|
| Sprint Planning | Inicio de sprint | Seleccionar historias del backlog |
| Daily Standup | Diario | Sincronización del equipo |
| Sprint Review | Fin de sprint | Demo de funcionalidades completadas |
| Retrospectiva | Fin de sprint | Mejora continua del proceso |

Cada historia de usuario se traduce en una rama `feature/` que sigue el flujo Git Flow descrito en la sección 5.

---

## 3. Arquitectura del Sistema

### Vista de Alto Nivel

```
                    ┌─────────────────────────────────────────────┐
                    │              USUARIO FINAL                  │
                    └──────────────┬──────────────────┬──────────┘
                                   │                  │
                          Vota     │                  │  Ve resultados
                         (HTTP)    │                  │  (WebSocket)
                                   ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        RAILWAY (PRODUCCIÓN)                         │
│                                                                     │
│  ┌──────────────────┐                       ┌───────────────────┐  │
│  │  vote (Java)     │                       │ result (Node.js)  │  │
│  │  Spring Boot     │                       │ Express+Socket.IO │  │
│  │  :8080           │                       │ :80               │  │
│  └────────┬─────────┘                       └────────▲──────────┘  │
│           │ publish(voter_id, vote)                  │ SELECT       │
│           ▼                                          │              │
│  ┌──────────────────┐  consume              ┌────────┴──────────┐  │
│  │  Kafka 3.7       │──────────────────────►│  PostgreSQL 16    │  │
│  │  KRaft mode      │  ┌─────────────────┐  │  DB: votes        │  │
│  │  :9092           │  │  worker (Go)    │  │  tabla: votes     │  │
│  └──────────────────┘  │  Consumer Group │  └───────────────────┘  │
│                        └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────────┘
```

### Descripción de Servicios

| Servicio | Tecnología | Puerto | Imagen Docker | Responsabilidad |
|----------|-----------|--------|---------------|-----------------|
| `vote` | Java 22 / Spring Boot 3.4.1 / Thymeleaf | 8080 | `eclipse-temurin:22-jre` | Renderiza la UI, recibe votos via POST y los publica al topic Kafka `votes` usando `KafkaTemplate` |
| `worker` | Go 1.24.1 | N/A (proceso background) | `scratch` | Consume mensajes del topic Kafka y persiste votos en PostgreSQL con UPSERT |
| `result` | Node.js 22 / Express / Socket.IO | 80 | `node:22.12.0-slim` | Consulta PostgreSQL cada 1 segundo y emite resultados por WebSocket a los clientes |
| `kafka` | Apache Kafka 3.7.0 (KRaft) | 9092/9093 | `apache/kafka:3.7.0` | Message broker asíncrono, topic `votes`, modo KRaft sin ZooKeeper |
| `postgresql` | PostgreSQL 16 | 5432 | `postgres:16` | Persistencia de votos, tabla `votes(id VARCHAR, vote VARCHAR)` con constraint UNIQUE en `id` |

### Flujo de Datos Detallado

```
1. Usuario abre la URL del servicio vote
   └─► vote (Java/Thymeleaf) sirve la interfaz HTML

2. Usuario hace clic en "Burritos" o "Tacos"
   └─► POST /  →  VoteController.java
       └─► KafkaTemplate.send("votes", voter_id, "burritos")
           └─► Mensaje publicado al topic Kafka

3. Kafka retiene el mensaje en el topic "votes"
   └─► worker (Go) consume el mensaje con sarama.Consumer
       └─► INSERT INTO votes(id, vote) VALUES($1, $2)
           ON CONFLICT(id) DO UPDATE SET vote = $2

4. Usuario abre la URL del servicio result
   └─► result (Node.js) establece conexión WebSocket
       └─► Cada 1 segundo: SELECT vote, COUNT(id) FROM votes GROUP BY vote
           └─► socket.emit('scores', JSON.stringify(votes))
               └─► UI actualiza contadores en tiempo real
```

### Repositorios — Estrategia Two-Repo GitOps

| Repositorio | Propósito |
|-------------|-----------|
| **[microservices-demo](https://github.com/JuanAmor8/microservices-demo)** | Código fuente, Dockerfiles, pipelines CI |
| **[microservices-demo-infra](https://github.com/JuanAmor8/microservices-demo-infra)** | Helm charts, valores por ambiente, pipeline CD |

```
microservices-demo (DEV)              microservices-demo-infra (OPS)
────────────────────────              ──────────────────────────────
Código de aplicación        ───────►  Helm charts + configuración
Dockerfiles                           Valores por ambiente
Pipelines CI (build+push)             Pipeline CD (deploy)
Desarrolladores escriben aquí         Ops equipa gestiona aquí
         repository_dispatch
         (nueva imagen disponible)
```

---

## 4. Patrones de Diseño de Nube

### Patrón 1 — Event-Driven Architecture (EDA)

Los componentes se comunican a través de **eventos asíncronos** en lugar de llamadas directas. El servicio `vote` publica eventos y el `worker` reacciona de forma independiente.

```
  [vote - Java]                          [worker - Go]
  ────────────          Apache Kafka      ────────────
  POST /vote ──► KafkaTemplate.send ──► sarama.Consumer ──► INSERT PostgreSQL
                      topic: "votes"
                  Mensaje: { key: voter_id, value: "burritos" }
```

**Código relevante:**
- Productor: [vote/src/main/java/com/okteto/vote/kafka/KafkaProducerConfig.java](vote/src/main/java/com/okteto/vote/kafka/KafkaProducerConfig.java)
- Consumidor: [worker/main.go](worker/main.go)

| Beneficio | Descripción |
|-----------|-------------|
| Desacoplamiento | `vote` no necesita saber que `worker` existe ni su estado |
| Resiliencia | Si `worker` cae, Kafka retiene los mensajes hasta su recuperación |
| Escalabilidad | Se pueden agregar múltiples instancias de `worker` sin tocar `vote` |
| Tolerancia a fallos | El productor no falla si el consumidor está lento o caído |

---

### Patrón 2 — CQRS (Command Query Responsibility Segregation)

Las operaciones de **escritura (Command)** y de **lectura (Query)** están implementadas en servicios completamente separados con stacks tecnológicos distintos.

```
                ┌─── WRITE PATH (Command) ──────────────────────────┐
  Usuario       │                                                   │
     │──POST───► vote (Java) ──► Kafka ──► worker (Go) ──► PostgreSQL
     │          └───────────────────────────────────────────────┐   │
     │                                                          │   │
     │          ┌─── READ PATH (Query) ─────────────────────────┘   │
     └──GET────► result (Node.js) ◄──── SELECT ◄───── PostgreSQL
                └────────────────────────────────────────────────────┘
```

**Código relevante:**
- Command side: [vote/](vote/) → [worker/main.go](worker/main.go)
- Query side: [result/server.js](result/server.js)

| Beneficio | Descripción |
|-----------|-------------|
| Separación de concerns | Java/Go para escrituras, Node.js para lecturas |
| Escalado independiente | `result` puede escalar para muchos lectores sin afectar writes |
| Tecnología óptima por rol | Cada servicio usa el lenguaje más adecuado para su función |

---

### Patrón 3 — Microservices Pattern

La aplicación está dividida en **servicios pequeños, independientes y deployables por separado**, cada uno con su propio Dockerfile, Helm chart y pipeline CI/CD.

| Servicio | Lenguaje | Deploy independiente | Pipeline propio |
|----------|----------|----------------------|-----------------|
| `vote` | Java | Si | `vote-ci.yml` |
| `worker` | Go | Si | `worker-ci.yml` |
| `result` | Node.js | Si | `result-ci.yml` |

```
┌─────────────────────────────────────────────────────────────────┐
│                    Microservices Pattern                         │
│  ┌───────────────┐  ┌──────────────┐  ┌────────────────────┐   │
│  │  vote (Java)  │  │ worker (Go)  │  │  result (Node.js)  │   │
│  │  Dockerfile   │  │  Dockerfile  │  │    Dockerfile      │   │
│  │  Helm chart   │  │  Helm chart  │  │    Helm chart      │   │
│  │  vote-ci.yml  │  │ worker-ci.yml│  │  result-ci.yml     │   │
│  └───────┬───────┘  └──────┬───────┘  └──────────┬─────────┘   │
│          │                 │                       │             │
│  ┌───────▼─────────────────▼───────────────────────▼─────────┐  │
│  │               Event-Driven Architecture (Kafka)            │  │
│  │   vote ──publish──► Kafka ──consume──► worker ──write──►   │  │
│  │                                                PostgreSQL   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌─────────────────────────── CQRS ───────────────────────────┐  │
│  │  WRITE: vote → Kafka → worker → PostgreSQL                 │  │
│  │  READ:  result ← SELECT ← PostgreSQL                       │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 5. Estrategia de Branching — Desarrolladores

**Repositorio:** `microservices-demo` | **Modelo:** Git Flow

### Ramas principales

| Rama | Propósito | Protegida |
|------|-----------|-----------|
| `main` | Código en producción. Solo recibe merges de `feature/*` vía PR | Si |
| `develop` | Rama de integración. Base para nuevas features | Si |

### Ramas de soporte

| Patrón | Origen | Destino | Descripción |
|--------|--------|---------|-------------|
| `feature/TICKET-descripcion` | `develop` | `develop` | Nueva funcionalidad |
| `hotfix/descripcion` | `main` | `main` + `develop` | Corrección urgente en producción |
| `bugfix/descripcion` | `develop` | `develop` | Corrección de bugs no urgentes |

### Flujo completo

```
  feature/VOT-12          develop                   main
  ──────────────          ───────                   ────

  git checkout -b
  feature/VOT-12
        │
  [desarrollo]
  [commits]
        │
        │  PR + Code Review
        │  CI verde (test + build)
        └──────────────────────►│
                                │
                                │  PR + aprobación
                                └──────────────────►│
                                                    │
                                           Pipeline CI:
                                           build + push :latest
                                           repository_dispatch
                                                    │
                                                    ▼
                                          [microservices-demo-infra]
                                          Pipeline CD: deploy prod
```

### Reglas de protección

- `main` y `develop`: requieren **PR** con al menos **1 aprobación**
- El CI pipeline debe pasar antes del merge (tests + build)
- No se permite `force push`
- Conventional Commits: `feat:`, `fix:`, `ci:`, `chore:`, `docs:`, `test:`

### Ejemplo práctico

```bash
# 1. Iniciar nueva feature
git checkout develop && git pull origin develop
git checkout -b feature/VOT-15-improve-result-ui

# 2. Desarrollar + commits
git commit -m "feat(result): improve websocket reconnection logic"

# 3. Push + abrir PR hacia develop
git push origin feature/VOT-15-improve-result-ui
# GitHub: PR → develop → code review → CI verde → merge

# 4. Una vez en develop, PR hacia main
# GitHub: PR → main → aprobación → merge → pipeline CI dispara infra
```

---

## 6. Estrategia de Branching — Operaciones

**Repositorio:** `microservices-demo-infra` | **Modelo:** Environment Branching

### Ramas principales

| Rama | Ambiente | Deploy | Descripción |
|------|----------|--------|-------------|
| `main` | Producción | Con aprobación manual en GitHub Environments | Estado de infra en producción |
| `infra/staging` | Staging | Automático | Infra de pre-producción |

### Ramas de soporte

| Patrón | Origen | Destino | Descripción |
|--------|--------|---------|-------------|
| `infra/feature/*` | `infra/staging` | `infra/staging` | Cambios experimentales de infra |

### Qué va en el repo de infra

- Helm charts de todos los servicios (`charts/`)
- Valores por ambiente (`environments/production.yaml`, `environments/staging.yaml`)
- Pipeline de deploy (`infra-cd.yml`)

### Flujo de cambios de infraestructura

```
  infra/feature/          infra/staging            main (prod)
  increase-replicas       ─────────────            ──────────
  ─────────────────
  [modificar values.yaml]
          │
          │  PR + revisión Ops
          └──────────────────►│
                              │ Deploy automático a staging
                              │ [validar]
                              │
                              │  PR + aprobación manual
                              └────────────────────────►│
                                                        │
                                              Deploy a producción
                                              (requiere aprobación
                                               en GitHub Environments)
```

### Ejemplo práctico

```bash
# Aumentar replicas del servicio vote
git checkout infra/staging && git pull
git checkout -b infra/feature/scale-vote-replicas

# Modificar environments/production.yaml
# vote.replicaCount: 2 → 3
git commit -m "chore(infra): scale vote to 3 replicas for peak traffic"
git push origin infra/feature/scale-vote-replicas

# PR → infra/staging → deploy automático → validar
# PR → main → aprobación manual → deploy a producción
```

### Diagrama Resumen — Dos Repos

```
REPO DEV (microservices-demo)        REPO OPS (microservices-demo-infra)
══════════════════════════════       ═════════════════════════════════════

feature/* ──► develop                infra/feature/* ──► infra/staging
                │                                              │
         feature/* ──► main ─────────────────────────────► main
                      [CI: push image]  [repository_dispatch] │
                      hotfix/* ──► main                 [CD: deploy]
                                                              │
                                                 staging ◄────┘ (auto)
                                                 prod    ◄──────(aprobación manual)
```

---

## 7. Pipelines de Desarrollo CI

Cada servicio tiene su propio pipeline independiente. Todos siguen el mismo patrón de 3 etapas.

### Flujo general

```
push a feature/*, develop o main
        │
        ▼
   ┌─────────┐
   │  Test   │ ← Maven (Java) / go vet + go test (Go) / npm test (Node.js)
   └────┬────┘
        │ falla → pipeline se detiene, imagen NO se construye
        ▼
   ┌────────────────┐
   │ Build & Push   │ ← Docker multi-stage build → GHCR
   └────────┬───────┘   ghcr.io/juanamor8/microservices-demo/<servicio>:<tag>
            │ (solo en push, no en PR)
            ▼
   ┌──────────────────────┐
   │ Trigger Infra Repo   │ ← repository_dispatch → microservices-demo-infra
   └──────────────────────┘   (solo en main y develop)
```

### Vote CI — [vote-ci.yml](.github/workflows/vote-ci.yml)

| Stage | Herramienta | Acción |
|-------|-------------|--------|
| Test | Maven 3.9 + JDK 22 | `mvn test -B` — unit tests + surefire report |
| Build & Push | Docker Buildx + GHCR | Multi-stage build: `maven:3.9.9` → `eclipse-temurin:22-jre` |
| Trigger | `repository-dispatch` | Notifica al repo infra con `event-type: vote-image-updated` |

**Tags generados:**
- `sha-<commit>` — en todo push
- `develop` — en push a develop
- `latest` — en push a main

### Worker CI — [worker-ci.yml](.github/workflows/worker-ci.yml)

| Stage | Herramienta | Acción |
|-------|-------------|--------|
| Test | Go 1.24 | `go mod tidy` → `go vet ./...` → `go test -v -race -count=1 ./...` |
| Build & Push | Docker Buildx + GHCR | Multi-stage build: `golang:1.24.1-bookworm` → `scratch` |
| Trigger | `repository-dispatch` | Notifica al repo infra con `event-type: worker-image-updated` |

**Tests implementados** ([worker/main_test.go](worker/main_test.go)):
```
TestGetEnv_ReturnsFallbackWhenNotSet  — variable no definida → retorna fallback
TestGetEnv_ReturnsValueWhenSet        — variable con valor   → retorna el valor
TestGetEnv_ReturnsFallbackWhenEmpty   — variable vacía       → retorna fallback
```

### Result CI — [result-ci.yml](.github/workflows/result-ci.yml)

| Stage | Herramienta | Acción |
|-------|-------------|--------|
| Test | Node.js 22 + Jest | `npm install` → `npm audit` → `npm test` (Jest) |
| Build & Push | Docker Buildx + GHCR | `node:22.12.0-slim` con Tini para manejo de señales |
| Trigger | `repository-dispatch` | Notifica al repo infra con `event-type: result-image-updated` |

**Tests implementados** ([result/utils.test.js](result/utils.test.js)):
```
✓ returns zeros when no rows
✓ counts votes for both options
✓ handles partial results (only one option has votes)
```

### Infrastructure CI — [infrastructure-ci.yml](.github/workflows/infrastructure-ci.yml)

Valida y empaqueta los Helm charts del repo de desarrollo.

| Stage | Acción |
|-------|--------|
| Helm Lint | `helm lint` en los 4 charts (infrastructure, vote, worker, result) |
| Helm Package | `helm package` → artefactos subidos a GitHub Actions (30 días) |
| Deploy | Referencia a comandos `helm upgrade --install` (deploy real en repo infra) |

### Payload del repository_dispatch

```json
{
  "image": "ghcr.io/juanamor8/microservices-demo/vote:latest",
  "sha": "abc1234",
  "branch": "main",
  "triggered_by": "vote-ci"
}
```

---

## 8. Pipeline de Infraestructura CD

**Repositorio:** [microservices-demo-infra](https://github.com/JuanAmor8/microservices-demo-infra)
**Archivo:** `.github/workflows/infra-cd.yml`

### Triggers

| Evento | Que dispara |
|--------|-------------|
| `repository_dispatch` desde repo dev | Deploy a staging del servicio actualizado |
| Push a `main` | Deploy a producción (requiere aprobación manual) |
| Push a `infra/staging` | Deploy a staging |
| `workflow_dispatch` | Deploy manual con selección de ambiente y servicio |

### Etapas

```
┌──────────────────────────────────────────────────────────────────┐
│                        infra-cd.yml                              │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Stage 1: Helm Lint & Validate                          │    │
│  │  helm lint charts/infrastructure/                       │    │
│  │  helm lint charts/vote/                                 │    │
│  │  helm lint charts/worker/                               │    │
│  │  helm lint charts/result/                               │    │
│  │  helm template <all charts> --debug (dry-run)           │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           │                                      │
│             ┌─────────────┴─────────────┐                        │
│             ▼                           ▼                        │
│  ┌──────────────────┐       ┌───────────────────────────┐       │
│  │ Stage 2: Staging │       │ Stage 3: Production        │       │
│  │                  │       │                            │       │
│  │ Trigger:         │       │ Trigger:                   │       │
│  │ repository_disp  │       │ push a main solamente      │       │
│  │ o infra/staging  │       │ o workflow_dispatch manual │       │
│  │                  │       │                            │       │
│  │ Deploy del       │       │ Requiere aprobación manual │       │
│  │ servicio         │       │ en GitHub Environments     │       │
│  │ actualizado      │       │                            │       │
│  └──────────────────┘       └───────────────────────────┘       │
└──────────────────────────────────────────────────────────────────┘
```

### Environments de GitHub

| Environment | Protección | Uso |
|-------------|------------|-----|
| `staging` | Sin gate | Deploy automático |
| `production` | Aprobación manual requerida | Deploy a producción |

---

## 9. Implementación de la Infraestructura

### Helm Charts

Cada servicio tiene su propio Helm chart. La infraestructura compartida (Kafka + PostgreSQL) tiene un chart separado.

```
microservices-demo/
├── infrastructure/          ← Chart: Kafka + PostgreSQL
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── kafka.yaml       ← Deployment + Service + PVC (1Gi)
│       └── postgresql.yaml  ← Deployment + Service + PVC (1Gi)
│
├── vote/chart/              ← Chart: servicio vote
├── worker/chart/            ← Chart: servicio worker
└── result/chart/            ← Chart: servicio result

microservices-demo-infra/
├── charts/                  ← Charts para deploy
│   ├── infrastructure/
│   ├── vote/
│   ├── worker/
│   └── result/
└── environments/
    ├── production.yaml      ← Imagenes :latest, replicaCount: 2
    └── staging.yaml         ← Imagenes :develop, replicaCount: 1
```

### Recursos Kubernetes por servicio

| Recurso | vote | worker | result | infrastructure |
|---------|------|--------|--------|----------------|
| Deployment | Si | Si | Si | Si (kafka + pg) |
| Service (ClusterIP) | Si | — | Si | Si (kafka + pg) |
| Ingress | Si | — | Si | — |
| PersistentVolumeClaim | — | — | — | Si (1Gi cada uno) |

### Imágenes Docker

| Servicio | Build stage | Runtime stage | Característica |
|----------|-------------|---------------|----------------|
| `vote` | `maven:3.9.9-eclipse-temurin-22` | `eclipse-temurin:22-jre-jammy` | Usuario non-root `spring` |
| `worker` | `golang:1.24.1-bookworm` | `scratch` | Imagen minima, sin OS |
| `result` | — | `node:22.12.0-slim` | Tini para gestión de señales |

### Variables de entorno por servicio

**vote:**
```
KAFKA_BOOTSTRAP_SERVERS=kafka:9092
OPTION_A=Burritos          # opcional, default: Burritos
OPTION_B=Tacos             # opcional, default: Tacos
```

**worker:**
```
KAFKA_BOOTSTRAP_SERVERS=kafka:9092
DATABASE_URL=postgres://user:pass@host/db   # Railway
# o variables individuales para Docker Compose:
DB_HOST=postgresql
DB_USER=okteto
DB_PASSWORD=okteto
DB_NAME=votes
```

**result:**
```
DATABASE_URL=postgres://okteto:okteto@postgresql/votes
PORT=80
```

### Registro de imágenes (GHCR)

```
ghcr.io/juanamor8/microservices-demo/vote:<tag>
ghcr.io/juanamor8/microservices-demo/worker:<tag>
ghcr.io/juanamor8/microservices-demo/result:<tag>
```

Tags disponibles: `latest` (main), `develop`, `sha-<commit>`

---

## 10. Ejecución Local

### Requisitos

- Docker Desktop
- Git

### Levantar todos los servicios

```bash
git clone https://github.com/JuanAmor8/microservices-demo
cd microservices-demo
./scripts/deploy-local.sh up
```

| Servicio | URL local |
|----------|-----------|
| Vote | http://localhost:8080 |
| Result | http://localhost:4000 |

### Comandos disponibles

```bash
./scripts/deploy-local.sh up               # Construye y levanta todos los servicios
./scripts/deploy-local.sh down             # Detiene y elimina contenedores y volúmenes
./scripts/deploy-local.sh logs             # Logs de todos los servicios
./scripts/deploy-local.sh logs vote        # Logs de un servicio especifico
./scripts/deploy-local.sh status           # Estado de todos los servicios
./scripts/deploy-local.sh restart          # Reinicia todos los servicios
./scripts/deploy-local.sh restart worker   # Reinicia un servicio especifico
```

### Orden de arranque

```
postgresql (healthy) ──► worker
kafka      (healthy) ──► vote
                     ──► worker
postgresql (healthy) ──► result
```

### Demostración de cambios en el pipeline

Para demostrar el flujo CI/CD completo en vivo:

```bash
# 1. Crear rama feature
git checkout develop && git pull origin develop
git checkout -b feature/demo-cambio

# 2. Hacer un cambio visible
# Editar vote/src/main/resources/templates/index.html

# 3. Commit y push — activa el pipeline CI automaticamente
git add . && git commit -m "feat(vote): update candidate label"
git push origin feature/demo-cambio

# 4. Abrir PR en GitHub y observar:
#    Stage 1 — Test (Maven): mvn test
#    Stage 2 — Build & Push: Docker → GHCR
#    Stage 3 — Trigger Infra: repository_dispatch

# 5. Mergear PR a develop
# 6. PR develop → main → pipeline construye imagen :latest
#    → repo infra recibe dispatch → deploy a produccion
```
