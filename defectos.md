# Registro de Defectos

Curso: Testing y Validación de Software
Proyecto: Pruebas de Carga y Rendimiento
Equipo: [Nombre del equipo]
Fecha: [Fecha]

---

## Introducción

Este documento recopila los defectos identificados durante la ejecución de pruebas
de rendimiento sobre el servicio de registraduría. Incluye tanto defectos del
sistema bajo prueba como defectos del diseño de las pruebas, porque un fallo de
prueba no siempre corresponde a un fallo del sistema.

---

## Formato 1: Lista detallada

## Defecto PERF-01 — Conexiones a base de datos sin pool

- Capa afectada: Infraestructura de persistencia
- Escenario: Load Test (rampa a 200 VUs)
- Clase: `RegistryRepository`

### Descripción

`getConnection()` abría una conexión nueva con `DriverManager` en cada operación:

```java
private Connection getConnection() throws SQLException {
    return DriverManager.getConnection(jdbcUrl, username, password);
}
```

`registerVoter` ejecuta dos operaciones por petición, `existsById` y `save`, de modo
que cada petición atendida creaba y destruía dos conexiones. Bajo carga sostenida
eso son miles de conexiones por segundo, con su costo de establecimiento asociado.

### Evidencia

Comparación de dos scripts sobre el mismo hardware y los mismos 20 usuarios
virtuales, ejercitando caminos de código distintos:

| Script | Peticiones | Throughput | p95 |
| --- | --- | --- | --- |
| register_person_k6.js | 6 484 046 | 21 613 req/s | 1,64 ms |
| register_voter_k6.js | 58 920 | 196 req/s | 2 ms |

Ciento diez veces de diferencia en throughput entre dos caminos del mismo servicio.
Medición tomada por [autor], archivo `perf/results/summary-baseline.json`.

### Impacto

Límite artificial en el throughput del endpoint de registro de votantes, sin
relación con la lógica de negocio ni con la capacidad del motor de base de datos.

### Causa

Ausencia de pool de conexiones. Cada operación paga el costo completo de
establecer una conexión nueva.

### Corrección aplicada

Se introdujo HikariCP como origen de datos. `RegistryRepository` ahora recibe un
`DataSource` inyectado y `getConnection()` solicita una conexión al pool. Los
métodos de consulta y escritura no cambiaron: ya usaban `try-with-resources`, y
cerrar una conexión de Hikari la devuelve al pool en lugar de destruirla.

Rama: `feature/observabilidad`

### Resultado de la corrección

| Métrica | Antes | Después | Variación |
| --- | --- | --- | --- |
| p95 | [PENDIENTE] | [PENDIENTE] | |
| Throughput medio | [PENDIENTE] | [PENDIENTE] | |
| jvm.threads.live en el pico | [PENDIENTE] | [PENDIENTE] | |

Ambas mediciones se tomaron en el mismo ambiente, con el servicio en máquina
virtual y k6 en el anfitrión, y lo único que varió entre ellas fue la
introducción del pool.

### Estado

[PENDIENTE: Resuelto, una vez validada la corrección con la medición del después]

### Prioridad

Alta

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

Medición tomada por [autor].

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

Medición tomada por [autor].

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

## Formato 2: Tabla de seguimiento

| ID | Escenario | Resultado esperado | Resultado obtenido | Estado | Prioridad |
| --- | --- | --- | --- | --- | --- |
| PERF-01 | Load | Throughput acorde a la capacidad del motor | 196 req/s contra 21 613 req/s en el camino sin el defecto | [PENDIENTE] | Alta |
| PERF-02 | Todos | Resultado incorrecto < 1 % | 1,97 % y 19,58 % al encadenar corridas | Resuelto | Media |
| PERF-03 | Stress | Sin timeouts | Una petición con timeout a los 2 s de arrancar | Abierto | Baja |

---

## Convenciones de Estado

Abierto: Defecto identificado sin corrección aplicada.
En progreso: En proceso de corrección.
Resuelto: Corregido y validado con nuevas pruebas.

---

Universidad de La Sabana — Facultad de Ingeniería
Curso: Testing y Validación de Software