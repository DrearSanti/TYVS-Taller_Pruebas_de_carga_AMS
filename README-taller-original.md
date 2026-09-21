
# Taller de Pruebas de Carga y Rendimiento

Este taller tiene como objetivo aprender a **diseñar, implementar y ejecutar pruebas de carga y rendimiento** sobre un sistema tipo API/HTTP, aplicando buenas prácticas de ingeniería, análisis de resultados y automatización con CI.

---

## Objetivo General

Comprender, diseñar e implementar **pruebas de rendimiento** (baseline, carga, stress, spike, soak) con herramientas como **JMeter / k6 / Gatling**, definiendo **SLA/SLO**, modelos de carga, datos de prueba, y generando **reportes reproducibles** para la toma de decisiones técnicas.

> **Guía visual.** Abra [`guia-visual-pruebas-de-carga.html`](guia-visual-pruebas-de-carga.html) en el navegador (descárguela y ábrala con doble clic: GitHub la muestra como código, no como página). Tiene los escenarios del taller dibujados, un simulador que reproduce cada uno segundo a segundo con y sin pool de conexiones, y las mediciones reales del servicio: percentiles, saturación, cliente frente a servidor y el defecto del pool.

---

## Índice

- [Conceptos clave](#conceptos-clave)
- [CONOCE EL TALLER](#conoce-el-taller)
  - [Estructura de proyecto](#estructura-de-proyecto)
  - [Herramientas y dependencias](#herramientas-y-dependencias)
- [Tipos de pruebas de rendimiento](#tipos-de-pruebas-de-rendimiento)
- [Diseño del plan de pruebas](#diseño-del-plan-de-pruebas)
- [Modelos de carga](#modelos-de-carga)
- [Escenarios de prueba](#escenarios-de-prueba)
- [Métricas y criterios de aceptación](#métricas-y-criterios-de-aceptación)
- [Script de prueba (k6)](#script-de-prueba-perfscriptsregister_person_k6js)
- [Dataset mínimo](#dataset-mínimo-perfdatapersonscsv)
- [Paso a paso: Ejecución básica](#paso-a-paso-ejecución-básica)
- [SLO / SLA sugeridos](#slo--sla-sugeridos)
- [Observabilidad](#observabilidad-de-la-medición-al-diagnóstico)
- [Ejecución local y en CI](#ejecución-local-y-en-ci)
- [Análisis de resultados](#análisis-de-resultados)
- [Buenas prácticas](#buenas-prácticas)
- [Para entregar](#para-entregar-con-este-taller)
- [Resumen del Taller](#hagamos-un-resumen)
- [Conclusión](#conclusión)
- [Recursos recomendados](#recursos-recomendados)
- [Créditos y uso académico](#créditos-y-uso-académico)
- [Licencia](#licencia-de-uso)

---

## Conceptos clave

- **Prueba de rendimiento**: evalúa la **capacidad del sistema** bajo diferentes niveles de carga (tiempo de respuesta, throughput, consumo de CPU/Memoria, errores).
- **Prueba de carga**: verifica el comportamiento del sistema en **niveles esperados de demanda** (usuarios concurrentes/reqs por segundo).
- **Prueba de estrés**: empuja el sistema **más allá de su capacidad** para identificar el punto de falla y su degradación.
- **Prueba de picos (spike)**: aplica aumentos **bruscos** de tráfico para evaluar elasticidad y resiliencia.
- **Prueba de resistencia (soak)**: mantiene una carga prolongada para descubrir **fugas de memoria**, acumulación de conexiones, etc.
- **SLA/SLO/SLI**: conceptos fundamentales de confiabilidad **acordados/objetivo** (p.ej., *p95 Latency < 300 ms, Error Rate < 1%*).

---

## CONOCE EL TALLER

### Estructura de proyecto

```text
.
├─ README.md                     # este documento
├─ guia-visual-pruebas-de-carga.html  # guía visual: mediciones reales y simulador de ejecución
├─ defectos.md                   # ejemplo del profesor
├─ defectos_template.md          # plantilla para su entrega
├─ registraduria/                # SISTEMA BAJO PRUEBA (Spring Boot)
│   ├─ pom.xml
│   └─ src/main/...              # el servicio con POST /register
└─ perf/
    ├─ scripts/                  # register_person_k6.js, register_voter_k6.js
    ├─ data/                     # persons.csv, voters.csv
    ├─ results/                  # resúmenes de cada corrida (no se versionan)
    ├─ ci/                       # plantilla de GitHub Actions
    └─ lab/                      # mediciones de la presentación (material del profesor)
```

> Note que el sistema bajo prueba (`registraduria/`) y las pruebas (`perf/`) son hermanos. Los comandos de Maven se ejecutan **dentro de `registraduria/`**; los de k6, **desde la raíz**.

### Herramientas y dependencias

- **JMeter** (GUI + CLI): para crear planes de prueba (.jmx) y ejecutarlos en CLI para CI/CD.
- **k6** (CLI-first): scripts en JS, fácil de versionar, buen soporte de métricas.
- **Gatling** (Scala): alto desempeño, reportes HTML detallados.
- **Soporte de monitoreo**: Prometheus/Grafana, APM (New Relic, Datadog, Elastic APM).
- **Utilitarios**: `jq`, `csvkit`, `python` para post-procesamiento de resultados.

> Puedes usar **JMeter** como herramienta principal y complementar con k6 o Gatling según preferencias del equipo.

---

## Tipos de pruebas de rendimiento

1. **Smoke de performance**: 1–2 min, baja carga, valida que el entorno responde.
2. **Baseline**: establece la línea base (sin optimizaciones) para comparar.
3. **Carga**: demanda esperada (p.ej., 50–200 usuarios concurrentes).
4. **Estrés**: incrementos progresivos hasta saturación y fallo controlado.
5. **Picos (Spike)**: saltos abruptos (x5–x10) para medir recuperación.
6. **Resistencia (Soak)**: 1–4 horas (o más) a carga estable para detectar degradación.

---

## Diseño del plan de pruebas

- **Alcance**: endpoints críticos (p.ej., `POST /login`, `GET /orders`, `POST /register`).

**Ejemplo:**

**Ruta:** `POST /register`  
**Body esperado (JSON):**

```json
{
  "name": "Ana",
  "id": 100,
  "age": 30,
  "gender": "FEMALE",
  "alive": true
}
```

**Respuesta esperada:** `200 OK` con cuerpo `VALID` (texto).

> Puedes ajustar las validaciones del script si tu servicio responde de forma diferente (por ejemplo, JSON con campos específicos).

- **SLA/SLO**: p95 < 300 ms, p99 < 800 ms, error rate < 1%.
- **Datos de prueba**: usuarios, tokens, catálogos; evitar “caché feliz” usando **parametrización** y **correlación**.
- **Ambiente**: staging lo más **representativo** posible (réplicas, RAM/CPU, versión).
- **Calentamiento (warmup)**: 2–5 min para estabilizar JIT/cachés.
- **Monitoreo**: CPU, Mem, GC, hilos, conexiones, I/O, tiempos de DB y colas (RabbitMQ/Kafka si aplica).
- **Riesgos**: límites de rate, *throttling*, dependencias externas, *feature flags*.

---

## Modelos de carga

- **Usuarios concurrentes (VUs)**: cantidad de usuarios simultáneos.
- **Req/s (RPS)**: útil para APIs idempotentes.
- **Rampa (ramp-up/ramp-down)**: crecimiento/descenso controlado.
- **Closed vs Open models**: *closed* controla VUs; *open* controla la tasa de llegada (RPS).
- **Patrones de tráfico**: horario laboral, eventos, campañas, estacionalidad.

---

## Pre-requisitos

- Servicio **Spring Boot** corriendo localmente en `http://localhost:8080` (o URL base equivalente).
- **k6** instalado: <https://grafana.com/docs/k6/latest/get-started/installation/>
- (Opcional) Base de datos o perfil `perf` para datos sintéticos.

## Instalación de k6

### Windows

#### Opción 1 – Chocolatey

```bash
choco install k6
```

#### Opción 2 – Winget

```bash
winget install grafana.k6
```

#### Opción 3 – Manual

1. Descarga desde la página oficial:  
   [https://grafana.com/docs/k6/latest/get-started/installation/](https://grafana.com/docs/k6/latest/get-started/installation/)
2. Descomprime el `.zip` en:  
   `C:\Program Files\k6\`
3. Agrega esa ruta al **PATH** de tu sistema.
4. Verifica la instalación:

```bash
k6 version
```

### Linux / Mac

```bash
curl -s https://packagecloud.io/install/repositories/loadimpact/k6/script.deb.sh | sudo bash
sudo apt install k6
```

> Verifica siempre con `k6 version` que esté disponible globalmente.

---

## Escenarios de prueba

Estos son los escenarios que **implementan los scripts**. Se activan con `--env SCENARIO=<nombre>`:

| `SCENARIO` | Modelo de carga | Forma | Duración | Para qué |
|---|---|---|---|---|
| `baseline` | cerrado, VUs constantes | 20 VUs | 5 min | Referencia estable para comparar |
| `load` | cerrado, rampa | 0→200 VUs (2 min), sostener 10 min, bajar 2 min | 14 min | Comportamiento en carga esperada |
| `stress` | cerrado, rampa | 200→600 VUs (5 min), sostener 3 min | 10 min | Encontrar el punto de saturación |
| `spike` | cerrado, rampa | 50→300 VUs (1 min), volver a 50 | 4 min | Recuperación tras un pico súbito |
| `soak` | cerrado, VUs constantes | 100 VUs | 2 h | Fugas de memoria, degradación por GC |
| `regression` | cerrado, VUs constantes | 20 VUs | 5 min | Comparar dos builds |
| `arrival` * | **abierto**, tasa de llegada | 100 req/s | 5 min | SLO expresado en throughput |

* Solo en `register_voter_k6.js`.

> **Cerrado vs. abierto.** En el modelo *cerrado* usted fija cuántos usuarios simultáneos hay; el throughput resultante depende de lo rápido que responda el sistema — si se degrada, usted le envía **menos** carga, justo cuando debería enviarle más. En el modelo *abierto* usted fija las peticiones por segundo y la cola crece si el sistema no da abasto, que es como se comporta el tráfico real. Compare `baseline` con `arrival` y observe la diferencia.

---

## Métricas y criterios de aceptación

- **Latencias**: p50/p90/p95/p99, *max*.
- **Throughput**: req/s.
- **Errores**: 4xx, 5xx, timeouts, *connection reset*.
- **Recursos**: CPU, RAM, GC, FD, *threads*, conexiones DB, colas.
- **Capacidad**: utilización del 70–80% con SLO cumplidos.
- **Criterios**: aprobar si p95 ≤ SLO y errores ≤ 1%; reprobar si se exceden límites o hay *leaks*.

---

## Dataset mínimo `perf/data/persons.csv`

Ejemplo de **5 filas** (puedes ampliarlo a cientos/miles):

```csv
id,name,age,gender,alive
101,Juan,28,MALE,true
102,María,31,FEMALE,true
103,Carlos,25,MALE,true
104,Sofia,27,FEMALE,true
105,Andrés,35,MALE,true
```

---

## Script de prueba `perf/scripts/register_person_k6.js`

El script envía solicitudes `POST /register` con datos del CSV, valida **status 200** y que el cuerpo sea exactamente `VALID` (no que lo *contenga*: `INVALID_AGE` también contiene la palabra `VALID`).  
Variables de entorno soportadas:

- `BASE_URL` (por defecto `http://localhost:8080`)
- `DATA_FILE` (por defecto `perf/data/persons.csv`)
- `SCENARIO`: `baseline` | `load` | `stress` | `spike` | `soak` | `regression` (por defecto `baseline`)
- `TIMEOUT_MS`: timeout del cliente HTTP (por defecto `2000`)

> Si ya tienes el archivo desde el taller, úsalo tal cual. Si no, crea uno con el contenido proporcionado anteriormente.

---

## Paso a paso: **Ejecución básica**

> **Desde dónde ejecutar cada comando.** Los comandos de Maven van dentro de `registraduria/` (ahí está el `pom.xml`); los de k6 van desde la **raíz del repositorio**, porque las rutas `perf/...` son relativas a ella. Es el error más común de este taller.

### 1) Levanta el servicio

Desde la carpeta `registraduria/`:

```bash
cd registraduria
mvn -DskipTests spring-boot:run
```

O empaquetando primero:

```bash
cd registraduria
mvn -DskipTests clean package
java -jar target/registraduria-1.0-SNAPSHOT.jar
```

Confirma que el servicio está arriba:

```bash
curl http://localhost:8080/actuator/health
# {"status":"UP", ...}
```

Y que `/register` responde `200 OK` con `VALID` para un JSON válido:

```bash
curl -X POST http://localhost:8080/register \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Ana\",\"id\":999001,\"age\":30,\"gender\":\"FEMALE\",\"alive\":true}"
```

> Si repite ese `curl` con el **mismo id**, la segunda vez obtendrá `200 OK` con el cuerpo `DUPLICATED`, no `VALID`. La regla de unicidad es correcta; use otro id para volver a probar. Este detalle importa más de lo que parece: es la razón por la que los scripts generan ids únicos por VU e iteración.

### 2) Baseline (medición corta de referencia)

**Vuelva a la raíz del repositorio** y ejecute:

```bash
cd ..
k6 run --env BASE_URL=http://localhost:8080 --env SCENARIO=baseline \
       perf/scripts/register_person_k6.js
```

> **No use `set VAR=...` para pasar la configuración.** En `cmd` de Windows, `set BASE_URL="http://localhost:8080"` guarda **las comillas dentro del valor** y la URL resulta inválida; y un comando que empiece por `set` no ejecuta k6, solo define una variable. La forma portable —igual en Windows, macOS y Linux— es `--env`, como arriba.

### 3) Carga (rampa hasta 200 VUs)

```bash
k6 run --env BASE_URL=http://localhost:8080 --env SCENARIO=load \
       perf/scripts/register_person_k6.js
```

Escenarios disponibles en `SCENARIO`: `baseline`, `load`, `stress`, `spike`, `soak`, `regression` (y `arrival` en el script de votantes).

### 4) Verificación del resultado de negocio

El segundo script comprueba algo distinto: que bajo carga el servicio siga respondiendo lo **correcto**, no solo un `200`.

```bash
k6 run --env BASE_URL=http://localhost:8080 --env SCENARIO=baseline \
       perf/scripts/register_voter_k6.js
```

Fíjese en la métrica `register_failed`: mide el porcentaje de respuestas cuyo resultado de negocio **no** fue el esperado según el dataset.

El CSV cubre las seis clases de equivalencia del dominio, incluidos los dos valores límite que separan a las dos que más se confunden:

| `expected` | Filas | Qué representa |
|---|---|---|
| `VALID` | 333 | persona viva, mayor de edad, id nuevo |
| `UNDERAGE` | 99 | edad de 0 a 17 — incluye la fila de **edad 0** |
| `DEAD` | 70 | `alive=false` |
| `INVALID_AGE` | 10 | edad negativa o mayor de 120 |

La fila de **edad 120** espera `VALID` y la de **edad 121** espera `INVALID_AGE`: son el borde exacto, y bajo carga verifican que la regla no se degrada.

> **Reinicie el servicio entre corridas.** Los ids que genera el script son únicos *dentro* de una ejecución, pero la base H2 vive mientras viva el proceso. Si repite la prueba sin reiniciar, los mismos ids ya están registrados y **todo lo que esperaba `VALID` devuelve `DUPLICATED`**: verá `register_failed` dispararse y el umbral cruzarse, sin que el servicio tenga nada malo.
>
> Si no quiere reiniciar, desplace el rango de ids:
>
> ```bash
> k6 run --env BASE_URL=http://localhost:8080 --env SCENARIO=baseline \
>        --env ID_BASE=700000000 perf/scripts/register_voter_k6.js
> ```
>
> No se arregla metiendo la marca de tiempo en el id: el campo es un `int` de Java y con 600 VUs el escenario de estrés ya consume la tercera parte del rango. **La gestión del estado de prueba es parte del diseño de una prueba de carga**, no un detalle de implementación — y es de las primeras cosas que se rompen cuando estas pruebas se llevan a un entorno compartido.

### 5) Resultados

Al finalizar, cada script imprime un resumen y escribe su detalle en `perf/results/`:

```text
{
  "escenario": "baseline",
  "peticiones": 725,
  "p95_ms": 5,
  "resultado_negocio_incorrecto": 0
}
```

Y el resumen completo queda en `perf/results/summary-<escenario>.json`.

> **Cuidado con `-o json=`.** Esa opción vuelca **cada punto de dato individual**, no un resumen: una corrida de 10 segundos con 5 VUs genera un archivo de **más de 200 MB**. Úsela solo si va a post-procesar los datos, y **nunca** la versione. Para el análisis normal basta con el `summary-*.json` que genera `handleSummary`.

Documente un breve análisis con los números obtenidos.


---

## SLO / SLA sugeridos (ajústalos a tu entorno)

| Métrica         | Objetivo            |
|-----------------|---------------------|
| p95 latencia    | ≤ 300 ms            |
| p99 latencia    | ≤ 800 ms            |
| Error rate      | < 1%                |
| Throughput base | ≥ 100 req/s (referencia) |

> Considera tu hardware/infra: en máquinas locales, el throughput puede ser menor; en staging/cluster, mayor.

---

## Ejecución local y en CI

- **Local**: validar un *smoke* corto (1–2 min) antes de lanzar cargas largas.
- **CI/CD**:
  - GitHub Actions / Jenkins / GitLab CI ejecutan los escenarios clave.
  - Publicar artefactos: los `summary-*.json` de cada corrida.
  - **Gates** de calidad: fallar el *pipeline* si p95 > SLO o la tasa de error > 1%.
  - Separar los escenarios cortos (en cada PR) de los largos (nocturnos).

El repositorio trae el flujo listo en [`perf/ci/github-actions.yml`](perf/ci/github-actions.yml).

> **GitHub Actions solo lee los workflows de `.github/workflows/`.** El archivo está en `perf/ci/` para que quede versionado junto al resto del material de rendimiento, pero **no se ejecuta desde ahí**. Cópielo:
>
> ```bash
> mkdir -p .github/workflows
> cp perf/ci/github-actions.yml .github/workflows/perf.yml
> ```

Tres decisiones de ese flujo que conviene entender:

**1. El workflow levanta el servicio él mismo.** Es el error más común al llevar pruebas de rendimiento a CI: se configura k6 impecablemente y se apunta a un servicio que nadie arrancó. El flujo empaqueta, lanza el jar en segundo plano y **espera al `/actuator/health`** antes de seguir:

```yaml
      - name: Levantar el servicio en segundo plano
        run: |
          nohup java -jar target/registraduria-1.0-SNAPSHOT.jar > /tmp/app.log 2>&1 &
          for i in $(seq 1 60); do
            if curl -sf http://localhost:8080/actuator/health > /dev/null; then
              echo "Servicio arriba"; exit 0
            fi
            sleep 2
          done
          echo "El servicio no arrancó a tiempo"; cat /tmp/app.log; exit 1
```

Un `sleep 30` fijo en lugar de ese bucle es una fuente clásica de pruebas inestables: a veces alcanza, a veces no.

**2. En un pull request solo corre el escenario corto.** El escenario `load` dura casi 15 minutos y bloquearía la revisión. Los escenarios largos van en `workflow_dispatch` o en una ejecución nocturna.

**3. El gate no necesita lógica adicional.** Los `thresholds` del script ya son el criterio: si el p95 supera el SLO o la tasa de error pasa del 1%, k6 termina con código distinto de cero y el paso falla solo.

---

## Observabilidad: de la medición al diagnóstico

Hasta aquí todo lo que hemos medido viene **del lado del cliente**: k6 dice cuántas peticiones envió y cuánto tardaron. Eso responde *qué* pasó, pero no *por qué*.

Cuando el p95 se dispara, la pregunta útil es otra: ¿se agotó el pool de hilos? ¿el recolector de basura está pausando la JVM? ¿la base de datos es el cuello de botella? Ninguna de esas se responde desde fuera.

### Métricas del servidor con Actuator

El servicio ya expone métricas (ver `application.properties`):

```properties
management.endpoints.web.exposure.include=health,metrics,prometheus
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.metrics.distribution.percentiles.http.server.requests=0.5,0.95,0.99
```

Con el servicio arriba:

```bash
# Latencia medida por el SERVIDOR
curl -s "http://localhost:8080/actuator/metrics/http.server.requests" | jq

# Hilos en uso
curl -s "http://localhost:8080/actuator/metrics/jvm.threads.live" | jq

# Memoria y pausas de GC
curl -s "http://localhost:8080/actuator/metrics/jvm.gc.pause" | jq
```

### El ejercicio: cliente contra servidor

1. Anote el p95 que reporta k6 al final de una corrida `load`.
2. Consulte el p95 de `http.server.requests` en Actuator.
3. Compare.

La diferencia entre ambos **no es ruido**: es el tiempo que la petición pasó viajando por la red y, sobre todo, **esperando en la cola** antes de que un hilo la atendiera. Si el servidor dice 20 ms y el cliente dice 400 ms, el problema no está en su código de negocio: está en la saturación.

### Un cuello de botella real, en este mismo repositorio

Mire `RegistryRepository.getConnection()`:

```java
private Connection getConnection() throws SQLException {
    return DriverManager.getConnection(jdbcUrl, username, password);
}
```

Se abre una **conexión nueva en cada operación**, sin pool. Y `registerVoter` hace dos operaciones por petición (`existsById` y `save`), así que son **dos conexiones nuevas por request**.

Con 200 VUs eso significa cientos de conexiones creadas y destruidas por segundo. Es exactamente el tipo de defecto que:

- una prueba unitaria **no** detecta (funciona perfectamente con un usuario),
- una prueba de integración **no** detecta (también funciona),
- una prueba de carga **sí** detecta, pero solo reporta el síntoma (p95 alto),
- y solo la observabilidad **explica**.

#### Actividades

1. Ejecute el escenario `load` y registre el p95 de k6 y el de Actuator.
2. Consulte `jvm.threads.live` durante la corrida. ¿Cuántos hilos hay activos en el pico?
3. Agregue un pool de conexiones (HikariCP viene con Spring Boot) y repita la medición. Documente en el Wiki el antes y el después.
4. Explique por qué este defecto no aparece en ninguno de los otros tres talleres.

> **La conclusión que buscamos**: una prueba de carga sin observabilidad le dice que algo va mal; con observabilidad le dice **qué** arreglar. La primera genera reuniones; la segunda, cambios de código.

---

## Análisis de resultados

1. **Valida primero errores y p95**: si no cumple SLO, no sigas afinando.
2. **Correlaciona** latencias con **CPU/RAM/GC/DB** para ubicar cuellos de botella.
3. **Perf triage**:
   - ¿Baja reutilización de conexiones? ⇒ HikariCP/pool tuning.
   - ¿Elevada latencia en DB? ⇒ índices, *query plan*, N+1, cacheo.
   - **I/O bloqueante** en APIs externas ⇒ *timeouts*, *circuit breakers*, *bulkheads*.
   - **GC/heap**: revisa *young/old gen*, *pause times*.
4. **Compara con baseline**: muestra mejoras en %.
5. **Repite**: optimiza → re-ejecuta → documenta.

---

## Buenas prácticas

1. **Datos realistas**: variabilidad para evitar cachés engañosos.
2. **Correlación**: extrae tokens/IDs en lugar de valores fijos.
3. **Warmup**: estabiliza JIT y cachés antes de medir.
4. **Modelo de carga correcto**: *open* vs *closed* según negocio.
5. **Evidencia reproducible**: versiona scripts, datos y reportes.
6. **No mezclar** cambios de código y de entorno entre corridas.
7. **Observabilidad**: logs con *traceId*, métricas, *profilers* puntuales.

---

## PARA ENTREGAR CON ESTE TALLER

### 1) Repositorio

- **Repositorio Git** con carpeta `perf/` y scripts (JMeter/k6/Gatling).
- `README.md` con **SLA/SLO**, escenarios, cómo ejecutar y interpretar resultados.
- **Datos de prueba** en `perf/data/` (sin información sensible).
- **Resultados** (`perf/results/`) con los `summary-*.json` de cada corrida.

### 2) Wiki (obligatoria)

Estructura mínima sugerida:

- **Inicio**: dominio del sistema y objetivos de rendimiento.
- **Tipos de pruebas**: baseline, carga, stress, spike, soak (con tablas).
- **Modelos de carga**: VUs vs RPS; *open* vs *closed*.
- **Plan de pruebas**: SLA/SLO, escenarios, ambiente, riesgos.
- **Ejecución**: comandos, *pipeline* CI, artefactos.
- **Resultados**: capturas de reportes y análisis (p95, errores, recursos).
- **Conclusiones técnicas**: hallazgos y *trade-offs*.
- **Mejoras propuestas**: acciones de performance tuning.

### 3) Escenarios y scripts

- ≥ **3 escenarios** (baseline, carga, estrés) implementados y versionados.

- `perf/scripts/register_voter_k6.js`
- `perf/data/voters.csv` (512 filas, con la columna `expected`, cubriendo las seis clases de equivalencia)
- `perf/results/*` (`baseline.json`, `load.json`)
- Breve análisis: p95/p99, error rate, hallazgos y próximas acciones.

- **Parametrización** y **correlación** en el script (tokens/IDs dinámicos).
- **Asserts** de tiempo de respuesta y código HTTP.

### 4) Reportes y cobertura de escenarios

- Un `summary-<escenario>.json` por cada escenario ejecutado (los genera `handleSummary`).

> k6 **no genera reportes HTML** de forma nativa, y `.jtl` es un formato de JMeter. Si quiere un HTML, use `K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=perf/results/reporte.html k6 run ...`, pero para la entrega basta con el JSON del resumen.
- Tabla de **comparación** vs baseline con % de mejora/degradación.

### 5) Matriz de pruebas de rendimiento

| Escenario | Modelo | Duración | SLO | Resultado | Artefactos |
|---|---|---|---|---|---|
| Baseline | 50 VUs, p95<300ms | 15 min | p95<300ms | Cumple / No | `results/baseline-report/` |
| Carga | 0→200 VUs 20 min | p95<500ms | Cumple / No | `results/load-report/` |
| Estrés | 200→600 VUs | Error<1% | Cumple / No | `results/stress-report/` |

### 6) Gestión de defectos

- **`defectos.md`** con al menos 1 hallazgo (ej.: N+1, timeout, fuga de memoria), evidencia y estado.

### 7) Integración continua

- *Pipeline* que ejecute **baseline** y **carga** en cada PR; **estrés/soak** on-demand.
- **Gates** automáticos (fallar si SLO no se cumple).

### 8) Reflexión final (en el Wiki)

- ¿Qué métrica fue más sensible y por qué?
- ¿Cuál fue el principal cuello de botella y cómo lo mitigaste?
- ¿Qué cambiarías del diseño para mejorar el rendimiento?

### 9) Rúbrica – Taller de Pruebas de Carga y Rendimiento

| **Criterios de evaluación** | **Indicadores de cumplimiento** | **Excelente (5 pts)** | **Bueno (4 pts)** | **Necesita mejorar (3.5 pts)** | **Deficiente (2.5 pts)** | **No cumple (0 pts)** |
|---|---|---|---|---|---|---|
| **Estructura del repositorio** | `perf/` con scripts, datos, resultados y README claro. | Estructura impecable y reproducible. | Clara, pocos ajustes. | Parcialmente ordenada. | Desorden o ejecuciones fallan. | No entrega. |
| **Plan de pruebas (SLA/SLO, modelos, escenarios)** | Definición y justificación. | Completo y alineado al negocio. | Completo con leves omisiones. | Parcial e impreciso. | Incompleto y confuso. | Ausente. |
| **Scripts (parametrización, correlación, asserts)** | Calidad técnica. | Correctos, robustos y comentados. | Correctos con detalles menores. | Limitados o frágiles. | Errores o sin correlación. | No existen. |
| **Ejecución y artefactos** | Resúmenes JSON por escenario y evidencias. | Artefactos limpios y comparables. | Artefactos adecuados. | Evidencia parcial. | Artefactos incompletos. | Sin evidencia. |
| **Análisis de resultados** | Diagnóstico y recomendaciones. | Análisis profundo y accionable. | Análisis correcto. | Superficial o sin datos. | Conclusiones erróneas. | No analiza. |
| **CI/CD y gates** | Automatización y umbrales. | Pipeline con gates efectivos. | Pipeline básico. | Pipeline parcial. | Pipeline defectuoso. | Sin CI. |
| **Matriz de rendimiento** | Tabla y trazabilidad. | Completa y consistente. | Adecuada con omisiones leves. | Incompleta. | Confusa. | Ausente. |
| **Gestión de defectos** | Registro y estado. | Casos bien documentados. | Casos adecuados. | Superficial. | Sin evidencia. | Ausente. |
| **Reflexión técnica** | Aprendizajes y mejoras. | Profunda y clara. | Correcta. | Breve. | Vaga. | Ausente. |
| **Observabilidad del servidor** | Correlación entre métricas de cliente (k6) y de servidor (Actuator). | Compara p95 de k6 con `http.server.requests` y diagnostica la causa raíz de la degradación. | Recoge ambas métricas y las compara, sin llegar a la causa. | Solo recoge métricas del servidor, sin correlacionar. | Menciona Actuator sin datos. | No usa observabilidad. |

> **Cómo suma**: 10 criterios × 5 pts = **50 puntos**.

| Rango de puntaje | Desempeño                                                |
| ---------------- | -------------------------------------------------------- |
| 45 – 50          | Excelente dominio técnico y metodológico.                |
| 35 – 44          | Buen trabajo con documentación o análisis parcial.       |
| 30 – 34          | Cumple con lo básico pero sin profundidad.               |
| < 30             | No cumple con los criterios mínimos del taller/proyecto. |

---

## Hagamos un resumen

- Define **SLA/SLO**, escenarios y **modelo de carga** adecuado.
- Versiona **scripts, datos y resultados** para reproducibilidad.
- Ejecuta en **CI** con **gates** automáticos.
- Analiza **p95, errores y recursos**; prioriza cuellos de botella.
- Itera: **mide → optimiza → vuelve a medir**.

---

## Conclusión

Las **pruebas de carga y rendimiento** brindan evidencia objetiva para **dimensionar, optimizar y dar confiabilidad** al sistema bajo demanda realista. Integradas a CI/CD, permiten **evitar degradaciones** y sostener la calidad en producción.

---

## Recursos recomendados

- Apache JMeter (User Manual)
- k6 (docs.k6.io)
- Gatling (gatling.io)
- Google SRE Book – Service Level Objectives
- *Systems Performance* – Brendan Gregg
- *Release It!* – Michael Nygard

---

## Créditos y uso académico

**Autor:** César Augusto Vega Fernández
**Curso:** Testing y Validación de Software
**Programa:** Maestría en Ingeniería de Software – Universidad de La Sabana
**Año:** 2025

Este taller es material académico para el curso *Testing y Validación de Software* y está orientado a fortalecer competencias de **planificación y ejecución de pruebas de rendimiento**, automatización y análisis.

---

## Licencia de uso

Este material se distribuye bajo **CC BY-NC-SA 4.0**. Puedes **usar, adaptar o compartir** con fines educativos, siempre que:

1. Se reconozca la autoría del profesor **César Augusto Vega Fernández**.
2. No se utilice con fines comerciales.
3. Las obras derivadas se distribuyan bajo la misma licencia.
