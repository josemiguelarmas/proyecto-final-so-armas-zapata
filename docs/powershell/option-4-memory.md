# Opción 4 (PowerShell) — Memoria RAM y swap

## Requisito

> Cantidad de memoria libre y cantidad del espacio de swap en uso (en bytes y
> porcentaje).

## Fuente de datos y por qué

Se consulta la clase CIM **`Win32_OperatingSystem`** mediante `Get-CimInstance`.

| Propiedad en `Win32_OperatingSystem` | Significado | Unidad original |
|---|---|---|
| `TotalVisibleMemorySize` | Memoria RAM física total disponible para el sistema operativo | KiB (bloques de 1024 bytes) |
| `FreePhysicalMemory` | Memoria física actualmente libre y reutilizable de inmediato | KiB |
| `SizeStoredInPagingFiles` | Tamaño total configurado en los archivos de paginación (`pagefile.sys`) | KiB |
| `FreeSpaceInPagingFiles` | Espacio libre actual dentro de los archivos de paginación | KiB |

Alternativas descartadas:

- **`Win32_PageFileUsage`**: reporta `AllocatedBaseSize` y `CurrentUsage` en
  **MiB** (menor precisión que los KiB de `Win32_OperatingSystem`) y puede no
  devolver instancias cuando el archivo de paginación es administrado de forma
  especial o temporal.
- **`Get-Counter '\Memory\Available Bytes'`**: el nombre de los contadores de
  rendimiento cambia según el idioma del sistema operativo (`\Memory\...` en
  inglés vs `\Memoria\...` en español), por lo que fallaría en máquinas con
  distinto idioma. `Win32_OperatingSystem` es independiente del idioma.
- **`Win32_ComputerSystem.TotalPhysicalMemory`**: incluye la memoria reservada
  por hardware/BIOS que el kernel no puede usar; el porcentaje de memoria libre
  del sistema operativo debe calcularse sobre `TotalVisibleMemorySize`.

### Conversión a bytes: `× 1024L` (`[int64]`)

Las cuatro propiedades de `Win32_OperatingSystem` vienen en **KiB** (1024
bytes). Se convierten explícitamente a enteros de 64 bits (`[int64]`) y se
multiplican por `1024L` para obtener el valor exacto en bytes sin riesgo de
desbordamiento de 32 bits (que ocurriría a partir de 2 GiB).

## Algoritmo (`Invoke-OptionMemory`)

1. Consulta `Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop`.
   Si falla, muestra `ERROR: no se pudo consultar Win32_OperatingSystem: …`.
2. Valida que `TotalVisibleMemorySize > 0`.
3. Calcula en `[int64]`:
   - `$memTotal = TotalVisibleMemorySize * 1024L`
   - `$memFree = FreePhysicalMemory * 1024L`
   - `$swapTotal = SizeStoredInPagingFiles * 1024L`
   - `$swapFree = FreeSpaceInPagingFiles * 1024L`
4. Imprime la sección de **Memoria RAM** con `Write-MemoryLine`:
   - Total en bytes y formato legible (`Format-HumanSize`).
   - Libre en bytes, formato legible y porcentaje (`Format-Percentage` a 2 decimales).
5. Imprime la sección de **Swap / Archivo de paginación**:
   - Si `$swapTotal <= 0`, imprime `0 bytes` y el mensaje
     `No hay swap/archivo de paginación configurado; el uso es 0 bytes y el porcentaje no aplica.`
     (evitando la división por cero).
   - De lo contrario, calcula `$swapUsed = [Math]::Max(0L, $swapTotal - $swapFree)`
     y muestra el total y el espacio en uso en bytes, formato legible y porcentaje.

## Permisos

`Win32_OperatingSystem` es accesible para cualquier usuario local sin necesidad
de privilegios de Administrador.

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Sistema con archivo de paginación deshabilitado (`SizeStoredInPagingFiles = 0`) | Informa que no hay swap configurado sin dividir por cero |
| Equipos con más de 4 GiB de RAM | Cálculo en `[int64]` (`1024L`) sin desbordamiento de entero |
| Configuración regional en español (coma decimal) | `Format-Percentage` y `Format-HumanSize` usan `InvariantCulture` (`.` decimal siempre) |

## Ejemplo real

Windows 11, usuario estándar. Entrada: `4`.

```text
=== Memoria RAM y swap ===

Memoria RAM (fuente: Win32_OperatingSystem)
  Total (VisibleMemory):            8355172352 bytes      7.8GiB
  Libre (FreePhysical):             1242222592 bytes      1.2GiB   14.87 %
  (FreePhysicalMemory representa la memoria RAM física inmediatamente disponible
   sin necesidad de escribir en el archivo de paginación.)

Swap / Archivo de paginación
  Total (PagingFiles):             20401094656 bytes     19.0GiB
  Usada (Total - Free):             1866293248 bytes      1.7GiB    9.15 %
```

Comprobación:
- RAM libre: `1,242,222,592 / 8,355,172,352 × 100 = 14.8677... % → 14.87 %`.
- Swap en uso: `1,866,293,248 / 20,401,094,656 × 100 = 9.1480... % → 9.15 %`.

## Preguntas probables de la sustentación

**¿Qué equivalente tiene la partición swap de Linux en Windows?**  
El archivo de paginación (`pagefile.sys`), administrado por el gestor de
memoria virtual de Windows. En `Win32_OperatingSystem`, su tamaño total es
`SizeStoredInPagingFiles` y su espacio libre es `FreeSpaceInPagingFiles`.

**¿Por qué no usar `Get-Counter` para consultar la memoria?**  
Porque los nombres de los contadores de rendimiento (`Performance Counters`)
dependen del idioma del sistema operativo (`\Memory\Available Bytes` en inglés
vs `\Memoria\Bytes disponibles` en español), mientras que las propiedades CIM
de `Win32_OperatingSystem` son idénticas en cualquier idioma.

**¿Por qué usar `[int64]` y `1024L` al multiplicar?**  
Porque un entero de 32 bits (`[int]`) solo llega hasta `2,147,483,647` (~2 GiB).
Al multiplicar los KiB de una máquina de 8 GiB o 16 GiB por 1024 se necesita
aritmética de 64 bits (`[int64]`).
