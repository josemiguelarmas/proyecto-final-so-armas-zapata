# Opción 1 (PowerShell) — Usuarios y último inicio de sesión

## Requisito

> Desplegar los usuarios creados en el sistema, y la fecha y hora de su último
> ingreso (login).

## Cmdlets y clases usados, y por qué

| Recurso | Uso | Alternativas descartadas |
|---|---|---|
| `Get-LocalUser` (`Microsoft.PowerShell.LocalAccounts`) | Fuente primaria de cuentas locales (`Name`, `SID`, `Enabled`, `LastLogon`) | **`net user`**: salida de texto pensada para humanos y dependiente del idioma del sistema; requeriría ejecutar `net user <nombre>` un proceso por cada usuario. |
| `Get-CimInstance Win32_UserAccount` + `Win32_NetworkLoginProfile` | Fuente de respaldo si el módulo `LocalAccounts` no está disponible | **`Get-WmiObject`**: obsoleto desde PowerShell 3.0 y eliminado en PowerShell 7+; `Get-CimInstance` es el estándar actual basado en WS-Man/DCOM. |
| `SID.Value` (`S-1-5-21-...-<RID>`) | Extracción del Relative Identifier (RID) para clasificar cuentas | **Filtrar por nombre (`Administrador`, `Guest`)**: los nombres cambian según el idioma de Windows (`Administrator` vs `Administrador`, `Guest` vs `Invitado`), mientras que los RIDs (`500`, `501`, `503`, `504`) son universales e invariantes. |

**Por qué auditar la fuente empleada:** el script imprime
`Fuente del último inicio de sesión: Get-LocalUser (SAM local)` (o la fuente
CIM de respaldo) para que el administrador sepa de dónde provienen los datos.

## Algoritmo

1. `Invoke-OptionUsers` muestra el submenú:
   - `1` Solo usuarios humanos (`Administrador` RID 500 y cuentas activas con `RID >= 1000`).
   - `2` Todas las cuentas locales (humanas, integradas y de sistema).
   Cualquier otra entrada muestra `ERROR: opción no válida: '…'.` y regresa al menú.
2. `Get-LocalUserRecords` consulta `Get-LocalUser`:
   - Para cada cuenta extrae el **RID** mediante `Get-AccountRid` (expresión regular `-(\d+)$` sobre el SID).
   - Evalúa `LastLogon`: si es `$null` o su año es `<= 1970` (en Windows un timestamp `FILETIME` en cero corresponde al `1601-01-01`), asigna `'NEVER'`; de lo contrario lo formatea como `yyyy-MM-dd HH:mm:ss`.
   - Si `Get-LocalUser` no existe en el entorno, recurre a `Win32_UserAccount -Filter "LocalAccount = True"` cruzado con `Win32_NetworkLoginProfile`.
3. Clasifica cada registro con `Test-IsHumanAccount`:
   - `Rid == 500 || (Rid >= 1000 && Enabled)` → arreglo `$humans`.
   - Resto (`Invitado` 501, `DefaultAccount` 503, `WDAGUtilityAccount` 504 o cuentas deshabilitadas) → arreglo `$system`.
4. `Write-UsersTable` imprime `USUARIOS HUMANOS (N)` y, si se eligió `2`,
   `CUENTAS DE SISTEMA / INTEGRADAS (N)` con columnas alineadas (`USUARIO`, `RID`, `FECHA`, `HORA`).

## Permisos

- Tanto `Get-LocalUser` como `Win32_UserAccount` pueden ejecutarse como
  **usuario estándar** sin requerir privilegios de Administrador para leer las
  cuentas locales y su atributo `LastLogon` en la base SAM.

## Casos borde (verificados)

| Caso | Comportamiento |
|---|---|
| Usuario que nunca ha iniciado sesión (`LastLogon = $null` o año 1601) | Muestra `Nunca ha iniciado sesión` |
| Windows en español (`Administrador`, `Invitado`) vs inglés (`Administrator`, `Guest`) | Clasificación exacta gracias al uso del RID (`500`, `501`) en lugar del nombre |
| Cuentas de utilidad de Windows Defender (`WDAGUtilityAccount`, RID 504) y `DefaultAccount` (RID 503) | Clasificadas como cuentas de sistema/integradas |
| Entrada inválida en el submenú | `ERROR: opción no válida: '…'.` por `stderr` sin cerrar el programa |

## Ejemplo real

Windows 11 (Windows PowerShell 5.1), usuario estándar (`gigi`). Entrada: `1`, `2`.

```text
=== Usuarios del sistema y último inicio de sesión ===

  1) Solo usuarios humanos (Administrador RID 500 y cuentas activas RID >= 1000)
  2) Todas las cuentas locales (humanas, integradas y de sistema)

Fuente del último inicio de sesión: Get-LocalUser (SAM local)

USUARIOS HUMANOS (4)
USUARIO                       RID  FECHA      HORA    
-------                       ---  -----      ----    
Administrador                 500  2021-03-16 08:59:07
CodexSandboxOffline          1039  Nunca ha iniciado sesión
CodexSandboxOnline           1040  Nunca ha iniciado sesión
gigi                         1032  2026-11-05 10:53:25

CUENTAS DE SISTEMA / INTEGRADAS (3)
USUARIO                       RID  FECHA      HORA    
-------                       ---  -----      ----    
DefaultAccount                503  Nunca ha iniciado sesión
Invitado                      501  Nunca ha iniciado sesión
WDAGUtilityAccount            504  Nunca ha iniciado sesión
```

## Limitaciones

- Consulta cuentas locales de la máquina (SAM). En un controlador de dominio
  Active Directory, las cuentas del dominio se consultan con `Get-ADUser` (o
  sin el filtro `LocalAccount = True` en CIM, lo cual sería lento en dominios
  grandes).
- Cuentas locales de servicio creadas por aplicaciones con `RID >= 1000` y
  habilitadas (como cuentas de sandbox) aparecen en la lista de usuarios con
  `RID >= 1000` al igual que ocurre en Linux con cuentas de `UID >= 1000`.

## Preguntas probables de la sustentación

**¿Qué es el RID y por qué se usa en lugar del UID de Linux?**  
En Windows cada cuenta tiene un SID (*Security Identifier*) de la forma
`S-1-5-21-<dominio>-<RID>`. El último número es el *Relative Identifier* (RID),
que cumple el mismo rol que el UID en Unix: `500` es siempre el Administrador
integrado (equivalente a `root` con UID 0) y las cuentas creadas para usuarios
empiezan en `1000`.

**¿Por qué clasificar por RID y no por nombre de usuario?**  
Porque los nombres de las cuentas integradas cambian según el idioma de
instalación de Windows (`Administrador`/`Administrator`, `Invitado`/`Guest`),
mientras que sus RIDs (`500`, `501`, `503`, `504`) son constantes en todas las
versiones e idiomas de Windows.

**¿Por qué se verifica `$u.LastLogon.Year -gt 1970`?**  
Porque Windows almacena las fechas internamente como estructuras `FILETIME`
(intervalos de 100 ns desde el 1 de enero de 1601). Cuando un usuario nunca ha
iniciado sesión, algunas APIs devuelven `$null` y otras devuelven la época cero
(`1601-01-01`).

**¿Por qué usar `Get-CimInstance` en el respaldo y no `Get-WmiObject`?**  
`Get-WmiObject` fue deprecado en PowerShell 3.0 y eliminado en PowerShell 7
porque usaba DCOM propietario. `Get-CimInstance` funciona tanto en Windows
PowerShell 5.1 como en PowerShell 7+.
