# Guía paso a paso para ejecutar Northwind

Esta guía explica el recorrido completo usando Visual Studio y SQL Server Management Studio (SSMS): desde abrir la solución hasta ejecutar el job y verificar las ventas. También explica cómo volver a empezar sin borrar datos y cómo restablecer las copias de práctica si realmente necesitas una carga limpia.

## Antes de comenzar

La solución se encuentra en la carpeta `practica sql server` y el archivo que debes abrir es `Northwind.sln`. Los cuatro proyectos son:

| Proyecto | Función |
| --- | --- |
| `Northwind.OLTP` | Procedimientos que extraen los cambios desde Northwind. |
| `Northwind.DW` | Tablas de staging, dimensiones, ventas y controles de carga. |
| `Northwind.ETL` | Paquetes SSIS que mueven los datos al almacén. |
| `Northwind.OLAP` | Modelo tabular que permite consultar las ventas con DAX. |

La ejecución usa estas bases:

| Base | Uso |
| --- | --- |
| `NorthWind` | Base operativa original; se conserva intacta. |
| `Northwind_DW` | Almacén original; se conserva intacto. |
| `Northwind_Test` | Copia de práctica del origen. |
| `Northwind_DW_Test` | Copia de práctica del almacén. |

Todas las publicaciones y cargas de esta guía deben apuntar a las bases que terminan en `_Test`. No selecciones `NorthWind` ni `Northwind_DW` como destino.

Necesitas SQL Server Database Engine, SQL Server Agent, Analysis Services instalado en modo **Tabular**, SSMS, Visual Studio con SSDT, las extensiones **SQL Server Integration Services Projects** y **Microsoft Analysis Services Projects**, y **Microsoft OLE DB Driver for SQL Server**. Para SSIS usa el proveedor `MSOLEDBSQL.1`; `SQLNCLI11` no está instalado en este equipo.

## Elige cómo empezar

### A. Volver a abrir el proyecto después de cerrar Visual Studio o reiniciar Windows

No restaures ni borres ninguna base. Continúa con los pasos 1 y 2 y luego usa la **opción 2 del paso 11** para ejecutar el ciclo completo desde SSMS. La carga incremental detecta qué cambió y se puede repetir.

### B. Preparar el proyecto por primera vez en otra computadora

Sigue los pasos del 1 al 10 para configurar y publicar por primera vez; después realiza el paso 11 para ejecutar y comprobar el proyecto. El equipo debe tener las dos bases originales `NorthWind` y `Northwind_DW`, además de los programas y servicios mencionados arriba.

### C. Volver al estado inicial de las copias de práctica

Esto reemplaza el contenido de `Northwind_Test` y `Northwind_DW_Test`. No lo hagas para una ejecución normal. Confirma que las bases originales estén disponibles y que el job no se esté ejecutando. Haz el restablecimiento de copias del paso 12; luego repite los pasos 3 al 10 y termina con el paso 11. No borres ni restaures sobre las bases originales.

## 1. Iniciar los servicios y abrir la solución

### 1.1 Comprobar servicios de Windows

1. Abre **Inicio**, escribe **Servicios** y abre la aplicación.
2. Busca **SQL Server (MSSQLSERVER)**. Debe tener estado **En ejecución / Running**. Si está detenido, clic derecho > **Iniciar / Start**.
3. Busca **SQL Server Agent (MSSQLSERVER)**. Debe estar en ejecución para usar el job. Si está detenido, clic derecho > **Iniciar**.
4. Busca **SQL Server Analysis Services (MSSQLSERVER)**. Debe estar en ejecución para publicar, procesar y consultar el modelo. Si está detenido, clic derecho > **Iniciar**.

Si alguno de esos servicios no aparece, revisa la instalación de SQL Server antes de continuar. Analysis Services debe estar instalado como **Tabular**, no como Multidimensional.

### 1.2 Abrir y compilar

1. Abre Visual Studio.
2. Selecciona **Archivo > Abrir > Proyecto o solución**.
3. Navega a la carpeta del repositorio y abre `Northwind.sln`.
4. Abre **Ver > Explorador de soluciones**. Expande la solución y comprueba que aparezcan `Northwind.OLTP`, `Northwind.DW`, `Northwind.ETL` y `Northwind.OLAP`. Ninguno debe indicar **Incompatible** ni **Descargado**.
5. Selecciona **Compilar > Recompilar solución / Build > Rebuild Solution**.
6. Selecciona **Ver > Salida / View > Output** y, en la lista **Mostrar salida de**, elige **Compilación / Build**.

**Resultado esperado:** `Rebuild All: 4 succeeded, 0 failed, 0 skipped`, sin errores. Visual Studio crea el paquete de publicación SSIS en `Northwind.ETL/bin/Development/Northwind.ispac`.

Si los proyectos ETL/OLAP no cargan, instala sus extensiones en **Extensiones > Administrar extensiones** y reinicia Visual Studio cuando lo pida. Si aparece un error sobre `SQLNCLI11`, conserva el controlador **Microsoft OLE DB Driver for SQL Server** y revisa que las conexiones usen `MSOLEDBSQL.1`.

## 2. Conectarse a SQL Server y Analysis Services

### 2.1 Conexión al motor SQL

1. Abre SSMS.
2. En **Conectar al servidor**, elige **Tipo de servidor: Motor de base de datos**.
3. Escribe `localhost` como nombre del servidor.
4. Elige **Autenticación de Windows** y pulsa **Conectar**.
5. En **Explorador de objetos > Bases de datos**, comprueba que existan `NorthWind` y `Northwind_DW`.

Si SSMS muestra advertencia del certificado local, marca **Confiar en el certificado del servidor / Trust server certificate** y vuelve a conectar.

### 2.2 Conexión a Analysis Services

1. En el **Explorador de objetos**, pulsa **Conectar > Analysis Services**.
2. Escribe `localhost`, deja **Autenticación de Windows** y conecta.
3. Confirma que el servidor se identifica como instancia Tabular y que puedes expandir sus bases de datos.

Las conexiones de Motor de base de datos y Analysis Services son conexiones distintas; usa el tipo correcto al abrir cada una.

## 3. Crear o reutilizar las copias de práctica

Si ya ves `Northwind_Test` y `Northwind_DW_Test` en el Explorador de objetos y son las copias marcadas de esta práctica, no las restaures otra vez. Continúa con 3.3 para confirmar la identificación.

### 3.1 Crear copia `Northwind_Test`

1. En SSMS, conectado al **Motor de base de datos**, expande **Bases de datos**.
2. Clic derecho en `NorthWind` > **Tareas > Copia de seguridad**.
3. Deja el tipo **Completa**. En **Destino**, agrega un archivo `.bak` en una carpeta donde la cuenta del servicio SQL Server pueda escribir y pulsa **Aceptar**.
4. Cuando termine la copia, clic derecho en **Bases de datos** > **Restaurar base de datos**.
5. En **Origen**, selecciona **Dispositivo**, pulsa el botón de exploración `...`, agrega el `.bak` recién creado y acepta.
6. En **Destino**, escribe `Northwind_Test` como **Base de datos**.
7. Abre la página **Archivos**. Cambia la ruta física de cada archivo restaurado para que tenga un nombre nuevo, por ejemplo `Northwind_Test.mdf` y `Northwind_Test_log.ldf`. No permitas que la ruta coincida con los archivos de `NorthWind`.
8. Revisa que el nombre de destino diga exactamente `Northwind_Test` y pulsa **Aceptar**.

### 3.2 Crear copia `Northwind_DW_Test`

Repite el procedimiento anterior usando `Northwind_DW` como base de origen, el nombre `Northwind_DW_Test` como destino y archivos físicos propios, por ejemplo `Northwind_DW_Test.mdf` y `Northwind_DW_Test_log.ldf`.

### 3.3 Identificar y aislar las copias

1. En SSMS selecciona **Archivo > Abrir > Archivo** y abre `scripts/sql/Identify-NorthwindCopies.sql` dentro del repositorio.
2. Comprueba que la conexión activa sea el motor `localhost`.
3. Pulsa **Ejecutar / Execute (F5)**.
4. Lee los mensajes y resultados de las dos bases.

**Resultado esperado:** el script informa que las copias están identificadas. Este paso comprueba el nombre y los objetos esperados, agrega la marca de práctica cuando falta, mantiene `TRUSTWORTHY` y `DB_CHAINING` apagados y configura el usuario restringido que necesitan las pruebas. Si el script dice que la base no es la copia esperada, detente; no cambies el nombre de destino a la base original para evitar la guarda.

## 4. Publicar los extractores de Northwind

Los extractores son procedimientos almacenados del proyecto `Northwind.OLTP`. Se publican en la copia operativa, no en `NorthWind`.

1. En Visual Studio, localiza el proyecto `Northwind.OLTP` en el Explorador de soluciones.
2. Clic derecho en `Northwind.OLTP` > **Publicar / Publish**.
3. En la ventana de publicación, pulsa **Cargar perfil / Load Profile** y abre `Northwind.OLTP/Properties/PublishProfiles/Northwind_Test.publish.xml`.
4. Confirma el servidor `localhost` y la base destino `Northwind_Test`.
5. Pulsa **Generar script / Generate Script**. Revisa la cabecera del script: servidor `localhost`, destino `Northwind_Test`.
6. Vuelve a la ventana de publicación y pulsa **Publicar / Publish**. Espera el mensaje de publicación correcta.

### 4.1 Comprobar los procedimientos

En SSMS, abre **Nueva consulta / New Query**, confirma la conexión `localhost` y ejecuta:

```sql
USE Northwind_Test;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Lineas FROM dbo.OrderDetails;
SELECT name FROM sys.procedures WHERE name LIKE N'%RowVersion%' ORDER BY name;
```

**Resultado de referencia:** 91 clientes, 2.155 líneas y ocho procedimientos auxiliares/de extracción.

### 4.2 (Opcional) Ver las filas que leen los extractores

Esta demostración consulta las filas de origen; por sí sola no llena el DW.

```sql
USE Northwind_Test;
DECLARE @cut TABLE(DBTS bigint);
INSERT @cut EXEC dbo.GetDatabaseRowVersion;
DECLARE @fin bigint=(SELECT DBTS FROM @cut);
EXEC dbo.GetCustomerChangesByRowVersion 0,@fin;
EXEC dbo.GetEmployeeChangesByRowVersion 0,@fin;
EXEC dbo.GetProductChangesByRowVersion 0,@fin;
EXEC dbo.GetShipperChangesByRowVersion 0,@fin;
EXEC dbo.GetSalesChangesByRowVersion 0,@fin;
```

Pulsa **F5**. Los resultados de referencia son 91 clientes, 9 empleados, 77 productos, 3 transportistas y 2.155 líneas de venta.

## 5. Preparar y publicar el almacén de datos

### 5.1 Ejecutar la preparación del almacén

1. En SSMS abre `Northwind.DW/Deployment/Prepare-LegacyWarehouse.sql`.
2. En la barra de consulta, selecciona `Northwind_DW_Test` en la lista desplegable de bases de datos. Confirma el nombre antes de ejecutar.
3. Pulsa **F5**.

El script prepara/migra el almacén de práctica y contiene una guarda: si la conexión no apunta a la copia `Northwind_DW_Test` identificada, falla sin hacer la migración.

### 5.2 Publicar el proyecto DW

1. En Visual Studio, clic derecho en `Northwind.DW` > **Publicar / Publish**.
2. Pulsa **Cargar perfil / Load Profile**.
3. Abre `Northwind.DW/Properties/PublishProfiles/Northwind_DW_Test.publish.xml`.
4. Comprueba servidor `localhost` y base destino `Northwind_DW_Test`.
5. Pulsa **Generar script** y revisa que el destino siga siendo la copia de práctica.
6. Pulsa **Publicar** y espera el resultado correcto.

La publicación mantiene datos y marcas existentes; no es una orden para vaciar el almacén.

### 5.3 Crear el calendario

En SSMS abre una nueva consulta conectada al motor `localhost` y ejecuta con **F5**:

```sql
USE Northwind_DW_Test;
DECLARE @Desde date, @Hasta date;
SELECT @Desde=MIN(Fecha), @Hasta=MAX(Fecha)
FROM Northwind_Test.dbo.Orders
CROSS APPLY (VALUES(CONVERT(date,OrderDate)),
                   (CONVERT(date,RequiredDate)),
                   (CONVERT(date,ShippedDate))) d(Fecha);
EXEC dbo.DW_LoadDimTiempo @FechaInicio=@Desde,@FechaFin=@Hasta;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

**Resultado de referencia para las copias originales:** 708 días, del 4 de julio de 1996 al 11 de junio de 1998, y cinco controles en `PackageConfig`. Si la copia es nueva, las marcas empiezan en cero y las fechas de carga en `NULL`. Si ya cargaste ventas, no borres las marcas ni ejecutes restauraciones para forzar ese resultado inicial.

## 6. Ejecutar la carga SSIS en Visual Studio

Este paso lee `Northwind_Test`, extrae los cambios y carga dimensiones y ventas en `Northwind_DW_Test`.

### 6.1 Revisar conexiones y parámetros

1. En Visual Studio abre `Northwind.sln` y expande `Northwind.ETL`.
2. Abre `Project.params`.
3. Confirma estos valores:

| Parámetro | Valor de práctica |
| --- | --- |
| `SourceServer` | `localhost` |
| `SourceDatabase` | `Northwind_Test` |
| `WarehouseServer` | `localhost` |
| `WarehouseDatabase` | `Northwind_DW_Test` |
| `LogDirectory` | `.` |

4. En el Explorador de soluciones expande **Northwind.ETL > Connection Managers**. Verás `Origen.conmgr` y `DW.conmgr`. No crees otras conexiones.
5. Abre ambas conexiones si cambiaste los nombres o el servidor. El proveedor debe ser **Microsoft OLE DB Driver for SQL Server / `MSOLEDBSQL.1`** y la autenticación **Windows**. Pulsa **Probar conexión / Test Connection** y guarda.
6. Clic derecho en `Northwind.ETL` > **Propiedades**. Comprueba `TargetServerVersion = SQL Server 2025`.

### 6.2 Ejecutar el paquete principal

1. Expande **Northwind.ETL > SSIS Packages**.
2. Haz doble clic en `CargarNorthwind.dtsx`.
3. En el diseñador, selecciona **Flujo de control / Control Flow**. Los rectángulos `Cargar Cliente`, `Cargar Empleado`, `Cargar Producto`, `Cargar Transportista` y `Cargar Ventas` son grupos de tareas que ejecutan en ese orden.
4. Para inspeccionar un grupo, pulsa la flecha de su esquina superior para expandirlo. Haz doble clic en `Extraer a staging`; en **Flujo de datos / Data Flow** verás **OLE DB Source** conectado a **OLE DB Destination**. Vuelve a la pestaña **Control Flow**.
5. En el diseñador, clic derecho en `CargarNorthwind.dtsx` > **Ejecutar paquete / Execute Package**.
6. Espera el mensaje `Package execution completed with success` y las marcas verdes. Detén la depuración con **Mayús+F5**.

Si hay una cruz roja, abre **Progreso / Progress**, busca el primer mensaje **Error** y corrige esa causa antes de repetir. No vacíes tablas ni pongas las marcas a cero para reintentar.

### 6.3 Comprobar la carga en SSMS

En SSMS, conectado al motor, ejecuta:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS Lineas,
       COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint,Cantidad)) AS Unidades,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;

SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;

SELECT OrderID,ProductID,Cantidad,ImporteNeto
FROM dbo.Fact_Ventas WHERE OrderID=10248 ORDER BY ProductID;
```

Pulsa **F5**.

**Resultado de referencia:** 2.155 líneas, 830 pedidos, 51.317 unidades y neto `1.265.792,76`; cinco controles con fecha de carga correcta. El pedido 10248 contiene 3 líneas, 27 unidades y neto total `440,00`.

### 6.4 Repetir la carga

Vuelve a ejecutar el paquete `CargarNorthwind.dtsx` en Visual Studio y vuelve a ejecutar la consulta anterior en SSMS. Si el origen no cambió, deben permanecer los mismos conteos, claves e importes. La carga incremental no duplica las ventas.

## 7. Crear el catálogo SSISDB y su entorno

Si `SSISDB` ya aparece bajo **Catálogos de Integration Services**, no la crees de nuevo; pasa a 7.2.

### 7.1 Crear SSISDB una sola vez

1. En SSMS, conectado al **Motor de base de datos > localhost** con una cuenta administradora, expande el servidor.
2. Clic derecho en **Catálogos de Integration Services** > **Crear catálogo / Create Catalog**.
3. Marca **Habilitar integración CLR / Enable CLR Integration**.
4. Escribe una contraseña nueva para la clave maestra y confírmala.
5. Pulsa **Aceptar** y espera que aparezca `SSISDB`.
6. Guarda esa contraseña en un gestor seguro. No la escribas en un archivo SQL ni la subas al repositorio.

### 7.2 Crear el entorno y sus cinco valores

1. En SSMS selecciona **Archivo > Abrir > Archivo** y abre `scripts/sql/Configure-NorthwindSSIS.sql`.
2. La primera vez, revisa que los valores del encabezado sean:

| Campo | Valor |
| --- | --- |
| Folder | `Northwind` |
| Environment | `Northwind_Test` |
| Project | `Northwind.ETL` |
| SourceServer | `localhost` |
| SourceDatabase | `Northwind_Test` |
| WarehouseServer | `localhost` |
| WarehouseDatabase | `Northwind_DW_Test` |
| LogDirectory | `C:\ProgramData\NorthwindBI\Logs` |

3. Confirma que la consulta está conectada al motor correcto y pulsa **F5**.
4. Si el proyecto SSIS aún no se publicó, el script crea la carpeta, entorno y valores y avisa que falta publicar el proyecto. Es normal en esta primera pasada.

### 7.3 Dar permisos a la carpeta de registros

1. Abre el Explorador de archivos y navega a `C:\ProgramData`.
2. Crea `NorthwindBI` y dentro crea `Logs` si todavía no existen.
3. Clic derecho en `Logs` > **Propiedades > Seguridad > Editar > Agregar**.
4. En **Ubicaciones**, elige este equipo. Añade `NT SERVICE\MSSQLSERVER` y `NT SERVICE\SQLSERVERAGENT` (o las cuentas reales que viste en **Servicios**).
5. Para ambas cuentas permite **Modificar** y acepta.

Esto permite que SSIS y Agent creen los archivos de registro; no concedas permisos a `Everyone/Todos`.

## 8. Publicar SSIS en SSISDB y ejecutarlo

### 8.1 Publicar el proyecto

1. En Visual Studio, clic derecho en `Northwind.ETL` > **Implementar / Deploy**.
2. Selecciona destino **SSIS en SQL Server**.
3. Servidor: `localhost`. Usa autenticación de Windows.
4. Como ruta de destino selecciona la carpeta **SSISDB > Northwind** y el proyecto `Northwind.ETL`.
5. Confirma el resumen y pulsa **Implementar / Deploy**.

Si usas el asistente de SSMS, selecciona `Northwind.ETL/bin/Development/Northwind.ispac` como archivo de origen y publica en la misma carpeta. El `.ispac` de Visual Studio se llama `Northwind.ispac` aunque el proyecto del catálogo se llame `Northwind.ETL`.

### 8.2 Vincular los parámetros del proyecto al entorno

1. Regresa a la ventana de consulta de SSMS con `Configure-NorthwindSSIS.sql`.
2. Ejecútala de nuevo con **F5**.
3. En SSMS, expande **Catálogos de Integration Services > SSISDB > Northwind > Proyectos > Northwind.ETL** y revisa sus parámetros y referencias.

**Resultado esperado:** una referencia al entorno `Northwind_Test` y cinco parámetros vinculados: servidor/base de origen, servidor/base del DW y carpeta de logs.

### 8.3 Ejecutar desde el catálogo

1. En el árbol de SSMS expande **Northwind > Proyectos > Northwind.ETL > Paquetes**.
2. Clic derecho en `CargarNorthwind.dtsx` > **Ejecutar**.
3. En la ventana de ejecución, marca que use el entorno y selecciona `Northwind_Test`.
4. Pulsa **Aceptar** para iniciar.
5. Cuando SSMS confirme que terminó, abre **Informes > Informes estándar > Todas las ejecuciones** del proyecto y abre la ejecución más reciente.
6. Revisa el estado general y los mensajes del paquete; el estado debe ser **Correcto / Succeeded**.
7. Repite la consulta de ventas del paso 6.3.

## 9. Publicar y procesar el modelo tabular

### 9.1 Permitir que Analysis Services lea el DW

1. En SSMS, conectado al motor `localhost`, abre `scripts/sql/Configure-NorthwindOLAPAccess.sql`.
2. Ejecuta con **F5**.

**Resultado:** la cuenta del servicio Analysis Services puede leer las seis tablas de `Northwind_DW_Test` que utiliza el modelo. El permiso es `SELECT` sobre esas tablas.

### 9.2 Revisar y publicar el modelo

1. En Visual Studio, expande `Northwind.OLAP` y clic derecho en el proyecto > **Propiedades**.
2. En **Implementación / Deployment**, confirma servidor `localhost` y base del modelo `NorthwindOLAP_Test`; guarda.
3. Abre `Northwind.OLAP.bim`. En el modelo tabular, abre **Orígenes de datos / Data Sources** y confirma que `NorthwindDW` use servidor `localhost` y base `Northwind_DW_Test`.
4. Clic derecho en `Northwind.OLAP` > **Implementar / Deploy**.
5. Espera el mensaje de despliegue correcto.

**Resultado:** en SSMS, conectado a **Analysis Services > localhost**, aparece la base `NorthwindOLAP_Test`.

### 9.3 Procesar los datos

1. En SSMS, actualiza la lista de bases de Analysis Services.
2. Clic derecho en `NorthwindOLAP_Test` > **Procesar base de datos / Process Database**.
3. Elige **Procesar completo / Process Full** y pulsa **Aceptar**.
4. Espera el resultado correcto.

Repite el procesamiento después de cargas hechas en Visual Studio. El job del paso 10 ya hace la carga y el procesamiento como etapas seguidas.

### 9.4 Consultar con DAX

En SSMS, clic derecho en `NorthwindOLAP_Test` > **Nueva consulta > DAX**. Ejecuta:

```DAX
EVALUATE
ROW("Pedidos", [Pedidos distintos],
    "Unidades", [Unidades],
    "Neto", [Ventas netas])
```

**Resultado de referencia:** 830 pedidos, 51.317 unidades y `1.265.792,76` netos.

Prueba también un filtro de producto y año:

```DAX
EVALUATE
ROW("Ventas netas", CALCULATE([Ventas netas],
    Dim_Tiempo[Anio] = 1996,
    Dim_Producto[Categoria] = "Beverages"))
```

**Resultado:** `47.919,00`.

Y un filtro por país y cliente:

```DAX
EVALUATE
ROW("Pedidos", CALCULATE([Pedidos distintos],
    Dim_Cliente[Pais] = "Germany",
    Dim_Cliente[CustomerID] = "ALFKI"),
    "Ventas netas", CALCULATE([Ventas netas],
    Dim_Cliente[Pais] = "Germany",
    Dim_Cliente[CustomerID] = "ALFKI"))
```

**Resultado:** 6 pedidos y `4.273,00` netos.

## 10. Configurar y ejecutar el job

El job combina dos etapas: ejecutar `CargarNorthwind.dtsx` y luego procesar `NorthwindOLAP_Test`. Se crea deshabilitado y el horario también queda deshabilitado.

### 10.1 Permitir que SQL Server Agent procese el modelo

1. En **Servicios**, revisa la cuenta con la que se inicia **SQL Server Agent (MSSQLSERVER)**. Normalmente es `NT SERVICE\SQLSERVERAGENT`.
2. En SSMS, conéctate a **Analysis Services > localhost**.
3. Expande **Bases de datos > NorthwindOLAP_Test > Roles**.
4. Si `NorthwindBIJobProcessor` ya existe, clic derecho > **Propiedades** y revisa **General**, **Permisos** y **Pertenencia**. Si está correcto, continúa con 10.2.
5. Si no existe, clic derecho en **Roles > Nuevo rol**.
6. En **General**, escribe el nombre `NorthwindBIJobProcessor` y selecciona permiso **Procesar base de datos / Process Database**.
7. En **Descripción**, pega exactamente: `Northwind practice processing role managed by Configure-NorthwindJobAccess.ps1.`
8. En **Pertenencia / Membership**, pulsa **Agregar**, elige la cuenta de SQL Server Agent del paso 1 y acepta.

La descripción exacta identifica este rol como el de la práctica. El rol debe revisarse después de volver a implementar el modelo desde Visual Studio.

### 10.2 Crear el job deshabilitado

1. En SSMS conecta a **Motor de base de datos > localhost** usando una cuenta administradora.
2. Selecciona **Archivo > Abrir > Archivo** y abre `scripts/sql/Create-NorthwindBIJob.sql`.
3. Revisa el encabezado. Los valores locales son `localhost`, `Northwind`, `Northwind.ETL`, `Northwind_Test`, paquete `CargarNorthwind.dtsx` y modelo `NorthwindOLAP_Test`.
4. `@StartTime` tiene el valor `'02:00:00'` (hora local del servidor SQL). Puedes cambiarlo, por ejemplo, a `'04:30:00'`.
5. Conserva `@EnableJob = 0` y `@EnableSchedule = 0` durante la prueba.
6. Pulsa **F5**. En el Explorador de objetos actualiza **SQL Server Agent > Trabajos / Jobs**.

**Resultado:** `NorthwindBIJob` con dos pasos nativos y programación diaria, ambos deshabilitados. Si vuelves a ejecutar el script, actualiza el job de la práctica en lugar de duplicarlo.

### 10.3 Ejecutar manualmente y leer el historial

1. En **SQL Server Agent > Trabajos**, clic derecho en `NorthwindBIJob` > **Iniciar trabajo en el paso… / Start Job at Step…**.
2. Selecciona el paso 1 y pulsa **Iniciar**.
3. Espera a que termine. Clic derecho en el job > **Ver historial / View History**.
4. Expande la ejecución más reciente. Debe aparecer primero **carga SSIS** y luego **procesamiento OLAP**, ambos con estado **Correcto / Succeeded**.
5. Si un paso está rojo, selecciónalo y lee el mensaje. Para SSIS también abre el informe **SSISDB > Northwind > Proyectos > Northwind.ETL > Informes > Todas las ejecuciones** y selecciona **Todos los mensajes**.

### 10.4 Confirmar que las dos capas tienen los mismos resultados

En Motor de base de datos ejecuta:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) AS Lineas,
       COUNT(DISTINCT OrderID) AS Pedidos,
       SUM(CONVERT(bigint,Cantidad)) AS Unidades,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas;
SELECT OrderID,
       SUM(Cantidad) AS Unidades,
       SUM(ImporteNeto) AS Neto
FROM dbo.Fact_Ventas
WHERE OrderID=10248
GROUP BY OrderID;
```

En Analysis Services ejecuta otra vez la consulta DAX total de 9.4.

**Resultado esperado en ambos destinos:** 830 pedidos, 51.317 unidades y neto `1.265.792,76`. Para el pedido 10248: 27 unidades y neto `440,00`. El conteo de líneas en DW es 2.155.

### 10.5 Habilitar el horario (opcional)

Hazlo solo después de que 10.3 y 10.4 estén correctos.

1. En **SQL Server Agent > Trabajos**, clic derecho en `NorthwindBIJob` > **Propiedades > Programaciones / Schedules**.
2. Selecciona la programación y pulsa **Editar**.
3. Confirma **Diariamente**, cada 1 día, y la hora local que elegiste. Marca **Habilitada / Enabled** y acepta.
4. En la página **General**, marca el job **Habilitado / Enabled** y acepta.

Para apagar ejecuciones futuras, vuelve a **Propiedades > General** y desmarca **Habilitado**. El job aún se puede ejecutar manualmente desde el menú contextual.

## 11. Qué hacer cada vez que vuelvas a ejecutar el proyecto

### Opción 1: ejecutar y procesar por separado desde las interfaces

1. Inicia los tres servicios en el paso 1 si están detenidos.
2. En Visual Studio abre `Northwind.sln` y ejecuta `CargarNorthwind.dtsx` según el paso 6.
3. En SSMS confirma que el paquete terminó correctamente y que los totales del DW coinciden.
4. En SSMS, conecta a Analysis Services, clic derecho en `NorthwindOLAP_Test` > **Procesar base de datos > Procesar completo**.
5. Ejecuta la consulta DAX del paso 9.4.

### Opción 2: ejecutar todo con el job desde la interfaz

1. En SSMS conecta al motor `localhost`.
2. En **SQL Server Agent > Trabajos**, clic derecho en `NorthwindBIJob` > **Iniciar trabajo en el paso…**.
3. Inicia desde el paso 1, espera el resultado y revisa el historial.
4. Compara DW y OLAP según 10.4.

No ejecutes ambas opciones una tras otra para una misma demostración: el job ya incluye la carga SSIS y el procesamiento del modelo. La carga es incremental y repetible, pero una sola ruta hace más fácil explicar y comprobar cada ejecución.

## 12. Restablecer solo las copias de práctica

Haz este apartado únicamente si de verdad necesitas volver al estado inicial. **Se perderán los cambios de práctica en `Northwind_Test` y `Northwind_DW_Test`.** No toques `NorthWind` ni `Northwind_DW`.

1. En SSMS, deshabilita `NorthwindBIJob` desde **Propiedades > General** y confirma que no haya una ejecución activa.
2. Crea backups completos nuevos de `NorthWind` y `Northwind_DW` siguiendo 3.1. Guarda los archivos `.bak` con nombres fáciles de distinguir.
3. Restaura `NorthWind` como `Northwind_Test` y `Northwind_DW` como `Northwind_DW_Test` siguiendo 3.1–3.2.
4. En cada restauración revisa dos veces el nombre de **Base de datos de destino**. En **Archivos**, especifica archivos físicos con sufijo `_Test`; nunca apuntes a los `.mdf`/`.ldf` de las originales.
5. En **Opciones**, si el destino de prueba ya existe, marca **Sobrescribir la base de datos existente / Overwrite the existing database (WITH REPLACE)** solamente después de comprobar que el destino escrito es el nombre `_Test`. Si hay conexiones activas a la copia, cierra primero consultas, paquetes y ejecuciones del job; no fuerces la restauración de la original.
6. Ejecuta `scripts/sql/Identify-NorthwindCopies.sql` como en 3.3.
7. Repite la publicación de extractores (paso 4), preparación/publicación y calendario del DW (paso 5), carga SSIS (paso 6), configuración/publicación del catálogo SSIS (pasos 7–8), modelo OLAP (paso 9) y creación/prueba del job (paso 10).

Si no estás segura de haber seleccionado la copia `_Test`, cancela la ventana de restauración y verifica el nombre antes de continuar.

## 13. Errores comunes

| Mensaje o síntoma | Comprobación |
| --- | --- |
| `SQLNCLI11 provider is not registered` | Usa el controlador Microsoft OLE DB Driver for SQL Server; en Connection Managers el proveedor debe ser `MSOLEDBSQL.1`. |
| Un proyecto aparece incompatible o descargado | Instala SSDT y las extensiones SSIS/Analysis Services indicadas en 1.2; reinicia Visual Studio. |
| No conecta a `localhost` | En Servicios inicia SQL Server. En SSMS usa Autenticación Windows; para el certificado local habilita **Confiar en el certificado**. |
| No aparece SQL Server Agent | Comprueba que tu edición de SQL Server lo incluya y que el servicio esté instalado/iniciado. |
| No aparece `SSISDB` | Créala una vez en 7.1. Si ya existe, no repitas creación; sigue con la configuración del entorno. |
| El script SSIS dice que la copia no está marcada | Confirma que existen `Northwind_Test` y `Northwind_DW_Test`, y ejecuta la identificación de 3.3. No sustituyas sus nombres por los originales. |
| SSIS no encuentra el entorno `Northwind_Test` | Ejecuta `Configure-NorthwindSSIS.sql` después de publicar el proyecto (paso 8.2) y marca la referencia al entorno en la ventana de ejecución. |
| Falla al escribir el log | Comprueba que existe `C:\ProgramData\NorthwindBI\Logs` y que las cuentas de servicio tienen permiso **Modificar** (7.3). |
| El job falla en el paso SSIS | Abre el historial del job y **SSISDB > Informes > Todas las ejecuciones > Todos los mensajes**. Revisa conexión, entorno y acceso a los logs. |
| El job falla en el paso OLAP | Confirma que existe `NorthwindOLAP_Test`, que SSAS está iniciado y que `NorthwindBIJobProcessor` permite procesar y contiene la cuenta de SQL Server Agent. |
| Los conteos no coinciden | Espera a que termine el job; actualiza las consultas; comprueba que los resultados vienen de `_Test` y que se procesó OLAP después de la carga. No reinicies marcas ni vacíes tablas para ocultar la diferencia. |

## Referencia rápida del orden

`Servicios activos > abrir y compilar Northwind.sln > copias identificadas > publicar extractores > preparar/publicar DW > calendario > ejecutar CargarNorthwind.dtsx > comprobar ventas > crear/configurar SSISDB > publicar SSIS > vincular entorno > dar acceso a SSAS > publicar y procesar modelo > crear job deshabilitado > iniciar job manualmente > revisar historial y comparar resultados > habilitar horario solo si lo necesitas.`

Las guías operativas numeradas 01–10 contienen los mismos procesos en fichas más breves: [índice de guías](docs/01-guia-practica.md).
