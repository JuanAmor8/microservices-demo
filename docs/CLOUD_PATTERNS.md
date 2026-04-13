# Patrones de Diseño de Nube

Este documento describe los patrones de diseño de nube implementados en el proyecto
**Microservices Demo**, justificando su selección y mostrando cómo se aplican en el código.

---

## Patrón 1: Event-Driven Architecture (EDA)

### Descripción

Los componentes del sistema se comunican a través de **eventos asíncronos** en lugar de llamadas
directas (RPC/REST). Un componente publica un evento y uno o más consumidores reaccionan a él de
forma independiente.

### Aplicación en el proyecto

```
  [vote - Java]                [worker - Go]
  Spring Boot         Kafka         Consumer
  ──────────    ───────────────   ──────────────
  POST /vote ──► publish event ──► consume event ──► INSERT PostgreSQL
```

- **Productor**: el servicio `vote` (Java/Spring Boot) recibe el voto del usuario y publica un
  mensaje en el topic de Kafka.
- **Broker**: Apache Kafka actúa como bus de eventos distribuido, desacoplando productor y consumidor.
- **Consumidor**: el servicio `worker` (Go) consume mensajes de Kafka y persiste los votos en PostgreSQL.

### Código relevante

- Kafka producer: [vote/src/](../vote/src/)
- Kafka consumer: [worker/main.go](../worker/main.go)
- Kafka config en Helm: [infrastructure/values.yaml](../infrastructure/values.yaml)

### Beneficios obtenidos

| Beneficio           | Descripción                                                         |
|---------------------|---------------------------------------------------------------------|
| Desacoplamiento     | `vote` no necesita saber que `worker` existe                        |
| Escalabilidad       | Se pueden agregar múltiples instancias de `worker` sin cambiar `vote` |
| Resiliencia         | Si `worker` cae, Kafka retiene los mensajes hasta que se recupere   |
| Tolerancia a fallos | El productor no falla si el consumidor está lento o caído           |

---

## Patrón 2: CQRS — Command Query Responsibility Segregation

### Descripción

Separa las operaciones de **escritura (Command)** de las de **lectura (Query)** en componentes
distintos, permitiendo optimizar cada uno de forma independiente.

### Aplicación en el proyecto

```
                    ┌─── WRITE PATH (Command) ───┐
  Usuario           │                            │
     │──── POST ───► vote (Java) ──► Kafka ──► worker (Go) ──► PostgreSQL
     │              └────────────────────────────┘                  │
     │                                                               │
     │              ┌─── READ PATH (Query) ──────────────────────────┘
     └──── GET ────► result (Node.js) ◄──── SELECT ◄── PostgreSQL
                    └────────────────────────────┘
```

- **Command side**: `vote` recibe votos y los escribe en Kafka → `worker` los persiste en PostgreSQL.
- **Query side**: `result` solo lee de PostgreSQL y expone los datos vía WebSocket a los clientes.
- Los dos paths son **completamente independientes**: escalan por separado y pueden fallar
  de forma aislada.

### Código relevante

- Command path: [vote/](../vote/) → [worker/](../worker/)
- Query path: [result/server.js](../result/server.js)
- Modelo de datos compartido: tabla `votes` en PostgreSQL

### Beneficios obtenidos

| Beneficio              | Descripción                                                        |
|------------------------|--------------------------------------------------------------------|
| Separación de concerns | Escritura y lectura tienen stacks tecnológicos distintos (Java/Go vs Node.js) |
| Escalado independiente | Se puede escalar `result` para muchos lectores sin afectar writes  |
| Optimización de reads  | `result` puede implementar caché sin afectar la integridad de writes |
| Simplicidad por lado   | Cada servicio tiene una sola responsabilidad clara                 |

---

## Patrón 3 (Complementario): Microservices Pattern

### Descripción

La aplicación se divide en **servicios pequeños, independientes y deployables por separado**, cada
uno con su propia tecnología, base de código y ciclo de vida.

### Aplicación en el proyecto

| Servicio   | Tecnología      | Responsabilidad                        | Puerto |
|------------|-----------------|----------------------------------------|--------|
| `vote`     | Java/Spring Boot | Interfaz de votación                   | 8080   |
| `worker`   | Go              | Procesamiento asíncrono de votos       | N/A    |
| `result`   | Node.js         | Visualización de resultados en tiempo real | 80 |
| `kafka`    | Apache Kafka    | Bus de mensajes (infraestructura)      | 9092   |
| `postgresql`| PostgreSQL     | Persistencia de datos (infraestructura) | 5432  |

### Características implementadas

- **Imagen Docker independiente** por servicio → deploy por separado
- **Helm chart propio** por servicio → configuración y escalado independiente
- **Pipeline CI/CD separado** por servicio → `vote-ci.yml`, `worker-ci.yml`, `result-ci.yml`
- **Polyglot persistence & programming**: cada servicio usa el lenguaje y las herramientas más
  adecuadas para su función

### Código relevante

- [vote/Dockerfile](../vote/Dockerfile), [vote/chart/](../vote/chart/)
- [worker/Dockerfile](../worker/Dockerfile), [worker/chart/](../worker/chart/)
- [result/Dockerfile](../result/Dockerfile), [result/chart/](../result/chart/)
- Pipelines CI/CD: [.github/workflows/](../.github/workflows/)

---

## Resumen de Patrones

```
┌─────────────────────────────────────────────────────────────────┐
│                    Microservices Pattern                         │
│  ┌─────────────┐   ┌───────────────┐   ┌──────────────────┐    │
│  │  vote (Java) │   │  worker (Go)  │   │  result (Node.js) │   │
│  └──────┬──────┘   └───────┬───────┘   └────────┬─────────┘    │
│         │                  │                     │              │
│  ┌──────▼──────────────────▼─────────────────────▼─────────┐   │
│  │              Event-Driven Architecture (Kafka)           │   │
│  │    vote ──publish──► Kafka ──consume──► worker ──write─► │   │
│  │                                                 PostgreSQL│   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────── CQRS ───────────────────────────┐   │
│  │  WRITE: vote → Kafka → worker → PostgreSQL              │   │
│  │  READ:  result ← SELECT ← PostgreSQL                    │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```
