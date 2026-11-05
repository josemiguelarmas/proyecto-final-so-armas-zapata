# Opción 3 (PowerShell) — Los diez archivos más grandes

## Requisito

> Desplegar el nombre y el tamaño de los diez archivos más grandes almacenados
> en un disco o filesystem que el usuario deberá especificar. Los archivos
> deben aparecer con su trayectoria completa.

## Clases y métodos usados, y por qué

| Recurso | Uso | Por qué / alternativas descartadas |
|---|---|---|
| `[System.IO.DirectoryInfo]` + `Stack[string]` | Recorrido iterativo del árbol de directorios | Permite inspeccionar los atributos de cada directorio antes de entrar en él, omitir explícitamente cualquier `ReparsePoint` y capturar excepciones de permisos (`UnauthorizedAccessException`) directorio por directorio con máxima velocidad. |
| `FileAttributes::ReparsePoint` | Equivalente a `find -xdev` y `-type f` | Evita seguir enlaces simbólicos, *junctions* de NTFS o puntos de montaje de otros volúmenes dentro de una carpeta. |
| `Sort-Object` + `Select-Object -First 10` | Ordenamiento descendente por `Length` (y desempate por `FullName`) | Obtiene los 10 archivos más grandes con su ruta absoluta completa (`FullName`). |

Alternativas descartadas:

- **`Get-ChildItem -Recurse -File`**: en Windows PowerShell 5.1 atraviesa
  *junctions* y enlaces simbólicos hacia otros volúmenes, es mucho más lento
  por la sobrecarga del *pipeline* en discos con cientos de miles de archivos,
  y ante ciertos errores de permisos en contenedores de sistema puede abortar
  subárboles sin contabilizarlos con precisión.
- **`cmd /c dir /s`**: salida textual dependiente del idioma del sistema y
  difícil de parsear cuando hay rutas largas (`> 260` caracteres).

## Algoritmo

1. `Invoke-OptionLargestFiles` solicita la unidad o ruta con `Read-UserPath`
   (soporta `~`). Si está vacía → `ERROR: no se ingresó ninguna ruta.`
2. `Resolve-SearchPath` normaliza la entrada:
   - Si el usuario escribe solo la letra de unidad (`C` o `C:`), la convierte
     en la raíz `C:\` (en Windows `C:` sin barra invertida significa "el
     directorio actual de trabajo en la unidad C", no la raíz).
   - Si no existe: distingue entre unidad inexistente/no montada
     (`ERROR: la unidad 'Z:' no existe o no está montada.`) y ruta inexistente
     (`ERROR: '…' no existe.`).
   - Verifica que sea un directorio (`PSIsContainer`) y no un archivo regular,
     y comprueba que se pueda listar su contenido inicial.
3. Si la ruta buscada no es la raíz de la unidad (`C:\`), muestra una nota
   indicando a qué volumen pertenece y que no se cruzarán enlaces simbólicos ni
   puntos de montaje.
4. Advierte si no se ejecuta como Administrador y que el recorrido puede tardar.
5. Recorre el árbol con una pila (`Stack[string]`):
   - En cada directorio llama a `EnumerateFiles()` y agrega los archivos que no
     sean `ReparsePoint` a una lista tipada `List[object]`.
   - Luego llama a `EnumerateDirectories()` y apila solo los subdirectorios que
     no tengan el atributo `ReparsePoint`.
   - Cualquier excepción de acceso incrementa `$errorCount` y continúa con el
     siguiente directorio.
6. Ordena por `Length` descendente, toma los primeros 10 e imprime la tabla
   `#`, `BYTES`, `LEGIBLE`, `RUTA`.
7. Si `$errorCount > 0`, muestra al final:
   `ADVERTENCIA: no se pudo leer N ruta(s) (permisos u otros errores); los resultados pueden estar incompletos.`

## Permisos

Sin privilegios de Administrador, carpetas protegidas de Windows como
`C:\System Volume Information` o perfiles de otros usuarios en `C:\Users\...`
lanzan `UnauthorizedAccessException`. El script las captura, continúa la
búsqueda y reporta al final el número exacto de rutas no leídas.

## Casos borde (verificados)

| Caso | Resultado |
|---|---|
| Usuario ingresa `C` o `C:` sin barra final | Se normaliza a `C:\` (raíz del volumen) |
| Unidad inexistente (`Z:`) | `ERROR: la unidad 'Z:' no existe o no está montada.` |
| Ruta apunta a un archivo regular | `ERROR: '…' no es un directorio ni una unidad de disco.` |
| *Junctions* de Windows (`Application Data`, `Archivos de programa`) | Omitidas gracias al filtro `ReparsePoint` (evita ciclos infinitos y duplicados) |
| Directorio vacío (0 archivos) | Muestra `No se encontraron archivos regulares en …` |

## Ejemplo real

Windows 11, usuario estándar. Entrada: `3`, ruta del repositorio.

```text
=== Los diez archivos más grandes ===


Buscando en: C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata
Nota: no es la raíz de la unidad; pertenece al sistema de archivos montado en C:\.
Se busca solo dentro de esta ruta, sin cruzar enlaces simbólicos ni puntos de montaje.
ADVERTENCIA: sin privilegios de Administrador algunos directorios pueden no ser accesibles.
Esto puede tardar en sistemas de archivos grandes...

  #             BYTES     LEGIBLE  RUTA
  1             76021     74.2KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\.git\objects\pack\pack-b66cc49cfe535ddad7e9f272c1239ac314978039.pack
  2             36068     35.2KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\bash\sysadmin-tool.sh
  3             24724     24.1KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\powershell\sysadmin-tool.ps1
  4             19834     19.4KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\tests\test_option5_backup.bats
  5             16642     16.3KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs\option-5-backup.md
  6             16335     16.0KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\README.md
  7             13251     12.9KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\tests\test_option1_users.bats
  8             11956     11.7KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs\architecture.md
  9             10870     10.6KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\tests\test_option3_largest.bats
 10              9485      9.3KiB  C:\Users\gigi\Desktop\7_Semestre\Sistemas_Operativos\Proyecto_Final\proyecto-final-so-armas-zapata\docs\option-3-largest-files.md
```

## Preguntas probables de la sustentación

**¿Por qué normalizar `C:` a `C:\`?**  
En DOS/Windows cada unidad mantiene su propio directorio de trabajo actual:
`C:` significa "el directorio actual en la unidad C", mientras que `C:\`
significa la raíz del volumen C. Si el usuario escribe `C:` esperando buscar en
todo el disco, sin la barra solo buscaría desde la carpeta actual.

**¿Cómo se evita salir del sistema de archivos o caer en bucles infinitos en Windows?**  
Filtrando el atributo `[System.IO.FileAttributes]::ReparsePoint`. En NTFS, los
puntos de montaje de otros discos en carpetas, los enlaces simbólicos y las
*junctions* de compatibilidad (como `C:\Users\<user>\AppData\Local\Application Data`,
que apunta a sí misma) son `ReparsePoint`.

**¿Por qué usar `EnumerateFiles()` en vez de `GetFiles()`?**  
`GetFiles()` carga todo el arreglo en memoria antes de devolver el primer
elemento; `EnumerateFiles()` transmite cada entrada a medida que la lee del
directorio NTFS, reduciendo el consumo de memoria.
