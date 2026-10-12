# Marcas de cambios y extracción de clientes

## 1. Qué cambió

Una carga **incremental** lee cambios desde la última carga confirmada. `rowversion` es una marca binaria de ocho bytes que SQL Server genera al insertar o actualizar una fila; no representa una fecha ni se comparte entre bases. Aunque reviertas una modificación de prueba, el contador de la copia puede avanzar.

Usaremos un intervalo **(inicio, fin]**: la marca igual al inicio se excluye; la igual al fin se incluye. Lo posterior queda para el próximo intervalo. Ejemplo: con inicio 100 y fin 105, una fila con marca 100 no se lee, una con 105 sí y una con 106 queda pendiente.

`GetDatabaseRowVersion` devuelve el fin inclusivo en la columna `DBTS`. Usa `MIN_ACTIVE_ROWVERSION`, que identifica el límite exclusivo anterior a cambios todavía pendientes de confirmar; lo convierte a un límite inclusivo restando uno. Así, un cambio asignado dentro de una transacción pendiente no se pierde por avanzar la marca antes de su commit. También pueden posponerse cambios posteriores ya confirmados, que se retomarán en el siguiente intervalo. Este comportamiento se basa en [MIN_ACTIVE_ROWVERSION](https://learn.microsoft.com/en-us/sql/t-sql/functions/min-active-rowversion-transact-sql?view=sql-server-ver17).

Las conversiones `BigIntToRowVersion` y `RowVersionToBigInt` comprueban rango e ida y vuelta. El contrato admite valores entre cero y el máximo Int64 (9223372036854775807); rechaza NULL, negativos y binarios que no caben. No utiliza números de punto flotante: podrían perder precisión para marcas grandes. El control futuro conservará `BINARY(8)` y las variables numéricas usarán Int64.

`GetCustomerChangesByRowVersion` lee directamente Customers y entrega exactamente el contrato de `std.Cliente`:

| Columna | Tipo de salida |
| --- | --- |
| CustomerID | nchar(5) |
| CompanyName | nvarchar(40) |
| ContactName / ContactTitle | nvarchar(30) |
| City / Region / Country | nvarchar(15) |
| PostalCode | nvarchar(10) |
| SourceRowVersion | binary(8) |

Se retiraron los joins demográficos, incluidos el join que comparaba una columna consigo misma y la columna CustomerDesc. También se retiraron Address, Phone y Fax de este resultado porque no forman parte del contrato de staging de clientes. La tabla Customers conserva todas sus columnas: solo cambia la salida del extractor.

Las lecturas de los procedimientos se ejecutan con **READ COMMITTED**: no publican valores sin confirmar. En el entorno actual pueden esperar a que una escritura confirme o revierta. SQL Server restaura el aislamiento del llamador al salir de un procedimiento; se probó que una conexión inicialmente READ COMMITTED conserva ese nivel después de obtener el corte y extraer clientes. No se promete corregir permanentemente una sesión que el llamador haya configurado explícitamente como READ UNCOMMITTED. Véase [aislamiento en procedimientos](https://learn.microsoft.com/en-us/sql/t-sql/statements/set-transaction-isolation-level-transact-sql?view=sql-server-ver17).

## 2. Preparar los procedimientos en la copia

**Objetivo y motivo:** probar el extractor actualizado sin publicar todavía en NorthWind.

**Requisitos / programa:** PowerShell 7.6.5, SQL Server local en `localhost`, bases de prueba preparadas, autenticación Windows con permiso de alterar procedimientos en Northwind_Test. La preparación inicial está en [pruebas aisladas](03-pruebas-aisladas.md).

**Preparado:** los procedimientos ya se publicaron y verificaron en Northwind_Test. Los archivos están en el proyecto OLTP y la compilación pasó. **Pendiente:** publicación final en NorthWind y paquetes SSIS; la prueba real de conversiones a través de parámetros SSIS se hará en 5.1.

1. Abre PowerShell en la raíz donde clonaste el repositorio, por ejemplo `C:\Proyectos\proyecto-sql-server`. Sustituye esa ruta por tu carpeta real.
2. Ejecuta:

```powershell
& '.\tests\Deploy-TestExtractors.ps1'
```

3. Comprueba seis mensajes `Publicado en Northwind_Test: dbo...`: RowVersionToBigInt, BigIntToRowVersion, GetDatabaseRowVersion GetCustomerChangesByRowVersion, GetEmployeeChangesByRowVersion y GetProductChangesByRowVersion.

**Resultado esperado / comprobación:** se crean o actualizan únicamente esos procedimientos en la copia marcada Northwind_Test; no se publica un dacpac completo, no se modifica NorthWind ni se reinician datos o marcas. Repetir el script actualiza las definiciones sin recrear la base.

**Errores y recuperación:** si falta la copia o su marca, la publicación se rechaza. Sigue la preparación de pruebas; no cambies el destino a NorthWind para evitar el error. Si falta permiso, revisa la cuenta Windows del despliegue. El usuario NorthwindFixture sirve para los datos de prueba, no para publicar procedimientos.

## 3. Ver una extracción en SSMS

**Objetivo y motivo:** relacionar las marcas con los 91 clientes de la referencia.

**Requisitos / programa:** SSMS 22.10.2, conexión al motor localhost con autenticación Windows, procedimientos de esta etapa publicados en Northwind_Test.

**Preparado:** tabla Customers y contrato de extracción. **Pendiente:** cargar el resultado a staging y a la dimensión mediante ETL.

1. En SSMS, abre **New Query / Nueva consulta** en la conexión al motor.
2. Ejecuta el siguiente bloque de lectura (F5):

```sql
USE Northwind_Test;
DECLARE @Corte TABLE (DBTS bigint);
INSERT @Corte EXEC dbo.GetDatabaseRowVersion;
DECLARE @Fin bigint = (SELECT DBTS FROM @Corte);
SELECT DB_NAME() AS BaseActual, @Fin AS FinInclusivo;
EXEC dbo.GetCustomerChangesByRowVersion @startRow = 0, @endRow = @Fin;
EXEC dbo.GetCustomerChangesByRowVersion @startRow = @Fin, @endRow = @Fin;
```

3. Revisa BaseActual `Northwind_Test`. La primera extracción devuelve 91 filas en la referencia estable; la segunda devuelve cero porque el intervalo está vacío. No se exige un orden de filas.

**Resultado esperado / comprobación:** una fila por CustomerID y nueve columnas compatibles con staging. La marca numérica puede variar cuando ejecutes fixtures; no copies un valor de otra computadora o base. La carga inicial de referencia requiere que no haya modificaciones de prueba concurrentes.

**Errores y recuperación:** error 51104 indica intervalo nulo, negativo o invertido. Los errores 51101/51102/51103 indican conversiones o corte no representables; conserva el diagnóstico, no trunques la marca ni la conviertas a float. Un tiempo de espera mientras otra sesión escribe puede ser un bloqueo por lectura confirmada: termina correctamente la transacción escritora antes de reintentar.

## 4. Reproducir las pruebas

**Objetivo y motivo:** comprobar límites, precisión y cambios pendientes, además de observar consultas normales.

**Requisitos / programa:** PowerShell 7.6.5 y copias estables de referencia. No ejecutes otros fixtures a la vez. Los datos de prueba se escriben mediante conexiones restringidas de Northwind.TestTools.psm1.

**Preparado:** las pruebas ya pasaron. Los fixtures SQL se revierten; la prueba de varias sesiones confirma dos cambios dentro de la copia y restaura los nombres originales en su limpieza. Los rowversions de la copia avanzan, como es esperado.

1. Desde la raíz del repositorio, ejecuta:

```powershell
Import-Module '.\tests\Northwind.TestTools.psm1' -Force
$sql = Get-Content '.\tests\Test-CustomerExtraction.sql' -Raw
$resultado = Invoke-NorthwindTestSql -Database Northwind_Test -Sql $sql
foreach ($tabla in $resultado.Tables) { $tabla }
```

2. Comprueba los resultados Passed: referencia de 91 clientes; conversiones exactas y rechazos; límites y cambio posterior; cero/varias clasificaciones sin duplicados. El fixture comprueba la compatibilidad de tipos mediante inserción del resultado en una tabla temporal con la estructura de staging.
3. Ejecuta la prueba de conexiones separadas:

```powershell
& '.\tests\Test-RowVersion.ps1'
```

4. Revisa los mensajes PASS: sesión RC reutilizada, parámetros ADO.NET Binary(8)/Int64 exactos, corte anterior a la escritura pendiente, lectura sin datos sucios y ambos cambios recuperados después del commit. Con lectura RC basada en bloqueos se espera deliberadamente un timeout capturado; con versionado RC puede leerse la versión confirmada sin bloquear. Ambos casos deben excluir el valor pendiente.

**Resultado esperado / comprobación:** pruebas terminadas sin errores, 91 clientes y nombres originales restaurados. New-NorthwindTestConnection comparte las guardas del ejecutor de fixtures y permite mantener varias sesiones; sus llamadores deben cerrarlas con Dispose. Los parámetros ADO.NET se probaron realmente; todavía no son una prueba del futuro paquete SSIS.

**Errores y recuperación:** fixtures RT001/RT002/RT003 o clasificaciones RV_CLASS1/RV_CLASS2 preexistentes deben investigarse; no se sobrescriben. Si hay un error de conexión o SQL distinto del timeout deliberado, la prueba falla y no se declara PASS. La limpieza revierte la transacción pendiente y restaura los nombres de VINET/ALFKI. No reinicies las marcas del DW para recuperar una prueba de origen.

## 5. Evidencia y próxima etapa

La [validación](validacion.md) registra escenarios y resultados. Los logs crudos están localmente en `docs/evidencias/segmento-03` y se excluyen de Git. Se preservaron los datos, marcas y definiciones de los procedimientos de NorthWind durante la suite.

Siguiente segmento recomendado: empleados y productos (2.3 y 2.4), con relaciones opcionales y atributos dependientes. Todavía no se han corregido esos extractores ni construido los paquetes de carga.
