# Guía paso a paso para ejecutar Northwind en las bases reales

Esta guía comienza en un equipo Windows sin las bases de la práctica. El recorrido principal trabaja con `NorthWind` y `Northwind_DW`; las copias `_Test` se reservan para pruebas automatizadas. Si ya tienes instalado alguno de los programas, no lo instales otra vez: comprueba su servicio y versión y sigue desde el primer paso que te falte.

| Nombre | Programa | Uso en esta práctica |
| --- | --- | --- |
| `NorthWind` | Motor de base de datos SQL Server | Origen de clientes, empleados, productos, transportistas y pedidos. Se restaura desde el archivo incluido en el proyecto. |
| `Northwind_DW` | Motor de base de datos SQL Server | Almacén de datos. Se crea vacío y el proyecto DW crea su esquema. |
| `SSISDB` | Catálogo de Integration Services en SQL Server | Guarda los paquetes publicados y sus parámetros de ejecución. |
| `NorthwindOLAP` | Analysis Services, modo Tabular | Modelo analítico que lee `Northwind_DW`; no es una base del motor relacional. |
| `NorthwindBIJob` | SQL Server Agent | Ejecuta la carga SSIS y después procesa `NorthwindOLAP`. |

## 01. Prepara los archivos e instala los programas

Esta guía es para Windows. Haz las instalaciones con una cuenta administradora.

1. Usa la carpeta completa que recibiste con el proyecto; confirma que estén `Northwind.sln` y `Files/NorthWind.bak`. Si la recibiste como ZIP, en el Explorador de archivos pulsa **Extraer todo** antes de abrirla. No descargues solo el archivo `.sln` ni crees una solución o proyectos nuevos.
2. Si SQL Server aún no está instalado, descárgalo desde [Descargas de SQL Server](https://www.microsoft.com/en-us/sql-server/sql-server-downloads). Para esta práctica local, selecciona **Developer**; no uses Express porque esta práctica necesita SQL Server Agent y Analysis Services. En el instalador, elige una instalación nueva y, en **Selección de características / Feature Selection**, marca **Database Engine Services** y **Integration Services**.
3. En **Configuración de instancia / Instance Configuration**, elige **Instancia predeterminada / Default instance** (`MSSQLSERVER`). En **Configuración del motor de base de datos / Database Engine Configuration**, elige **Autenticación de Windows / Windows authentication** y pulsa **Agregar usuario actual / Add Current User**. Así podrás conectar con `localhost` y publicar desde tu sesión.
4. En SQL Server Setup instala también **Analysis Services**. En **Configuración de Analysis Services**, selecciona el modo **Tabular** y agrega tu usuario de Windows como administrador. Usa la instancia predeterminada para conectar con `localhost`.
5. Instala [SQL Server Management Studio (SSMS)](https://learn.microsoft.com/en-us/ssms/download-sql-server-management-studio-ssms/). Se usa para restaurar y crear bases, y para administrar SSISDB, Analysis Services y SQL Server Agent.
6. Instala [Visual Studio 2026 Community](https://visualstudio.microsoft.com/vs/community/). Esta solución apunta a SQL Server 2025. En **Visual Studio Installer > Modificar**, marca **SQL Server Data Tools** dentro de **Almacenamiento y procesamiento de datos / Data storage and processing**.
7. En Visual Studio, abre **Extensiones > Administrar extensiones**. Busca e instala **Microsoft Analysis Services Projects** y **SQL Server Integration Services Projects**. Cierra y vuelve a abrir Visual Studio cuando lo solicite.
8. En la [página de descarga de Microsoft OLE DB Driver](https://learn.microsoft.com/en-us/sql/connect/oledb/download-oledb-driver-for-sql-server), abre **Previous releases** y descarga la versión **18.x x64**. Este proyecto usa el proveedor `MSOLEDBSQL.1` de la versión 18. La versión 19 se instala en paralelo, pero usa el nombre `MSOLEDBSQL19.1` y requeriría cambiar ambos administradores de conexión; no selecciones `SQLNCLI11`.

**Resultado:** en **Inicio > Servicios** aparecen **SQL Server (MSSQLSERVER)**, **SQL Server Agent (MSSQLSERVER)** y **SQL Server Analysis Services (MSSQLSERVER)**; Integration Services quedó instalado como componente de SQL Server. SSMS conecta al **Motor de base de datos** y a **Analysis Services** usando servidor `localhost` y autenticación Windows. Para confirmar los pasos actuales de instalación, consulta [instalar SQL Server](https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-installation-wizard-setup), [instalar Integration Services](https://learn.microsoft.com/en-us/sql/integration-services/install-windows/install-integration-services), [instalar Analysis Services](https://learn.microsoft.com/en-us/analysis-services/instances/install-windows/install-analysis-services) y [SSDT y sus extensiones](https://learn.microsoft.com/en-us/sql/ssdt/download-sql-server-data-tools-ssdt).

## 02. Restaura NorthWind y crea Northwind_DW

Si una de estas bases ya existe y contiene datos, no la restaures encima ni la reemplaces.

### 02.1 Restaura la base de origen NorthWind

1. En el Explorador de archivos, confirma que exista `Files/NorthWind.bak` dentro de la carpeta del proyecto.
2. En SSMS, conecta al **Motor de base de datos > localhost**. Haz clic derecho en el nombre del servidor > **Propiedades > Configuración de base de datos / Database Settings** y anota las rutas predeterminadas de **Datos** y **Copias de seguridad**.
3. Copia `Files/NorthWind.bak` a la ruta predeterminada de copias de seguridad. SQL Server lee el archivo desde su propio servicio; restaurar directamente desde el Escritorio puede producir «Operating system error 5 (Access is denied)».
4. En SSMS, clic derecho en **Bases de datos > Restaurar base de datos / Restore Database**. En **Origen / Source**, selecciona **Dispositivo / Device**, pulsa `...`, elige **Agregar / Add** y selecciona `NorthWind.bak` desde la carpeta de copias de seguridad.
5. En **Destino / Destination**, escribe exactamente `NorthWind`. Abre **Archivos / Files**, marca **Reubicar todos los archivos a una carpeta / Relocate all files to folder** y selecciona la ruta de datos anotada en el paso 2. Si SSMS pide una carpeta para el archivo de registro, selecciona la ruta de registro predeterminada que muestra **Database Settings**.
6. En **Opciones / Options**, deja desmarcada **Sobrescribir la base de datos existente (WITH REPLACE)**. Pulsa **Aceptar** y espera **Database restored successfully**.

Si `NorthWind` ya aparece en **Bases de datos**, omite la restauración y verifica que sea la base Northwind de la práctica. Si no estás seguro de su contenido, detente; no la sobrescribas.

### 02.2 Crea la base vacía Northwind_DW

1. En el Explorador de objetos, clic derecho en **Bases de datos > Nueva base de datos / New Database**.
2. En **Nombre de la base de datos / Database name**, escribe `Northwind_DW`.
3. Abre **Opciones / Options**, selecciona la intercalación `Modern_Spanish_CI_AS` y deja las rutas y tamaños de archivos con los valores predeterminados.
4. Pulsa **Aceptar**. No crees tablas manualmente ni restaures `NorthWind.bak` en `Northwind_DW`: la publicación del proyecto DW creará el esquema y sus datos iniciales.

Si `Northwind_DW` ya existe, no la crees de nuevo ni la vacíes. El paso 07 explica cómo continuar si está vacía o si conserva tablas de una versión anterior de la práctica.

### 02.3 Comprueba las bases

En SSMS, abre **Nueva consulta**, selecciona el motor `localhost` y ejecuta con **F5**:

```sql
SELECT name,state_desc
FROM sys.databases
WHERE name IN (N'NorthWind',N'Northwind_DW');

SELECT COUNT(*) AS Pedidos FROM NorthWind.dbo.Orders;
SELECT COUNT(*) AS Lineas FROM NorthWind.dbo.OrderDetails;
SELECT COUNT(*) AS TablasDW FROM Northwind_DW.sys.tables;
```

**Resultado de una instalación nueva:** ambas bases aparecen `ONLINE`; `NorthWind` tiene 830 pedidos y 2.155 líneas; `Northwind_DW` tiene 0 tablas. Si aparecen tablas del DW, conserva los datos y sigue la rama correspondiente del paso 07.

## 03. Inicia servicios y confirma las bases

1. Abre **Inicio**, busca **Servicios** y comprueba que estén iniciados **SQL Server (MSSQLSERVER)** y **SQL Server Analysis Services (MSSQLSERVER)**. Para crear o ejecutar el job, inicia también **SQL Server Agent (MSSQLSERVER)**.
2. Abre SSMS. En **Conectar > Motor de base de datos**, usa servidor `localhost` y autenticación **Windows**. Si aparece el aviso del certificado local, marca **Confiar en el certificado del servidor**.
3. En **Explorador de objetos > Bases de datos**, confirma que existan `NorthWind` y `Northwind_DW`.
4. Abre **Nueva consulta** y ejecuta esta comprobación de solo lectura con **F5**:

```sql
SELECT name, state_desc
FROM sys.databases
WHERE name IN (N'NorthWind',N'Northwind_DW');

SELECT COUNT(*) AS Pedidos FROM NorthWind.dbo.Orders;
SELECT COUNT(*) AS Lineas FROM NorthWind.dbo.OrderDetails;
SELECT COUNT(*) AS TablasDW FROM Northwind_DW.sys.tables;
```

**Resultado:** ambas bases aparecen `ONLINE`; `NorthWind` tiene 830 pedidos y 2.155 líneas. En una instalación nueva `Northwind_DW` tiene 0 tablas; si reutilizas un DW existente, aquí pueden aparecer tablas.

## 04. Abre y recompila la solución

1. Abre Visual Studio.
2. Selecciona **Archivo > Abrir > Proyecto o solución**.
3. Abre `Northwind.sln` dentro de la carpeta local donde guardaste el proyecto.
4. Abre **Ver > Explorador de soluciones**. Debes ver los proyectos `Northwind.OLTP`, `Northwind.DW`, `Northwind.ETL` y `Northwind.OLAP` cargados.
5. Selecciona **Compilar > Recompilar solución**.
6. Abre **Ver > Salida** y, en la lista **Mostrar salida de**, selecciona **Compilación / Build**.

**Resultado:** `Rebuild All: 4 succeeded, 0 failed, 0 skipped` y cero errores. Si un proyecto aparece descargado o incompatible, consulta [02. Configurar el entorno](02-entorno.md) antes de continuar.

## 05. Publica los extractores en NorthWind

1. En el Explorador de soluciones, haz clic derecho en `Northwind.OLTP` y elige **Publicar**.
2. En la ventana de publicación, pulsa **Cargar perfil / Load Profile**.
3. Selecciona `Northwind.OLTP/Properties/PublishProfiles/NorthWind.publish.xml`.
4. Verifica que el servidor sea `localhost` y la base de destino `NorthWind`.
5. Pulsa **Generar script / Generate Script**. Comprueba el destino indicado en la parte superior del script. El perfil bloquea cambios con posible pérdida de datos y no elimina objetos que no pertenezcan al proyecto.
6. Regresa a la ventana de publicación y pulsa **Publicar / Publish**. Espera el mensaje de publicación correcta.

Para comprobarlo en SSMS, conéctate al **Motor de base de datos > localhost**, abre **Nueva consulta** y ejecuta:

```sql
USE NorthWind;
SELECT name
FROM sys.procedures
WHERE name IN (N'GetDatabaseRowVersion',N'GetCustomerChangesByRowVersion',
 N'GetEmployeeChangesByRowVersion',N'GetProductChangesByRowVersion',
 N'GetShipperChangesByRowVersion',N'GetSalesChangesByRowVersion',
 N'RowVersionToBigInt',N'BigIntToRowVersion')
ORDER BY name;
SELECT COUNT(*) AS Pedidos FROM dbo.Orders;
SELECT COUNT(*) AS Lineas FROM dbo.OrderDetails;
```

**Resultado:** aparecen ocho procedimientos; siguen existiendo los mismos 830 pedidos y 2.155 líneas. Si falta uno, repite la publicación de `Northwind.OLTP` con el perfil `NorthWind.publish.xml`.

## 06. Ejecuta los extractores para ver los datos que leerá SSIS

Este paso consulta el origen; todavía no carga el DW.

1. En SSMS, conéctate al **Motor de base de datos > localhost**.
2. Abre **Nueva consulta** y selecciona `NorthWind` en la lista de bases.
3. Ejecuta con **F5**:

```sql
USE NorthWind;
DECLARE @corte table(DBTS bigint);
INSERT @corte EXEC dbo.GetDatabaseRowVersion;
DECLARE @fin bigint=(SELECT DBTS FROM @corte);
EXEC dbo.GetCustomerChangesByRowVersion 0,@fin;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@fin;
EXEC dbo.GetProductChangesByRowVersion 0,@fin;
EXEC dbo.GetShipperChangesByRowVersion 0,@fin;
EXEC dbo.GetSalesChangesByRowVersion 0,@fin;
```

**Resultado de referencia:** 91 clientes, 9 empleados, 77 productos, 3 transportistas y 2.155 líneas de venta. Si aparece “Could not find stored procedure”, vuelve al paso 05 y publica en `NorthWind`.

## 07. Prepara el esquema de Northwind_DW

### 07.1 Decide si debes migrar un DW anterior

En SSMS, ejecuta esta comprobación en `Northwind_DW`:

```sql
USE Northwind_DW;
SELECT (SELECT COUNT(*) FROM sys.tables) AS TotalTablas,
       OBJECT_ID(N'dbo.Dim_Cliente',N'U') AS DimCliente,
       OBJECT_ID(N'dbo.Fact_Ventas',N'U') AS Hechos;
```

Si `TotalTablas` es 0 y los otros dos resultados son `NULL`, `Northwind_DW` está vacío: **omite 07.2 y pasa a 07.3**. Si ambas tablas de proyecto aparecen, ejecuta 07.2 antes de publicar. Si el conteo es mayor que 0 pero falta una de esas tablas, detente y revisa el esquema; no ejecutes la migración sobre una estructura incompleta.

### 07.2 Ejecuta la migración controlada si reutilizas el DW anterior

1. En SSMS, conéctate al **Motor de base de datos > localhost**.
2. Selecciona **Archivo > Abrir > Archivo** y abre `Northwind.DW/Deployment/Prepare-LegacyWarehouse.sql`.
3. En la lista desplegable de bases, selecciona `Northwind_DW`. Comprueba el nombre antes de ejecutar.
4. Pulsa **F5** y espera el mensaje de finalización correcta.

La migración usa una transacción y valida que las filas existentes puedan conservarse. Si se detiene por duplicados, claves o importes incompatibles, no fuerces el script; conserva el mensaje de error y revísalo antes de publicar.

### 07.3 Publica el proyecto DW

1. Regresa a Visual Studio.
2. En el Explorador de soluciones, clic derecho en `Northwind.DW` > **Publicar**.
3. Pulsa **Cargar perfil** y abre `Northwind.DW/Properties/PublishProfiles/Northwind_DW.publish.xml`.
4. Confirma servidor `localhost` y destino `Northwind_DW`.
5. Pulsa **Generar script** y comprueba otra vez el destino.
6. Pulsa **Publicar** y espera el mensaje de éxito.

El perfil usa `BlockOnPossibleDataLoss=True` y `DropObjectsNotInSource=False`: detiene cambios con pérdida posible y no borra objetos ajenos al proyecto.

### 07.4 Verifica el esquema y los controles iniciales

En SSMS, abre una consulta en `Northwind_DW` y ejecuta:

```sql
USE Northwind_DW;
SELECT PackageName,CONVERT(bigint,LastRowVersion) AS Marca,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT COUNT(*) AS FilasHecho FROM dbo.Fact_Ventas;
SELECT Cliente_SK,CustomerID FROM dbo.Dim_Cliente WHERE Cliente_SK=0;
SELECT Empleado_SK,EmployeeID FROM dbo.Dim_Empleado WHERE Empleado_SK=0;
SELECT Tiempo_SK,Fecha FROM dbo.Dim_Tiempo WHERE Tiempo_SK=0;
```

**Resultado:** cinco controles —Cliente, Empleado, Producto, Transportista y Ventas—; cero hechos antes de la carga; y las filas técnicas desconocidas de Cliente, Empleado y Tiempo. No elimines estos registros: son parte del modelo.

## 08. Llena el calendario

1. En la misma ventana de consulta, confirma que la base seleccionada sea `Northwind_DW`.
2. Ejecuta con **F5**:

```sql
USE Northwind_DW;
DECLARE @Desde date,@Hasta date;
SELECT @Desde=MIN(Fecha),@Hasta=MAX(Fecha)
FROM NorthWind.dbo.Orders
CROSS APPLY (VALUES(CONVERT(date,OrderDate)),
                   (CONVERT(date,RequiredDate)),
                   (CONVERT(date,ShippedDate))) f(Fecha);
EXEC dbo.DW_LoadDimTiempo @FechaInicio=@Desde,@FechaFin=@Hasta;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
```

**Resultado de referencia:** 708 días, del 1996-07-04 al 1998-06-11. El procedimiento puede ejecutarse otra vez: amplía el calendario si aparecen fechas nuevas y no duplica las existentes.

## 09. Ejecuta la carga SSIS desde Visual Studio

### 09.1 Confirma las conexiones del proyecto

1. En Visual Studio, expande `Northwind.ETL` en el Explorador de soluciones.
2. Abre `Project.params` y comprueba:

| Parámetro | Valor |
| --- | --- |
| `SourceServer` | `localhost` |
| `SourceDatabase` | `NorthWind` |
| `WarehouseServer` | `localhost` |
| `WarehouseDatabase` | `Northwind_DW` |
| `LogDirectory` | `.` |

3. Expande **Connection Managers**. Deben aparecer `Origen.conmgr` y `DW.conmgr`. Sus proveedores son `MSOLEDBSQL.1` y usan autenticación integrada de Windows.
4. Si tus valores coinciden, no cambies conexiones ni parámetros. Si el proveedor indica `SQLNCLI11`, selecciona **Microsoft OLE DB Driver for SQL Server / MSOLEDBSQL.1**.

### 09.2 Abre el paquete principal y ejecútalo

1. Expande `Northwind.ETL > SSIS Packages` y abre `CargarNorthwind.dtsx`.
2. Selecciona la pestaña **Flujo de control / Control Flow**.
3. Los grupos llamados `Cargar Cliente`, `Cargar Empleado`, `Cargar Producto`, `Cargar Transportista` y `Cargar Ventas` son contenedores de secuencia. Cada uno agrupa las tareas de una entidad y las ejecuta en orden.
4. Para inspeccionar un grupo, pulsa el pequeño triángulo de su esquina. Dentro, haz doble clic en **Extraer a staging** para ver el flujo de datos desde el origen OLE DB al destino de staging. Vuelve a **Flujo de control** al terminar.
5. Haz clic derecho en el fondo del diseñador y elige **Ejecutar paquete / Execute Package**.
6. Espera a que el estado termine como **Package execution completed with success**. Detén la depuración con **Mayús+F5**.

El paquete principal ejecuta las cinco entidades. No ejecutes los paquetes individuales además del principal durante la misma carga.

## 10. Verifica la carga y vuelve a ejecutarla

### 10.1 Comprueba resultados del DW

En SSMS, conéctate al **Motor de base de datos > localhost** y ejecuta en `Northwind_DW`:

```sql
USE Northwind_DW;
SELECT COUNT(*) AS Lineas,
       COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint,Cantidad)) AS Unidades,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;
SELECT PackageName,CONVERT(bigint,LastRowVersion) AS Marca,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT OrderID,ProductID,Cantidad,ImporteNeto
FROM dbo.Fact_Ventas WHERE OrderID=10248 ORDER BY ProductID;
```

**Resultado:** 2.155 líneas, 830 pedidos, 51.317 unidades y neto 1.265.792,76; cinco controles con fecha de éxito. El pedido 10248 tiene tres líneas y 27 unidades, con neto total 440,00.

### 10.2 Comprueba que la repetición es segura

1. Vuelve a Visual Studio y ejecuta `CargarNorthwind.dtsx` otra vez.
2. Espera el mismo estado **Package execution completed with success**.
3. Repite la consulta de 10.1.

**Resultado:** los conteos y el neto no cambian si `NorthWind` no tuvo cambios. No trunques tablas ni pongas las marcas de `PackageConfig` en cero.

## 11. Publica SSIS en el catálogo del servidor

### 11.1 Crea SSISDB si todavía no existe

1. En SSMS, conéctate al **Motor de base de datos > localhost** como administrador.
2. En el Explorador de objetos, clic derecho en **Catálogos de Integration Services** > **Crear catálogo**.
3. Marca **Habilitar integración CLR**, escribe y confirma una contraseña para proteger los datos sensibles del catálogo y pulsa **Aceptar**.
4. Si `SSISDB` ya aparece en el Explorador de objetos, no la vuelvas a crear.

### 11.2 Prepara el entorno de producción

1. En SSMS, selecciona **Archivo > Abrir > Archivo** y abre `scripts/sql/Configure-NorthwindSSIS.sql`.
2. Comprueba en el bloque inicial que los valores sean carpeta `Northwind`, entorno `Northwind`, origen `NorthWind` y almacén `Northwind_DW`.
3. Ejecuta el archivo completo con **F5**. Debe crear o actualizar la carpeta y el entorno, sin publicar el proyecto todavía.
4. En el Explorador de archivos, crea `C:\ProgramData\NorthwindBI\Logs` si no existe.
5. En **Propiedades > Seguridad**, concede **Modificar** a las cuentas de servicio que aparecen en **Servicios** para SQL Server y SQL Server Agent. Si las cuentas ya tienen acceso, no agregues duplicados.

### 11.3 Despliega el proyecto desde Visual Studio

1. En Visual Studio, recompila `Northwind.sln`.
2. Clic derecho en `Northwind.ETL` > **Implementar / Deploy**.
3. Selecciona el destino **Integration Services en SQL Server**, servidor `localhost`, autenticación Windows y ruta `/SSISDB/Northwind/Northwind.ETL`.
4. Pulsa **Implementar** y espera el mensaje de éxito.
5. Regresa a SSMS y vuelve a ejecutar `scripts/sql/Configure-NorthwindSSIS.sql` con **F5**. Esta segunda ejecución enlaza los parámetros del proyecto al entorno.

### 11.4 Comprueba y ejecuta el paquete publicado

1. En SSMS, expande **Catálogos de Integration Services > SSISDB > Northwind > Proyectos > Northwind.ETL**.
2. Confirma que aparecen seis paquetes y que el proyecto tiene una referencia al entorno `Northwind`.
3. Clic derecho en `CargarNorthwind.dtsx` > **Ejecutar**.
4. Marca **Usar entorno** y elige `Northwind`.
5. Antes de iniciar, comprueba `SourceDatabase = NorthWind` y `WarehouseDatabase = Northwind_DW`; pulsa **Aceptar**.
6. Abre el informe de ejecución y comprueba estado **Correcto / Succeeded**. Verifica de nuevo los totales de 10.1.

## 12. Publica y procesa NorthwindOLAP

### 12.1 Da acceso de lectura al servicio SSAS

1. En SSMS, conectado al **Motor de base de datos > localhost**, abre `scripts/sql/Configure-NorthwindOLAPAccess.sql`.
2. Comprueba que la primera línea diga `USE [Northwind_DW]` y que el servicio indicado sea `NT SERVICE\MSSQLServerOLAPService`.
3. Ejecuta con **F5**. El resultado indica acceso `SELECT` a las seis tablas del modelo.

### 12.2 Implementa el modelo tabular

1. En Visual Studio, clic derecho en `Northwind.OLAP` > **Propiedades**.
2. En **Implementación / Deployment**, confirma servidor `localhost` y base `NorthwindOLAP`.
3. Abre `Northwind.OLAP.bim`; en **Orígenes de datos / Data Sources**, confirma servidor `localhost` y base `Northwind_DW`.
4. Clic derecho en `Northwind.OLAP` > **Implementar / Deploy**. Espera el mensaje de publicación correcta.

### 12.3 Procesa y consulta

1. En SSMS, abre **Conectar > Analysis Services**, servidor `localhost`, autenticación Windows.
2. Expande **Bases de datos**, actualiza la vista y confirma `NorthwindOLAP`.
3. Clic derecho en `NorthwindOLAP` > **Procesar base de datos / Process Database**.
4. Selecciona **Procesar completo / Process Full**, pulsa **Aceptar** y espera el resultado correcto.
5. Clic derecho en `NorthwindOLAP` > **Nueva consulta > DAX**. Ejecuta:

```DAX
EVALUATE
ROW("Pedidos",[Pedidos distintos],"Unidades",[Unidades],"Neto",[Ventas netas])
```

**Resultado:** 830 pedidos, 51.317 unidades y 1.265.792,76 netos.

Para comprobar un filtro por categoría y año, ejecuta:

```DAX
EVALUATE
ROW("Ventas netas",CALCULATE([Ventas netas],
    Dim_Tiempo[Anio]=1996,Dim_Producto[Categoria]="Beverages"))
```

**Resultado:** 47.919,00.

## 13. Crea y prueba NorthwindBIJob

### 13.1 Configura el permiso de procesamiento

1. En **Servicios**, confirma qué cuenta ejecuta **SQL Server Agent (MSSQLSERVER)**. Con la instalación predeterminada suele ser `NT SERVICE\SQLSERVERAGENT`.
2. En SSMS, conectado a **Analysis Services > localhost**, expande **Bases de datos > NorthwindOLAP > Roles**.
3. Si no existe `NorthwindBIJobProcessor`, clic derecho en **Roles** > **Nuevo rol**. Si ya existe, abre **Propiedades**.
4. En **General**, escribe `NorthwindBIJobProcessor` y selecciona permiso **Procesar base de datos / Process Database**.
5. En **Pertenencia / Membership**, agrega la cuenta que viste para SQL Server Agent. Pulsa **Aceptar**.

### 13.2 Crea el job deshabilitado

1. En SSMS, conéctate al **Motor de base de datos > localhost** como administrador.
2. Abre `scripts/sql/Create-NorthwindBIJob.sql` mediante **Archivo > Abrir > Archivo**.
3. En el bloque inicial confirma `@Environment = N'Northwind'` y `@ModelDatabase = N'NorthwindOLAP'`.
4. Si quieres cambiar la hora diaria propuesta, edita `@StartTime`, por ejemplo `'04:30:00'`. Deja `@EnableJob = 0` y `@EnableSchedule = 0`.
5. Pulsa **F5** y actualiza **SQL Server Agent > Trabajos / Jobs**.

**Resultado:** `NorthwindBIJob` tiene dos pasos —cargar SSIS y procesar el modelo— y un horario deshabilitado. Si actualizas un job de esta práctica, el script conserva el mismo nombre y no crea una copia duplicada.

### 13.3 Ejecuta y revisa el historial

1. Clic derecho en `NorthwindBIJob` > **Iniciar trabajo en el paso… / Start Job at Step…**.
2. Selecciona el paso 1 y pulsa **Iniciar**.
3. Clic derecho en el job > **Ver historial / View History**. Expande la ejecución.
4. Comprueba que los pasos SSIS y Analysis Services indiquen **Correcto / Succeeded**.
5. Repite la consulta de totales de 10.1 y la consulta DAX de 12.3.

**Resultado:** ambos pasos correctos y los totales del DW coinciden con los del modelo.

### 13.4 Activa el horario solo si lo necesitas

1. Clic derecho en `NorthwindBIJob` > **Propiedades > Programaciones / Schedules**.
2. Selecciona el horario > **Editar**, elige frecuencia y hora, marca **Habilitada / Enabled** y pulsa **Aceptar**.
3. En **General**, marca el job como **Habilitado / Enabled** y pulsa **Aceptar**.

Para detener ejecuciones futuras, desmarca **Habilitado** en **General**. La ejecución manual sigue disponible.

## 14. Volver a abrir o ejecutar el proyecto después

1. Abre `Northwind.sln` en Visual Studio.
2. Recompila si cambiaste archivos del proyecto.
3. Para una carga manual, abre `CargarNorthwind.dtsx` y ejecútalo siguiendo 09. Para cargar y procesar de una vez, inicia `NorthwindBIJob` siguiendo 13.3.
4. Comprueba los resultados con las consultas de 10.1 y 12.3.

No restaures `NorthWind` ni pongas en cero los controles del DW para “empezar de nuevo”. La carga incremental vuelve a leer cambios del origen y actualiza el DW. Si necesitas reconstruir datos reales después de una pérdida o vaciado, detén la práctica y prepara primero una estrategia de respaldo y reconstrucción.

## 15. Si algo falla

| Mensaje o síntoma | Qué revisar |
| --- | --- |
| No aparece `NorthWind` o falta la tabla `Orders` | Repite la restauración de `Files/NorthWind.bak` del paso 02.1; verifica que el destino se llame `NorthWind`. |
| `Operating system error 5 (Access is denied)` al restaurar | Copia `NorthWind.bak` a la ruta **Copias de seguridad / Backup** del servidor indicada en SSMS y vuelve a seleccionarlo desde allí. |
| `Northwind_DW` tiene 0 tablas | Si acabas de crearla, es el resultado esperado; publica `Northwind.DW` en el paso 07.3. |
| El script de migración dice que falta una tabla | Si la base está vacía, omite 07.2; si tiene tablas parciales, detente y revisa el DW antes de publicar. |
| Un proyecto aparece incompatible en Visual Studio | Confirma Visual Studio 2026 y las extensiones SSIS y Analysis Services; reinicia Visual Studio después de instalarlas. |
| El servicio SQL Server Agent no existe | Instala la edición Developer y el Database Engine; Express no incluye SQL Server Agent. |
| No aparece `MSOLEDBSQL.1` | Instala OLE DB Driver 18 x64. El driver 19 usa otro nombre de proveedor. |
| `SQLNCLI11` no está registrado | En los administradores de conexión selecciona `Microsoft OLE DB Driver for SQL Server` (`MSOLEDBSQL.1`). |
| Falla al abrir o probar una conexión | Confirma servidor `localhost`, autenticación Windows y nombres `NorthWind` / `Northwind_DW` en parámetros y administradores de conexión. |
| Un procedimiento no existe | Repite el paso 05 con el perfil `NorthWind.publish.xml`; confirma que la ventana de publicación apunte a `NorthWind`. |
| SSIS dice que necesita una copia marcada | Se está ejecutando un paquete antiguo. Recompila la solución, vuelve a desplegar `Northwind.ETL` y usa los valores reales del entorno `Northwind`. |
| No aparece el entorno en SSISDB | Ejecuta `Configure-NorthwindSSIS.sql` antes y después de implementar el proyecto. |
| El paquete termina con error rojo | En Visual Studio abre **Progreso / Progress** y lee el primer error. En SSMS abre el informe de ejecución y **Todos los mensajes**. Corrige la causa antes de repetir. |
| No se procesa NorthwindOLAP | Confirma que SSAS esté iniciado, que el modelo lea `Northwind_DW` y que la cuenta del servicio tenga `SELECT` en las seis tablas. |
| El job falla en su segundo paso | Confirma el rol `NorthwindBIJobProcessor`, su miembro de SQL Server Agent y que el modelo se llame `NorthwindOLAP`. |
| La carga informa que el DW está ocupado | Espera a que termine la otra ejecución. No lances dos paquetes de carga a la vez. |

Para realizar pruebas automatizadas aisladas, usa las instrucciones de [pruebas aisladas](referencias/pruebas-aisladas.md). No uses esa ruta para la ejecución principal de la práctica.
