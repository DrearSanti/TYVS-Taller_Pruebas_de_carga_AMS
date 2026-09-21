# Registro de Defectos

Curso: Testing y Validación de Software
Proyecto: Pruebas de Carga y Rendimiento
Equipo: AMS — Santiago Escobar, Antonio Benítez, Mateo Ramírez
Fecha: 16 de septiembre de 2026

---

## Introducción

Este documento recopila los defectos identificados durante la ejecución de pruebas
de rendimiento sobre el servicio de registraduría. Incluye tanto defectos del
sistema bajo prueba como defectos del diseño de las pruebas, porque un fallo de
prueba no siempre corresponde a un fallo del sistema.

---

## Formato 1: Lista detallada

## PERF-01 — Conexiones a la base de datos sin pool

**Severidad:** Media
**Estado:** En progreso. La corrección está integrada en `master` y elimina la degradación progresiva; su efecto sobre el throughput no es concluyente con el ambiente disponible (ver PERF-04).

### Descripción

`RegistryRepository` abría una conexión nueva mediante `DriverManager.getConnection` en cada operación. Como `registerVoter` ejecuta dos operaciones por petición, cada petición creaba y destruía dos conexiones.

### Evidencia inicial

El defecto se identificó al comparar los dos scripts sobre el mismo ambiente con 20 usuarios virtuales: `register_person_k6.js` alcanzó 21 613 req/s y `register_voter_k6.js` 196 req/s.

Esa comparación no es evidencia válida del costo de las conexiones. Ambos scripts ejercitan el mismo endpoint y el mismo código, y la latencia por petición fue prácticamente igual (1,64 y 2 ms). La diferencia de throughput la produce la pausa de 100 ms que `register_voter_k6.js` aplica por iteración: con 20 usuarios virtuales, 20 / (0,100 + 0,002 s) da 196 req/s, que es exactamente lo medido. `register_person_k6.js` no pausa por defecto.

La evidencia del defecto es la de la sección siguiente: la degradación progresiva de la latencia del servidor bajo carga constante, registrada con Actuator.

### Corrección aplicada

Se incorporó HikariCP 5.1.0. `RegistryConfig` construye un `HikariDataSource` (pool `registry-pool`, 20 conexiones) y lo inyecta en `RegistryRepository`, que ahora obtiene sus conexiones de ahí. Commit `2423923`.

### Medición antes y después

Ambiente: Ubuntu Server 24.04.4, 2 vCPU, 4 GB de RAM, OpenJDK 17.0.20, red VMnet1 en solo anfitrión (192.168.231.129). k6 en el anfitrión Windows. Escenario `load` (rampa a 200 VUs, 14 min), una corrida por configuración, servicio reiniciado antes de cada una. Métricas del servidor muestreadas cada minuto con `perf/scripts/capturar_actuator.ps1`.

| Métrica | Antes (sin pool) | Después (HikariCP) |
| --- | --- | --- |
| Peticiones | 742 489 | 513 233 |
| Throughput medio | 884 req/s | 611 req/s |
| p95 según k6 | 294,6 ms | 384,5 ms |
| Threshold p95 ≤ 300 ms | Cumple | No cumple |
| Peticiones fallidas (timeout de 2 s) | 175 (0,0236 %) | 44 (0,0086 %) |
| Latencia media según el servidor | 37,4 ms | 44,1 ms |
| Latencia media del servidor en el tramo sostenido | crece de 8 a 115 ms | estable entre 40 y 55 ms |
| CPU del proceso en el pico | 93–99 % | 99–100 % |
| Pausa máxima de GC | 64 ms | 67 ms |

Artefactos: `perf/results/load-antes.json`, `perf/results/load-despues.json`, `perf/results/actuator-antes/`, `perf/results/actuator-despues/`.

### Análisis

Vista desde el cliente, la corrección empeoró el sistema: un 31 % menos de throughput y el p95 por encima del SLO.

Vista desde el servidor, la latencia media casi no cambió (37,4 frente a 44,1 ms). Esa cifra incluye el tiempo que un hilo espera por una conexión del pool, de modo que el pool no es el cuello de botella; una consulta durante el pico mostró 7 de 20 conexiones activas y ningún hilo en espera.

La diferencia entre las dos vistas es el tiempo que cada petición pasa fuera de la aplicación: unos 54 ms en la corrida sin pool y unos 135 ms en la corrida con pool. Ese tiempo no lo gasta el código corregido, y la explicación más probable es el ambiente descrito en PERF-04.

Lo que sí se observa del lado del servidor es un cambio de forma. Sin pool, la latencia crece de manera continua con la carga constante y el throughput cae de 1 270 a 670 req/s a lo largo del tramo sostenido. Con pool, ambas se mantienen planas. Las curvas se cruzan hacia el minuto 11, por lo que en una corrida más larga es previsible que la configuración con pool atienda más tráfico en total. La configuración con pool además falló cuatro veces menos peticiones.

La degradación progresiva sin pool no se explica por el crecimiento de la tabla, porque la corrida con pool también inserta cientos de miles de filas sin degradarse. Apunta a un costo que se acumula al abrir y cerrar conexiones; identificarlo con precisión exige métricas que no se recolectaron.

### Pendiente

Repetir ambas corridas con el inyector en una máquina física distinta, y ejecutar al menos una corrida de resistencia para confirmar el cruce de las curvas. Cada configuración se midió una sola vez, así que no hay estimación de la variación entre corridas.

---

## Defecto PERF-02 — Estado sucio entre corridas consecutivas

- Capa afectada: Diseño de las pruebas, no el sistema bajo prueba
- Escenario: Cualquiera, al encadenar corridas sin reiniciar el servicio

### Descripción

Al ejecutar varios escenarios seguidos sin reiniciar el proceso de Java, la tasa
de resultado de negocio incorrecto se dispara sin que el servicio tenga ningún
problema.

La base H2 es en memoria y la URL incluye `DB_CLOSE_DELAY=-1`, de modo que los
datos sobreviven mientras viva el proceso. Los identificadores que genera el
script de k6 ya quedaron registrados en la corrida anterior, así que las
peticiones que esperaban `VALID` reciben `DUPLICATED`. El servicio responde
correctamente: el registro duplicado es la respuesta correcta a esa entrada. Lo
que está mal es la expectativa de la prueba.

### Evidencia

Tasas de resultado incorrecto observadas al encadenar tres escenarios sin
reiniciar el servicio: 1,97 % en la segunda corrida y 19,58 % en la tercera,
suficiente para cruzar el umbral del 1 % y marcar el threshold en rojo.

Medición tomada por Santiago Escobar.

### Impacto

Tres corridas perdidas y un diagnóstico falso. El síntoma apunta al sistema bajo
prueba cuando la causa está en el procedimiento de ejecución. Es el tipo de
defecto que lleva a buscar el problema donde no está.

### Causa

Falta de aislamiento entre corridas. El estado de la base de datos no se
restablece entre escenarios.

### Mitigación

Reiniciar el servicio entre corridas, siempre. Una alternativa sería que el
script generase identificadores únicos por ejecución, o invocar `deleteAll()`
antes de cada escenario, pero reiniciar es lo más simple y no altera el código
bajo prueba.

### Estado

Resuelto

### Prioridad

Media

---

## Defecto PERF-03 — Timeout durante el arranque en frío

- Capa afectada: JVM
- Escenario: Stress Test (rampa a 600 VUs)

### Descripción

Una petición con timeout a los dos segundos de iniciar la corrida, con la carga
todavía en su nivel más bajo. El instante en que ocurre descarta la saturación
como causa y apunta al arranque en frío de la máquina virtual de Java: carga de
clases y compilación JIT antes de alcanzar el estado estacionario.

### Evidencia

Una petición de 2 190 256, equivalente a 0,0000457 % de resultado incorrecto, muy
por debajo de cualquier umbral. El detalle está en la página Resultados de la wiki.

Medición tomada por Santiago Escobar.

### Impacto

Despreciable en términos de SLO. Se documenta porque ilustra que el momento en
que ocurre un fallo es parte del diagnóstico, no solo su magnitud.

### Causa

Arranque en frío de la JVM. Las primeras peticiones se atienden con código
interpretado antes de que el compilador JIT optimice los caminos calientes.

### Mitigación

Incluir un periodo de calentamiento antes de empezar a medir, o descartar los
primeros segundos de cada corrida del cálculo de percentiles.

### Estado

Abierto

### Prioridad

Baja

---

## PERF-04 — Inyector y servidor comparten la CPU física

**Severidad:** Media (afecta la validez de las mediciones, no el comportamiento del servicio)
**Estado:** Abierto

### Descripción

La máquina virtual tiene dos vCPU asignadas, pero corren sobre el mismo procesador físico que el anfitrión donde se ejecuta k6. Cuando el anfitrión está cargado, el hipervisor le resta tiempo de CPU a la VM y k6 compite por los mismos núcleos. La separación del inyector es lógica, no física.

### Evidencia

- Durante la rampa del escenario `load`, el anfitrión reportó alrededor de 80 % de uso de CPU.
- Con latencias del servidor similares entre corridas (37,4 y 44,1 ms), el tiempo fuera de la aplicación pasó de ~54 a ~135 ms.
- En la corrida con pool, 37 timeouts ocurrieron entre los segundos 620 y 621, mientras la latencia máxima registrada por el servidor en ese minuto fue de unos 1,4 s, por debajo del timeout de 2 s de k6. Esas peticiones se demoraron antes de llegar al controlador: en la cola de Tomcat o con la VM sin tiempo de CPU.

### Mitigación propuesta

Ejecutar k6 desde una máquina física distinta a la que aloja la VM. Mientras tanto, las comparaciones entre corridas deben apoyarse en las métricas del servidor y no en las de k6.

---

## Formato 2: Tabla de seguimiento

| ID | Escenario | Resultado esperado | Resultado obtenido | Estado | Prioridad |
| --- | --- | --- | --- | --- | --- |
| PERF-01 | Load | Latencia del servidor estable bajo carga constante | Sin pool crece de 8 a 115 ms en el tramo sostenido; con pool se mantiene entre 40 y 55 ms | En progreso | Media |
| PERF-02 | Todos | Resultado incorrecto < 1 % | 1,97 % y 19,58 % al encadenar corridas | Resuelto | Media |
| PERF-03 | Stress | Sin timeouts | Una petición con timeout a los 2 s de arrancar | Abierto | Baja |
| PERF-04 | Load | Latencia del cliente atribuible al servicio | ~54 y ~135 ms por petición fuera de la aplicación; 37 timeouts en un segundo con el servidor bajo 1,4 s | Abierto | Media |

---

## Convenciones de Estado

Abierto: Defecto identificado sin corrección aplicada.
En progreso: En proceso de corrección.
Resuelto: Corregido y validado con nuevas pruebas.

---

Universidad de La Sabana — Facultad de Ingeniería
Curso: Testing y Validación de Software