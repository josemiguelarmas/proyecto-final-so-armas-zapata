# Opción 4 — Memoria RAM y swap

## Requisito

> Cantidad de memoria libre y cantidad del espacio de swap en uso (en bytes y
> porcentaje).

## Fuente de datos y por qué

Se lee directamente **`/proc/meminfo`** con `awk`.

`/proc/meminfo` es un archivo virtual: el kernel genera su contenido en el
momento de leerlo a partir de sus contadores internos. Es la fuente primaria;
`free`, `top` y `vmstat` lo leen por debajo.

| Alternativa | Por qué se descartó |
|---|---|
| `free -b` | Correcto en bytes, pero su formato de columnas cambió entre versiones de procps (columna `buff/cache`, `available`), y es un paquete más (`procps`/`procps-ng`) que en contenedores mínimos puede no estar. Leer `/proc/meminfo` da los mismos números sin intermediario. Se verificó que los valores del script coinciden con `free -b`. |
| `free -h` | Unidades redondeadas, no bytes. |
| `vmstat`, `top` | Pensados para monitoreo continuo; salida más difícil de parsear. |
| `swapon --show` | Solo swap; habría que combinarlo con otra fuente para la RAM. |

Campos usados: `MemTotal`, `MemFree`, `MemAvailable`, `Buffers`, `Cached`,
`SwapTotal`, `SwapFree`.

### Unidades: × 1024

`/proc/meminfo` etiqueta los valores como `kB`, pero en realidad son **KiB**
(1024 bytes). Por eso se multiplican por 1024. Se verificó: el resultado
coincide con `free -b`.

### "Libre" vs. "Disponible"

- **MemFree**: RAM que no se usa para nada. En Linux suele ser baja porque el
  kernel usa la RAM sobrante como caché de disco.
- **MemAvailable** (Linux ≥ 3.14): estimación del kernel de cuánta memoria
  pueden obtener nuevas aplicaciones **sin usar swap**, incluyendo cachés
  liberables. Es la cifra útil para el administrador.

El enunciado pide "memoria libre"; se muestran ambas con su explicación para
no inducir a error.

### Swap en uso

`SwapUsada = SwapTotal − SwapFree`, porcentaje sobre `SwapTotal`.

## Algoritmo (`option_memory`)

1. Si `/proc/meminfo` no es legible → `ERROR: no se puede leer /proc/meminfo.`
2. Un único `awk` extrae los campos, multiplica por 1024 y, si no existe
   `MemAvailable`, la estima como `MemFree + Buffers + Cached` y marca
   `estimated=1`. Imprime con `printf "%.0f"`: `awk` usa números de punto
   flotante y, según la implementación (p. ej. versiones antiguas de `mawk`),
   `print` puede mostrar enteros grandes en notación científica (`1.64859e+10`).
3. `read -r` recoge los seis valores en variables de bash.
4. `MemTotal` vacío o 0 → `ERROR: no se pudo interpretar /proc/meminfo.`
5. Imprime Total, Libre y Disponible con `print_memory_line` (bytes, tamaño
   legible con `human_size`, porcentaje con `percentage` a dos decimales). Si
   se estimó: `ADVERTENCIA: el kernel no expone MemAvailable; se estimó como MemFree + Buffers + Cached.`
6. Swap:
   - `SwapTotal == 0` → `No hay swap configurada; el uso es 0 bytes y el porcentaje no aplica.`
     (evita la división por cero).
   - Si no, Total y Usada con porcentaje.

Los porcentajes se calculan en `awk` porque la aritmética de bash
(`$(( ))`) es solo entera.

## Permisos

`/proc/meminfo` es legible por cualquier usuario; no requiere root.

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Sin swap (`swapoff -a`) | Mensaje "No hay swap configurada…", sin división por cero |
| `/proc/meminfo` sin `MemAvailable` (archivo falso montado con `bind`) | Estimación + advertencia |
| Valores de varios GiB/TiB | Sin notación científica (`%.0f`) |

## Diferencias entre distribuciones

Ninguna: `/proc/meminfo` lo provee el kernel, igual en todas. En un
contenedor Docker muestra la memoria del **host** (salvo que se use LXCFS),
porque los límites de cgroup no cambian `/proc/meminfo`.

## Ejemplo real

WSL Ubuntu 26.04, usuario normal. Entrada: `4`.

```text
=== Memoria RAM y swap ===

Memoria RAM (fuente: /proc/meminfo)
  Total (MemTotal):                16485855232 bytes     15.4GiB
  Libre (MemFree):                 13146951680 bytes     12.3GiB   79.75 %
  Disponible (MemAvailable):       15150551040 bytes     14.2GiB   91.90 %
  (Libre = memoria sin usar; Disponible = memoria utilizable sin recurrir a swap,
   incluye cachés que el kernel puede liberar.)

Swap
  Total (SwapTotal):                4294967296 bytes      4.0GiB
  Usada (Total - Free):                      0 bytes          0B    0.00 %
```

Comprobación: 13146951680 / 16485855232 × 100 = 79.75 %.

## Preguntas probables de la sustentación

**¿Por qué `/proc/meminfo` y no `free`?**
`free` lee `/proc/meminfo`; ir a la fuente evita depender del formato de
columnas de `procps`, que ha cambiado entre versiones. Los números coinciden
con `free -b`.

**¿Por qué multiplican por 1024?**
`/proc/meminfo` dice `kB` pero son KiB (1024 bytes); el enunciado pide bytes.

**¿Qué diferencia hay entre MemFree y MemAvailable?**
MemFree es RAM sin ningún uso. MemAvailable incluye cachés y buffers que el
kernel puede liberar; es la memoria realmente disponible para nuevos
procesos sin swap.

**¿Qué pasa si no hay swap?**
SwapTotal = 0; se informa "No hay swap configurada" en lugar de dividir por
cero.

**¿Y en un kernel viejo sin MemAvailable?**
Se estima como MemFree + Buffers + Cached y se avisa que es una estimación
(sobreestima un poco porque no toda la caché es liberable).

**¿Por qué `printf "%.0f"` en awk?**
`awk` trabaja en punto flotante; según la implementación (versiones antiguas
de `mawk`), `print` de un número como 16485855232 puede salir en notación
científica. `%.0f` garantiza un entero.
