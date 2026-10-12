# Bases de prueba aisladas

## 1. Qué se preparó y para qué

Una **copia de prueba** es una base independiente donde podemos provocar cambios y errores para comprobar la práctica. Un **fixture** es un dato o modificación que preparamos para una prueba: por ejemplo, cambiar el nombre de un cliente para comprobar la carga incremental.

Ya están creadas en el motor `localhost`:

| Original, usado como referencia de lectura | Copia donde se probarán cambios |
| --- | --- |
| NorthWind | **Northwind_Test** |
| Northwind_DW | **Northwind_DW_Test** |

Se hizo una copia de seguridad **COPY_ONLY** y se restauró cada copia con archivos físicos propios mediante **MOVE**. Esto conserva datos, objetos, claves, marcas e identidades de origen; no cambia el nombre ni los archivos de las bases originales. Los backups están en la carpeta de backup de SQL Server, con nombres únicos registrados en la evidencia. El método sigue la [documentación de copia por backup y restore](https://learn.microsoft.com/en-us/sql/relational-databases/databases/copy-databases-with-backup-and-restore?view=sql-server-ver17).

La comparación inicial verificó todas las tablas, incluidos valores de filas y `rowversion`, así como semillas, incrementos y últimos valores de columnas `IDENTITY`. El origen de prueba conserva **91 clientes, 9 empleados, 77 productos, 3 transportistas, 830 pedidos, 2.155 líneas y 51.317 unidades**. El DW de prueba conserva el estado capturado: tablas comerciales y staging vacíos, cinco controles con marca cero y fecha NULL.

No es todavía una carga ETL. Los procedimientos copiados mantienen sus problemas conocidos hasta que los corrijamos y probemos en los siguientes segmentos. No hay que publicar ni abrir nuevos proyectos en Visual Studio para esta preparación.

## 2. Revisarlas en SSMS

**Objetivo y motivo:** reconocer las copias y comprobar que las consultas se ejecutan en la base correcta.

**Requisitos / programa:** SSMS 22.10.2, motor `localhost` activo, autenticación Windows. La creación y comprobación ya están hechas; puedes seguir estos pasos para aprender. Falta implementar extractores y cargas.

1. En SSMS conecta a **Database Engine / Motor de base de datos**, servidor `localhost`, autenticación Windows, como en la guía inicial.
2. En **Object Explorer / Explorador de objetos**, haz clic derecho en **Databases / Bases de datos** y selecciona **Refresh / Actualizar**. Deben aparecer `Northwind_Test` y `Northwind_DW_Test` junto a tus bases originales.
3. Abre **New Query / Nueva consulta** y ejecuta este bloque de lectura con F5:

```sql
USE Northwind_Test;
SELECT DB_NAME() AS BaseActual;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Pedidos FROM dbo.Orders;
SELECT COUNT(*) AS Lineas, SUM(CONVERT(bigint, Quantity)) AS Unidades
FROM dbo.OrderDetails;

USE Northwind_DW_Test;
SELECT DB_NAME() AS BaseActual;
SELECT COUNT(*) AS LineasCargadas FROM dbo.Fact_Ventas;
SELECT PackageName, LastRowVersion, LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

**Resultado esperado / comprobación:** BaseActual cambia de Northwind_Test a Northwind_DW_Test; conteos de origen 91/830/2155/51317; cero hechos y cinco controles iniciales. Las consultas de comprobación ya se ejecutaron automáticamente.

**Errores y recuperación:** si no aparecen las copias, confirma servidor `localhost` y refresca el nodo. Si cambian conteos después de probar fixtures persistentes, no borres datos para recuperar estos números; registra el cambio y usa los criterios de esa prueba. Las consultas SSMS ejecutadas como administrador no quedan restringidas por el módulo de fixtures: para modificaciones de prueba usa la herramienta del apartado 4.

## 3. Repetir la preparación sin sobrescribir

**Objetivo y motivo:** disponer de una preparación reproducible que preserve trabajo de pruebas existente.

**Requisitos / programa:** PowerShell **7.6.5** con System.Data.SqlClient, autenticación Windows con permisos de backup, restore y creación de base; los scripts fueron ejecutados en la sesión PowerShell del entorno. SQL Server debe poder escribir en sus carpetas predeterminadas de backup/datos/log. No necesitas descargar componentes ni introducir contraseñas.

**Preparado:** ambas copias tienen la propiedad `NorthwindPracticeTestDatabase` que identifica su origen, el usuario restringido `NorthwindFixture` y TRUSTWORTHY/DB_CHAINING desactivados. No se ofrece una opción de reset ni restauración sobre una base existente.

1. Abre PowerShell y sitúate en la carpeta del proyecto:

```powershell
Set-Location -LiteralPath 'C:\Proyectos\proyecto-sql-server'
```

2. Ejecuta:

```powershell
& '.\tests\Prepare-TestDatabases.ps1'
```

3. Comprueba los mensajes `Reused: NorthWind -> Northwind_Test` y `Reused: Northwind_DW -> Northwind_DW_Test`. En la primera ejecución en un entorno sin copias, los mensajes son `Created`.
4. Consulta el nuevo `preparacion-<fecha>.json` en `docs\evidencias\segmento-02` para ver acción, origen, destino y ruta de backup cuando se creó.

**Resultado esperado / comprobación:** una segunda ejecución reutiliza las bases marcadas sin recrear tablas, restaurar backups encima ni reiniciar marcas. Ya se comprobó esa repetición.

**Errores y recuperación:** una base existente sin la marca correcta, sin usuario de fixtures o con aislamiento desactivado causa un error y se deja intacta. Si la primera preparación se interrumpe después de restaurar y antes de marcar, se detectará como incompleta al repetir. Conserva el mensaje y el estado para diagnóstico; no marques manualmente una base cuyo origen no hayas comprobado. Una denegación de backup o restore requiere revisar la cuenta de ejecución y las rutas del servicio. No uses la opción REPLACE ni elimines una base para resolverla automáticamente.

## 4. Ejecutar fixtures con la conexión restringida

**Objetivo y motivo:** escribir datos de prueba en las copias y evitar acceso accidental a tus bases originales, incluso con una sesión inicial administradora.

**Requisitos / programa:** misma PowerShell, bases marcadas y usuario sin login `NorthwindFixture`. El módulo usa autenticación integrada, comprueba nombre/marca/opciones y cambia la identidad SQL a ese usuario. Es una identidad interna de la base; no necesita contraseña ni permite acceder a otras bases. `NO REVERT` impide recuperar el contexto administrador durante ese batch; la conexión se desecha al terminar. El mecanismo corresponde a [EXECUTE AS USER](https://learn.microsoft.com/en-us/sql/t-sql/statements/execute-as-transact-sql?view=sql-server-ver17).

**Preparado:** solo se admiten `Northwind_Test` y `Northwind_DW_Test`. Por defecto se abre una transacción y se revierte al terminar. Con `-Commit` puedes guardar explícitamente un fixture para pruebas incrementales futuras. Los permisos de fixtures son lectura, inserción, actualización, borrado y ejecución dentro de la copia; no son permisos para publicar esquemas.

1. En la carpeta del proyecto, importa el módulo:

```powershell
Import-Module '.\tests\Northwind.TestTools.psm1' -Force
```

2. Para una lectura de prueba:

```powershell
$resultado = Invoke-NorthwindTestSql -Database Northwind_Test -Sql 'SELECT DB_NAME() AS BaseActual, COUNT(*) AS Pedidos FROM dbo.Orders;'
$resultado.Tables[0]
```

3. Comprueba BaseActual `Northwind_Test` y Pedidos `830` en esta referencia. La herramienta devuelve un DataSet: cada resultado SELECT está en `Tables[0]`, `Tables[1]`, etc. El SQL es un batch; no pongas separadores `GO` ni instrucciones propias de confirmación/reversión de transacciones en un fixture.
4. Ejecuta la comprobación automatizada:

```powershell
& '.\tests\Test-Isolation.ps1'
```

**Resultado esperado / comprobación:** mensajes PASS para destinos originales rechazados, modificación en la copia y rollback confirmado desde otra conexión, inserción con commit visible y posteriormente eliminada, rechazo de acceso a NorthWind/Northwind_DW desde SQL y de REVERT, y lectura de los cinco controles del DW de prueba. Ya se ejecutó esta prueba completa. Los rechazos se comprueban por su causa esperada; un error de conexión no se acepta como prueba de aislamiento.

**Errores y recuperación:** `Cannot validate argument ... Database` significa que se eligió un destino no permitido. La base sin marca produce un diagnóstico de copia no reconocida. Si un fixture falla, la conexión se cierra y revierte su transacción. Para analizar datos después de un `-Commit`, abre otra llamada o una consulta SSMS de lectura. La preparación reutiliza esa copia con sus cambios; no los deshace.

Los fixtures de este segmento no dejaron cambios comerciales persistentes. **Los rowversions de la copia sí avanzaron** al hacer UPDATE/INSERT aunque se reviertan o se eliminen las filas: ese comportamiento es esperado. `Verify-TestCopies.sql` se usa inmediatamente después de crear copias, antes de fixtures; su comparación exacta de rowversion puede fallar legítimamente después. Las futuras pruebas incrementales establecerán su corte a partir de la copia actual, no de las marcas del original.

## 5. Archivos y evidencia

| Archivo | Responsabilidad |
| --- | --- |
| `tests/Prepare-TestDatabases.ps1` | Crear copias nuevas o reutilizar las ya marcadas |
| `tests/Northwind.TestTools.psm1` | Ejecutar batches de fixtures con guardas y contexto restringido |
| `tests/Verify-TestCopies.sql` | Comparar conteos, valores e identidades iniciales mediante lectura |
| `tests/Test-Isolation.ps1` | Verificar guardas, rollback, commit y rechazo de acceso externo |
| `docs/evidencias/segmento-02/` | Preparación, comparación y resultados ejecutados |

La separación origen/DW corresponde a las responsabilidades de BikeStores, con destinos de prueba propios. Los proyectos y paquetes que construiremos utilizarán estas bases para sus escenarios de escritura. La ejecución bajo SSIS/Agent tendrá sus propias comprobaciones; esta conexión restringida corresponde al ejecutor de fixtures PowerShell.

El contrato de `rowversion` y la extracción de clientes (2.1 y 2.2) ya se completaron: consulta [extracción de clientes](extraccion-clientes.md). Siguiente segmento recomendado: empleados y productos (2.3 y 2.4), con relaciones opcionales y cambios dependientes.
