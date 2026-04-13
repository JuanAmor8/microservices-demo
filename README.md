# Microservices Demo

Aplicación de votación distribuida implementada con una arquitectura de microservicios.
Los usuarios votan entre **Tacos** y **Burritos** en tiempo real.

## Demo en Vivo (Railway)

| Servicio | URL |
|----------|-----|
| **Vote** | https://microservices-demo-production.up.railway.app |
| **Result** | https://loving-balance-production-ecc4.up.railway.app |

## Arquitectura

![Architecture diagram](architecture.png)

| Servicio   | Tecnología           | Responsabilidad                           |
|------------|----------------------|-------------------------------------------|
| `vote`     | Java 22 / Spring Boot | Interfaz web de votación                 |
| `worker`   | Go 1.24              | Consumidor Kafka → escribe en PostgreSQL  |
| `result`   | Node.js 22           | Resultados en tiempo real (WebSocket)     |
| `kafka`    | Apache Kafka 3.7     | Bus de mensajes asíncrono                 |
| `postgresql`| PostgreSQL 16       | Persistencia de votos                     |

## Repositorios

Este proyecto usa la estrategia **Two-Repo GitOps**:

| Repositorio | Propósito |
|-------------|-----------|
| **microservices-demo** (este) | Código fuente, Dockerfiles, pipelines CI |
| **[microservices-demo-infra](https://github.com/JuanAmor8/microservices-demo-infra)** | Helm charts, configuración, pipeline CD |

## Pipelines CI/CD

### Pipelines de Desarrollo (este repo)

Cada servicio tiene su propio pipeline independiente:

| Pipeline | Archivo | Triggers | Stages |
|----------|---------|----------|--------|
| Vote CI  | [vote-ci.yml](.github/workflows/vote-ci.yml) | push/PR en `vote/**` | Test → Build → Push → Dispatch |
| Worker CI | [worker-ci.yml](.github/workflows/worker-ci.yml) | push/PR en `worker/**` | Test → Build → Push → Dispatch |
| Result CI | [result-ci.yml](.github/workflows/result-ci.yml) | push/PR en `result/**` | Test → Build → Push → Dispatch |

**Flujo:**
```
push a feature/* o develop o main
        │
        ▼
   [Test]  ← Maven / Go test / npm
        │
        ▼
   [Build Docker image]
        │
        ▼
   [Push a GHCR]  ghcr.io/juanamor8/microservices-demo/<servicio>:<tag>
        │
        ▼ (solo main/develop)
   [repository_dispatch] ──────► microservices-demo-infra
                                  └─► deploy a staging/producción
```

### Pipeline de Infraestructura (repo infra)

Ver [microservices-demo-infra](https://github.com/JuanAmor8/microservices-demo-infra).

## Estrategia de Branching

Ver [docs/BRANCHING.md](docs/BRANCHING.md) para la documentación completa.

**Resumen:**
- `feature/*` → `develop` → `release/*` → `main` (Git Flow)
- `main` y `develop` están protegidas (requieren PR + CI verde)

## Patrones de Diseño de Nube

Ver [docs/CLOUD_PATTERNS.md](docs/CLOUD_PATTERNS.md) para la descripción completa.

1. **Event-Driven Architecture** — Kafka desacopla `vote` de `worker`
2. **CQRS** — escrituras (vote→Kafka→worker) separadas de lecturas (result←PostgreSQL)
3. **Microservices Pattern** — servicios independientes, polyglot, deploy por separado

## Diagrama de Arquitectura Detallado

Ver [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Configuración del Secret `INFRA_REPO_TOKEN`

Para que el pipeline de CI pueda disparar el repo de infra, se necesita un Personal Access Token:

1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Permisos: `Contents: Read and Write` en el repo `microservices-demo-infra`
3. Agregar como secret en este repo: `Settings → Secrets → INFRA_REPO_TOKEN`

## Ejecución Local (Docker Compose)

```bash
git clone https://github.com/JuanAmor8/microservices-demo
cd microservices-demo
./scripts/deploy-local.sh up
```

Servicios disponibles en:
- Vote: http://localhost:8080
- Result: http://localhost:4000

Ver más comandos en [scripts/deploy-local.sh](scripts/deploy-local.sh)

## Notas

- La aplicación acepta un solo voto por cliente (cookie-based)
- Los resultados se actualizan cada segundo vía WebSocket
- Kafka corre en modo KRaft (sin ZooKeeper)
