# Arquitectura del Sistema

## Descripción General

**Microservices Demo** es una aplicación de votación distribuida que implementa una arquitectura
de microservicios con comunicación asíncrona. Los usuarios votan entre **Tacos** y **Burritos**,
los votos se procesan en tiempo real y los resultados se muestran en vivo.

---

## Diagrama de Arquitectura — Vista de Alto Nivel

```
                         ┌─────────────────────────────────────────────┐
                         │              USUARIO FINAL                  │
                         └─────────────┬─────────────────┬────────────┘
                                       │                 │
                              Vota     │                 │  Ve resultados
                            (HTTP)     │                 │  (WebSocket)
                                       ▼                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES / OKTETO                          │
│                                                                      │
│  ┌───────────────────┐                       ┌──────────────────┐   │
│  │   vote (Java)     │                       │  result (Node.js) │  │
│  │  Spring Boot      │                       │  Express +        │  │
│  │  :8080            │                       │  Socket.IO :80    │  │
│  └────────┬──────────┘                       └────────▲─────────┘  │
│           │ publish                                    │ SELECT      │
│           ▼                                            │             │
│  ┌───────────────────┐                       ┌────────┴─────────┐   │
│  │   Kafka           │  consume              │   PostgreSQL     │   │
│  │  Apache Kafka     │──────────────────────►│   :5432          │   │
│  │  :9092            │  ┌────────────────┐   │   DB: votes      │   │
│  └───────────────────┘  │ worker (Go)    │   └──────────────────┘   │
│                         │ Consumer Group │                           │
│                         └────────────────┘                           │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Diagrama de Arquitectura — CI/CD Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PIPELINE CI/CD                                  │
│                                                                         │
│  Developer                GitHub              GitHub Actions             │
│  ──────────               ──────              ──────────────            │
│                                                                         │
│  git push ──────────────► feature/* ─────────► [Test]                  │
│  feature branch           develop               │                       │
│                           main                  ▼                       │
│                                              [Build Docker]             │
│                                                 │                       │
│                                                 ▼                       │
│                                         [Push to GHCR]                 │
│                                         ghcr.io/repo/vote:sha          │
│                                         ghcr.io/repo/worker:sha        │
│                                         ghcr.io/repo/result:sha        │
│                                                 │                       │
│                                    (solo main)  │                       │
│                                                 ▼                       │
│                                         [Deploy via Helm]               │
│                                         helm upgrade --install          │
│                                                 │                       │
│                                                 ▼                       │
│                                         Kubernetes (Okteto)            │
│                                         vote + worker + result         │
│                                         kafka + postgresql             │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Componentes del Sistema

### Servicios de Aplicación

#### vote — Interfaz de Votación
| Atributo       | Valor                             |
|----------------|-----------------------------------|
| Tecnología     | Java 22, Spring Boot 3.4.1        |
| Puerto         | 8080                              |
| Imagen base    | maven:3.9.9 (build) + eclipse-temurin:22-jre (runtime) |
| Responsabilidad| Renderizar UI, recibir votos, publicar a Kafka |
| CI Pipeline    | [vote-ci.yml](../.github/workflows/vote-ci.yml) |

#### worker — Procesador de Votos
| Atributo       | Valor                             |
|----------------|-----------------------------------|
| Tecnología     | Go 1.24.1                         |
| Puerto         | N/A (proceso background)          |
| Imagen base    | golang:1.24.1-bookworm (build) + scratch (runtime) |
| Responsabilidad| Consumir mensajes de Kafka, persistir en PostgreSQL |
| CI Pipeline    | [worker-ci.yml](../.github/workflows/worker-ci.yml) |

#### result — Visualización de Resultados
| Atributo       | Valor                             |
|----------------|-----------------------------------|
| Tecnología     | Node.js 22, Express, Socket.IO    |
| Puerto         | 80                                |
| Imagen base    | node:22.12.0-slim                 |
| Responsabilidad| Leer resultados de PostgreSQL, transmitir por WebSocket |
| CI Pipeline    | [result-ci.yml](../.github/workflows/result-ci.yml) |

### Servicios de Infraestructura

#### Kafka — Message Broker
| Atributo       | Valor                             |
|----------------|-----------------------------------|
| Versión        | Apache Kafka 3.7.0                |
| Puerto         | 9092 (PLAINTEXT), 9093 (CONTROLLER) |
| Modo           | KRaft (sin ZooKeeper)             |
| Chart          | [infrastructure/](../infrastructure/) |

#### PostgreSQL — Base de Datos
| Atributo       | Valor                             |
|----------------|-----------------------------------|
| Versión        | PostgreSQL 16                     |
| Puerto         | 5432                              |
| Base de datos  | `votes`                           |
| Persistencia   | PersistentVolume 1Gi              |
| Chart          | [infrastructure/](../infrastructure/) |

---

## Flujo de Datos Detallado

```
1. Usuario abre http://<vote-url>:8080
   └─► vote (Java) sirve la UI con Thymeleaf

2. Usuario hace clic en "Tacos" o "Burritos"
   └─► POST /vote → vote (Java)
       └─► Kafka Producer publica mensaje:
           { "vote": "tacos", "voter_id": "abc123" }

3. Kafka retiene el mensaje en el topic "votes"
   └─► worker (Go) consume el mensaje
       └─► INSERT INTO votes (id, vote) VALUES ('abc123', 'tacos')
           ON CONFLICT (id) DO UPDATE SET vote = 'tacos'

4. Usuario abre http://<result-url>:80
   └─► result (Node.js) establece conexión WebSocket
       └─► Cada 1 segundo: SELECT vote, COUNT(*) FROM votes GROUP BY vote
           └─► Emite resultado por WebSocket al browser
               └─► UI actualiza contadores en tiempo real
```

---

## Decisiones de Arquitectura

| Decisión                        | Justificación                                          |
|---------------------------------|--------------------------------------------------------|
| Kafka como broker               | Desacoplamiento entre vote y worker; tolerancia a fallos |
| PostgreSQL para persistencia    | ACID compliance; consultas relacionales para resultados |
| Go para worker                  | Alta performance para procesamiento de mensajes; binario pequeño (`scratch` image) |
| Java/Spring Boot para vote      | Ecosistema maduro para apps web; Thymeleaf para renderizado |
| Node.js + Socket.IO para result | WebSockets nativos; ideal para push de datos en tiempo real |
| Helm para deployment            | Gestión declarativa de Kubernetes; rollbacks sencillos |
| GHCR para registry              | Integrado con GitHub; sin costo adicional; autenticación con `GITHUB_TOKEN` |
| KRaft mode en Kafka             | Elimina dependencia de ZooKeeper; arquitectura más simple |
