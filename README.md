# Taller de Pruebas de Carga y Rendimiento — Caso Registraduría

Entrega del grupo para Testing y Validación de Software, Universidad de La Sabana.

El material original del profesor se conserva en [`README-taller-original.md`](README-taller-original.md): conceptos, tipos de prueba y la rúbrica de evaluación. Este documento describe **nuestra** entrega: qué medimos, cómo se reproduce y cómo se leen los resultados.

El análisis completo de las corridas está en la [wiki del repositorio](https://github.com/DrearSanti/TYVS-Taller_Pruebas_de_carga_AMS/wiki).

## Sistema bajo prueba

Servicio Spring Boot 2.7.18 sobre Tomcat 9.0.83, con base de datos H2 en memoria. Expone un único endpoint de negocio:

`POST /register` recibe nombre, identificador, edad, género y estado de vida, y devuelve **siempre HTTP 200** con un cuerpo de texto que indica el resultado.

| Cuerpo | Significado |
| --- | --- |
| VALID | Persona viva, mayor de edad, identificador nuevo. Único registro exitoso. |
| UNDERAGE | Edad entre 0 y 17 años. |
| DEAD | El campo `alive` viene en `false`. |
| INVALID_AGE | Edad negativa o mayor de 120. |
| DUPLICATED | El identificador ya existe en la base. |

Esto condiciona todo el diseño de las pruebas: **el código HTTP no distingue el resultado**. Una prueba que solo verifique `status 200` daría por bueno un servicio que rechaza al cien por ciento de los solicitantes. Por eso la validación se hace contra el resultado de negocio esperado, fila por fila del dataset.

## Estructura del repositorio

```text
.
├─ README.md                          # este documento
├─ README-taller-original.md          # material y rúbrica del profesor
├─ defectos.md                        # registro de defectos (ejemplo del profesor)
├─ defectos_template.md               # plantilla de la entrega
├─ guia-visual-pruebas-de-carga.html  # guía visual con simulador
├─ .github/workflows/perf.yml         # pipeline de integración continua
├─ registraduria/                     # SISTEMA BAJO PRUEBA (Spring Boot)
└─ perf/
   ├─ scripts/   # register_voter_k6.js, register_person_k6.js
   ├─ data/      # voters.csv, persons.csv
   ├─ results/   # resúmenes de cada corrida
   ├─ ci/        # plantilla original del workflow (no se ejecuta desde aquí)
   └─ lab/       # mediciones de la presentación (material del profesor)
```

El sistema bajo prueba (`registraduria/`) y las pruebas (`perf/`) son hermanos. Los comandos de Maven se ejecutan **dentro de `registraduria/`**; los de k6, **desde la raíz**.

## SLA y SLO

| Métrica | Objetivo | Justificación |
| --- | --- | --- |
| Latencia p95 | ≤ 300 ms | Umbral por debajo del cual una interacción se percibe inmediata. |
| Latencia p99 | ≤ 800 ms | Acota la cola: el 1 % peor no debe degradarse sin control. |
| Tasa de error HTTP | < 1 % | Disponibilidad efectiva del endpoint. |
| Tasa de resultado de negocio incorrecto | < 1 % | Específico de este servicio: un 200 con el cuerpo equivocado es un fallo. |
| Throughput de referencia | ≥ 100 req/s | Capacidad mínima esperada en operación normal. |

Los cuatro primeros están escritos como `thresholds` dentro de los scripts de k6, de modo que una corrida que los incumpla termina con código de salida distinto de cero. **Eso permite usarlos como gate del pipeline sin lógica adicional**: no hay que parsear el JSON ni escribir comparaciones.

Los umbrales representan el acuerdo de servicio, no la mejor marca observada. Se mantienen deliberadamente por encima de lo medido: un gate calibrado a la medición falla por variación natural del entorno de ejecución, y un gate que falla sin motivo termina ignorado.

## Escenarios

Se seleccionan con `--env SCENARIO=<nombre>`.

| Escenario | Modelo | Perfil | Duración |
| --- | --- | --- | --- |
| `baseline` | Cerrado, VUs constantes | 20 VUs | 5 min |
| `load` | Cerrado, rampa | 0→200 (2m), 200 (10m), →0 (2m) | 14 min |
| `stress` | Cerrado, rampa | 200→600 (5m), 600 (3m), →0 (2m) | 10 min |
| `spike` | Cerrado, pico | 50→300 (1m), →50 (2m), →0 (1m) | 4 min |
| `soak` | Cerrado, VUs constantes | 100 VUs | 2 h |
| `arrival` | **Abierto**, tasa de llegada | 100 req/s | 5 min |

Los cinco primeros fijan **usuarios concurrentes**. `arrival` fija **peticiones por segundo**, que es el modelo correcto cuando el SLO se expresa en throughput. La diferencia importa: en modelo cerrado, si el servicio se degrada recibe menos carga en lugar de más, porque cada usuario virtual espera la respuesta antes de enviar la siguiente petición. El modelo se autorregula y suaviza la degradación que debería estar midiendo.

## Requisitos

- JDK 17
- Maven 3.8 o superior
- k6 0.49 o superior

Instalación de k6 según el sistema:

| Sistema | Comando |
| --- | --- |
| macOS | `brew install k6` |
| Windows | `winget install k6 --source winget` |
| Linux | Ver la [documentación oficial de k6](https://grafana.com/docs/k6/latest/set-up/install-k6/) |

El pipeline fija la versión `v0.49.0` de forma explícita, para que las corridas automáticas sean comparables entre sí a lo largo del tiempo. Localmente no hace falta esa versión exacta: se verificó que k6 2.2.0 ejecuta los scripts sin modificaciones y genera un resumen con las mismas claves de primer nivel que los archivos versionados. Si reproduce las corridas con una versión distinta a la del pipeline, anótelo junto a sus resultados.

## Ejecución local

Hacen falta **dos terminales**: una queda ocupada por el servicio, la otra ejecuta las verificaciones y k6.

Terminal 1, compilar y levantar el servicio:

```bash
cd registraduria
mvn -DskipTests clean package
java -jar target/registraduria-1.0-SNAPSHOT.jar
```

La primera compilación descarga las dependencias de Maven y puede tardar varios minutos; las siguientes toman segundos. El servicio queda en primer plano y termina de arrancar con la línea `Started RegistryApplication`.

Terminal 2, verificar y ejecutar:

```bash
curl http://localhost:8080/actuator/health

# Desde la RAÍZ del repositorio, no desde registraduria/
k6 run perf/scripts/register_voter_k6.js \
  --env BASE_URL=http://localhost:8080 \
  --env SCENARIO=baseline
```

> **La corrida sobrescribe un archivo versionado.** La función `handleSummary` escribe en `perf/results/summary-voters-<escenario>.json`, y esos archivos están en el repositorio: son los resultados oficiales de la campaña. Ejecutar un escenario localmente los reemplaza por los suyos. Revise `git status` antes de hacer commit, y restaure con `git checkout -- perf/results/` si no quiere conservar su corrida.

**Reinicie el servicio entre escenarios.** La base H2 vive en memoria mientras viva el proceso de Java. Sin reinicio, los identificadores que genera el script chocan con los de la corrida anterior y todo lo que esperaba `VALID` devuelve `DUPLICATED`, lo que dispara la métrica de resultado incorrecto sin que el servicio tenga ningún problema. Si no puede reiniciar, desplace el rango con `--env ID_BASE=700000000`.

### Parametrización

| Variable | Por defecto | Para qué |
| --- | --- | --- |
| `BASE_URL` | `http://localhost:8080` | Dirección del servicio |
| `SCENARIO` | `baseline` | Escenario a ejecutar |
| `DATA_FILE` | autodetección | Ruta alterna del CSV |
| `TIMEOUT_MS` | `2000` | Timeout por petición |
| `SLEEP_MS` | `100` (voter) / `0` (person) | Pausa entre iteraciones |
| `ID_BASE` | `0` | Desplaza el rango de identificadores (solo `register_voter`) |

Se pasan con `--env` y no como variables de entorno del sistema: en CMD de Windows, `set BASE_URL="http://..."` guarda las comillas dentro del valor y produce una URL inválida.

## Integración continua

El pipeline está en [`.github/workflows/perf.yml`](.github/workflows/perf.yml). Levanta el servicio **en el propio runner**, espera a `/actuator/health` con un bucle de reintentos, instala k6 en una versión fija y ejecuta el gate.

| Disparador | Escenario | Motivo |
| --- | --- | --- |
| Pull request a `master` | `baseline` (5 min) | Tiempo tolerable para una revisión |
| Programado, 06:00 UTC | `load` (14 min) | Cobertura de carga nominal sin bloquear a nadie |
| Manual (`workflow_dispatch`) | el que se elija | Estrés, pico y resistencia bajo demanda |

**Desviación documentada:** la rúbrica pide ejecutar baseline *y* carga en cada pull request. Carga dura catorce minutos y estrés diez; sumados al empaquetado bloquearían cada revisión más de media hora. Se optó por baseline en cada pull request y carga en ejecución nocturna, con todos los escenarios disponibles bajo demanda. La cobertura es la misma en el tiempo; lo que cambia es cuándo se paga.

### Ejecutar el pipeline manualmente

1. Pestaña **Actions** → workflow **perf-tests**.
2. Botón **Run workflow**.
3. Elegir el escenario en el desplegable y confirmar.

Solo se corre el script `register_voter_k6.js`, y es deliberado: valida latencia **y** resultado de negocio. `register_person_k6.js` únicamente verifica que el cuerpo diga `VALID`, así que el gate del primero es estrictamente más fuerte.

### Artefactos que publica

Cada corrida publica un artefacto llamado `perf-results-<escenario>-<número>`, descargable desde la página de la ejecución en Actions. Contiene los `summary-*.json` generados por `handleSummary`.

No se publica el volcado de `-o json=`, que registra cada punto de dato individual y supera los doscientos megabytes por corrida. Para el análisis basta el resumen.

## Cómo leer los resultados

Cada corrida de `register_voter_k6.js` escribe **un** archivo: `perf/results/summary-voters-<escenario>.json`, además de un resumen corto por pantalla.

En ese JSON, lo que importa:

```json
"http_req_duration{status:200}": {
  "values": { "avg": 6.96, "med": 5.51, "p(90)": 13.94, "p(95)": 17.25, "max": 265.65 },
  "thresholds": { "p(95)<300": { "ok": true }, "p(99)<800": { "ok": true } }
}
```

- `thresholds` con todos los `ok` en `true` significa que la corrida cumplió el SLO. Es lo mismo que decide si el gate pasa.
- `register_failed.values.rate` es la tasa de resultado de negocio incorrecto.
- `http_reqs.values.count` y `.rate` dan peticiones totales y throughput medio. El throughput incluye los tramos de rampa, así que es una cifra conservadora.

**Advertencia sobre el p99.** El threshold `p(99)<800` se evalúa y se reporta como cumplido, pero `summaryTrendStats` del script incluye promedio, mínimo, mediana, máximo, p90 y p95 — **no p99**. k6 lo calcula internamente para decidir el umbral sin publicarlo. Se sabe que estuvo por debajo de 800 ms; no cuánto. Recuperar la cifra exige agregar `p(99)` a `summaryTrendStats` y volver a ejecutar.

**Nota sobre los nombres de archivo.** Los archivos `baseline.json` y `load.json` en `perf/results/` son copias manuales hechas para coincidir con los nombres que menciona la rúbrica. El script **no** las genera: el canónico de cada escenario es `summary-voters-<escenario>.json`.

## Resultados

Corridas del 19 de septiembre de 2026, servicio en máquina virtual y k6 en el anfitrión:

| Escenario | Peticiones | Throughput medio | p95 | Negocio incorrecto | Resultado |
| --- | --- | --- | --- | --- | --- |
| baseline | 58 357 | 195 req/s | 4,32 ms | 0 | Cumple |
| load | 1 338 920 | 1 594 req/s | 17,26 ms | 0 | Cumple |
| stress | 2 190 256 | 3 650 req/s | 42,50 ms | 0,0000457 % | Cumple |

El análisis, la matriz completa y los hallazgos están en la [wiki](https://github.com/DrearSanti/TYVS-Taller_Pruebas_de_carga_AMS/wiki).

## Equipo

| Integrante | Bloque |
| --- | --- |
| Santiago Escobar | Ejecución, matriz y análisis |
| Antonio Benítez | Observabilidad y defectos |
| Mateo Ramírez | Integración continua, estructura y plan |