# Guía de la práctica Northwind desde cero

Esta entrega cubre el inicio: entender las piezas, conectarse a las bases existentes y abrir/compilar el proyecto actual. Los capítulos de extracción, DW, paquetes SSIS, modelo SSAS y job se incorporarán conforme se implementen y comprueben. Puedes seguir estos pasos para aprender; las comprobaciones automáticas del entorno ya están hechas y registradas en [validación](validacion.md).

## 1. Qué estamos construyendo

Northwind representa una empresa que vende productos a clientes. Una **base de datos** guarda información organizada. Una **tabla** agrupa un tipo de información; una **fila** representa un registro y una **columna** una característica. Por ejemplo, `Customers` guarda clientes y `CompanyName` guarda su nombre.

El **esquema** es un agrupador dentro de una base: `dbo.Customers` significa tabla `Customers` del esquema `dbo`. La estructura también se llama esquema en sentido general: tablas, columnas, tipos y relaciones. No confundas ambos usos.

Una **clave primaria** identifica una fila, como `CustomerID`. Una **clave foránea** relaciona tablas: `Orders.CustomerID` permite conocer el cliente del pedido. Un **tipo de dato** define qué puede guardarse: texto, entero, fecha, decimal. `NULL` representa un valor ausente; no equivale a cero ni a texto vacío.

**SQL** es el lenguaje de consulta. `SELECT` lee; `INSERT`, `UPDATE` y `DELETE` cambian datos. Una **vista** conserva una consulta como objeto reutilizable. Un **procedimiento almacenado** guarda instrucciones que se invocan con `EXEC`; algunos leen y otros escriben. Una **transacción** permite confirmar un conjunto de cambios o revertirlos juntos si algo falla. Un **índice** ayuda a buscar y puede imponer unicidad.

`rowversion` es una marca binaria que cambia al insertar/actualizar filas de tablas que la incluyen; no es una fecha. Más adelante servirá para identificar cambios. `PackageConfig` guardará la última marca confirmada por entidad para retomar una carga.

| Pieza | Para qué sirve aquí | Analogía sencilla |
| --- | --- | --- |
| SQL Server (motor) | Aloja y ejecuta consultas sobre las bases | El lugar donde viven los datos |
| SSMS | Interfaz para conectarte, consultar y administrar SQL Server/SSAS | Una consola de trabajo |
| Visual Studio + SSDT | Organiza y compila los proyectos | El taller donde editamos la solución |
| OLTP / NorthWind | Datos operativos: pedidos y sus líneas | Registro diario de la empresa |
| DW / Northwind_DW | Datos preparados para análisis | Información organizada para responder preguntas |
| Staging / esquema std | Recepción temporal de datos extraídos | Mesa de preparación antes de la carga final |
| SSIS / ETL | Extraer, transformar y cargar los datos | El recorrido que mueve y prepara información |
| SSAS / modelo tabular | Relaciones y medidas para análisis | Una capa para explorar ventas por cliente, fecha, etc. |
| SQL Server Agent / job | Programa la ejecución de etapas | El encargado del horario |

Un **servicio** funciona en segundo plano. Cerrar SSMS o Visual Studio no detiene por sí mismo el motor. Una **instancia** es un servicio SQL Server al que te conectas; `localhost` señala esta computadora y aquí conecta a la instancia predeterminada. Una **base** está dentro de esa instancia. Windows Authentication usa tu identidad Windows; no necesitas inventar usuario y contraseña SQL.

Una **solución** (`.slnx`) agrupa proyectos. Un **proyecto SQL** (`.sqlproj`) describe objetos de una base. **Compilar** verifica esa descripción y genera un `.dacpac`, un paquete del esquema. **Publicar** aplica diferencias a una base real. Compilar no carga ventas ni publica automáticamente.

## 2. Cómo se relacionan los datos

`Orders` tiene una fila por pedido. `OrderDetails` tiene una fila por producto incluido en un pedido: un pedido puede tener varias líneas. El precio vendido está en `OrderDetails.UnitPrice`; el precio actual del catálogo está en `Products.UnitPrice` y puede ser diferente.

El pedido 10248 tiene tres líneas (productos 11, 42 y 72), 27 unidades y total 440 sin descuento. Cuando construyamos `Fact_Ventas`, una fila representará **una línea**, no un pedido completo. Por eso contar filas del hecho no será lo mismo que contar pedidos distintos.

Una **dimensión** describe entidades por las que quieres filtrar (cliente, empleado, producto, transportista, fecha). Una **tabla de hechos** guarda medidas (cantidad e importes) y referencias a dimensiones. Esa organización es el **modelo estrella**. La clave comercial viene del origen, como `ProductID`; una clave sustituta, como `Producto_SK`, identifica la fila en el DW.

Seguimos el diseño lógico de BikeStores: **OLTP → staging/DW → ETL de dimensiones → ETL de hechos → modelo tabular → job**. Adaptamos el negocio: aquí hay transportistas y no tiendas equivalentes a BikeStores. Los nombres y contenidos podrán mejorarse junto con sus referencias y esta guía.

## 3. Revisar programas y servicios

**Objetivo y motivo:** saber qué ejecuta cada etapa y distinguir lo instalado de lo pendiente.

**Requisitos / programa:** Windows, Visual Studio Community 2026 18.10.3, SSMS 22.10.2. Las versiones y cuentas están en [entorno](entorno.md).

**Preparado:** motor, SSIS 170, SSAS tabular y Agent activos; SSDT y extensiones instalados; bases de prueba creadas en el segmento 02. **Pendiente:** catálogo SSISDB, proyectos DW/ETL/OLAP y job propio.

1. Abre Inicio, busca **Servicios / Services** y abre la aplicación.
2. Localiza **SQL Server (MSSQLSERVER)**, **SQL Server Integration Services 17.0**, **SQL Server Analysis Services (MSSQLSERVER)** y **SQL Server Agent (MSSQLSERVER)**. Los nombres visibles pueden estar traducidos; sus identificadores están en `entorno.md`.
3. Comprueba que el estado sea **En ejecución / Running**. Ya lo comprobé en esta computadora; no necesitas reiniciarlos.
4. Para revisar extensiones, abre Visual Studio y entra en **Extensions > Manage Extensions / Extensiones > Administrar extensiones**. Busca entre las instaladas **SQL Server Integration Services Projects 2022+** (2.2) y **Microsoft Analysis Services Projects** (4.0.0).
5. Si un proyecto SQL no se reconoce, abre **Visual Studio Installer**, selecciona **Modify / Modificar** en Community 2026 y revisa **Data storage and processing / Almacenamiento y procesamiento de datos**, incluyendo SSDT. En este equipo SSDT ya compiló el proyecto: no hace falta modificar la instalación.

**Resultado esperado / verificación:** servicios activos y herramientas presentes, como muestran las evidencias. La revisión de extensiones sigue la [documentación de SSDT](https://learn.microsoft.com/en-us/sql/ssdt/download-sql-server-data-tools-ssdt?view=sql-server-ver17).

**Errores y recuperación:** si el motor está detenido, la conexión del siguiente apartado fallará. Puedes iniciarlo desde su menú contextual **Start / Iniciar** si tu cuenta tiene permisos; si falla, registra el mensaje. No cambies cuentas de servicio ni el modo de SSAS para solucionar una conexión. Un servicio SSIS activo no sustituye la creación del catálogo SSISDB.

## 4. Conectarte al motor y reconocer las bases

**Objetivo y motivo:** leer el origen y comprobar dónde están los datos.

**Requisitos / programa:** SSMS 22.10.2, servicio MSSQLSERVER activo, sesión Windows `usuario Windows de la sesión`.

**Preparado:** NorthWind y Northwind_DW existen y están ONLINE; Northwind_Test y Northwind_DW_Test también están preparadas (ver apartado 8). **Pendiente:** catálogo SSISDB.

1. Abre **SQL Server Management Studio 22** desde Inicio.
2. En **Object Explorer / Explorador de objetos**, selecciona **Connect > Database Engine / Conectar > Motor de base de datos**.
3. Escribe servidor **`localhost`** y elige **Windows Authentication / Autenticación de Windows**. No introduzcas contraseña SQL.
4. Si aparece un error de certificado no confiable al conectarte a este servidor local, activa **Trust server certificate / Confiar en el certificado del servidor** en las opciones de conexión y vuelve a conectar. La comprobación automática local usó esa opción (`sqlcmd -C`).
5. Pulsa **Connect / Conectar**. Expande **Databases / Bases de datos**: deben aparecer `NorthWind`, `Northwind_DW` y `BikeStores`.
6. Expande **NorthWind > Tables / Tablas**. Busca `dbo.Customers`, `dbo.Orders` y **`dbo.OrderDetails`**, sin espacio entre Order y Details.
7. Selecciona NorthWind y pulsa **New Query / Nueva consulta**. Ejecuta el siguiente bloque con **Execute / Ejecutar** (F5). El `USE` fija explícitamente la base de esta consulta.

```sql
USE NorthWind;
SELECT DB_NAME() AS BaseActual;
SELECT COUNT(*) AS Clientes FROM dbo.Customers;
SELECT COUNT(*) AS Pedidos FROM dbo.Orders;
SELECT COUNT(*) AS Lineas,
       SUM(CONVERT(bigint, Quantity)) AS Unidades
FROM dbo.OrderDetails;
SELECT OrderID, ProductID, UnitPrice, Quantity, Discount
FROM dbo.OrderDetails
WHERE OrderID = 10248
ORDER BY ProductID;
```

**Resultado esperado / verificación:** BaseActual NorthWind, 91 clientes, 830 pedidos, 2.155 líneas y 51.317 unidades. El último resultado tiene tres filas: (11, 14, 12, 0), (42, 9,8, 10, 0), (72, 34,8, 5, 0), mostrando producto, precio, cantidad y descuento. Estos valores corresponden a la captura; si cambias datos podrán variar. Los pasos de conexión siguen [SSMS: conectar](https://learn.microsoft.com/en-us/ssms/quickstarts/ssms-connect).

**Errores y recuperación:** si dice `Invalid object name`, comprueba BaseActual y el nombre `OrderDetails`; no crees otra tabla para evitar el error. Si faltan bases, confirma servidor y refresca el nodo Databases. Una instancia distinta puede tener datos distintos. Si falla la autenticación, conserva el error y verifica la cuenta Windows usada; no cambies a un login SQL inventado.

## 5. Reconocer el DW y sus marcas

**Objetivo y motivo:** distinguir preparación del esquema de carga de datos.

**Requisitos / programa:** misma conexión de SSMS al motor `localhost`; lectura de Northwind_DW.

**Preparado:** dimensiones, hechos, staging y controles creados, ocho procedimientos existentes. **Pendiente:** adaptación y pruebas de calendario/hechos/control; todavía no se ejecutaron paquetes del proyecto.

1. Abre una nueva consulta en SSMS y ejecuta:

```sql
USE Northwind_DW;
SELECT DB_NAME() AS BaseActual;
SELECT COUNT(*) AS ClientesCargados FROM dbo.Dim_Cliente;
SELECT COUNT(*) AS LineasCargadas FROM dbo.Fact_Ventas;
SELECT PackageName, LastRowVersion, LastSuccessfulLoad
FROM dbo.PackageConfig
ORDER BY PackageName;
SELECT COL_LENGTH('std.Empleado', 'SupervisorName') AS LongitudSupervisor;
```

2. En Object Explorer, expande **Northwind_DW > Tables** y distingue `dbo.Dim_...`, `dbo.Fact_Ventas`, `dbo.PackageConfig` y las tablas `std`.
3. Expande **Programmability > Stored Procedures / Programación > Procedimientos almacenados** para localizar los cuatro `DW_MergeDim...`, `DW_LoadDimTiempo`, `DW_MergeFactVentas` y los dos procedimientos de control. Esta etapa solo los identifica; no los ejecutes como una carga completa todavía.

**Resultado esperado / verificación:** cero clientes y cero hechos en esta captura; cinco controles (Cliente, Empleado, Producto, Transportista, Ventas), marca `0x0000000000000000`, fecha NULL. LongitudSupervisor = 120 bytes: `nvarchar(60)` usa dos bytes por carácter. La referencia completa incluye conteos exactos de todas las tablas.

**Errores y recuperación:** si hay datos o marcas diferentes, vuelve a capturar el estado antes de una migración. No borres datos ni reinicies marcas para hacerlos coincidir con este documento. Si no aparece SupervisorName, verifica la instancia y base: esta captura sí encontró la columna.

## 6. Abrir y compilar la solución actual

**Objetivo y motivo:** comprobar la estructura del proyecto sin confundir compilación con publicación.

**Requisitos / programa:** Visual Studio Community 2026, SSDT presente. Archivos en `C:\Proyectos\proyecto-sql-server`.

**Preparado:** `Northwind.slnx` contiene solamente `Northwind.OLTP`. **Pendiente:** integración de DW, ETL y OLAP; todavía no aparecerán cuatro proyectos como en BikeStores.

1. Abre Visual Studio. Selecciona **File > Open > Project/Solution / Archivo > Abrir > Proyecto o solución**.
2. Elige `C:\Proyectos\proyecto-sql-server\Northwind.slnx`.
3. En **Solution Explorer / Explorador de soluciones**, expande `Northwind.OLTP`: `dbo/Tables` describe tablas, `dbo/Stored Procedures` procedimientos, `dbo/Views` vistas. `Scripts` contiene archivos auxiliares, incluidos los scripts actuales del DW.
4. Haz clic derecho en `Northwind.OLTP`, abre **Properties / Propiedades** y comprueba **Target platform / Plataforma de destino: SQL Server 2025**. El proveedor Sql170 ya está configurado; no necesitas cambiarlo. La configuración de compilación usada es **Debug / Any CPU**.
5. Haz clic derecho en el proyecto y selecciona **Build / Compilar**. Revisa **Output / Salida** y **Error List / Lista de errores** desde el menú **View / Ver**.
6. Comprueba que exista `Northwind.OLTP\bin\Debug\Northwind.OLTP.dacpac`. Puedes abrir la carpeta con el Explorador de archivos.

**Resultado esperado / verificación:** compilación sin errores y, en el estado inicial, 19 advertencias SQL71502 por referencias a `Order Details`. Ya se generó el dacpac mediante MSBuild, con registro en `evidencias/segmento-01/compilacion.txt`. Los pasos de compilación por proyecto siguen [SQL Database Projects](https://learn.microsoft.com/en-us/sql/tools/sql-database-projects/get-started?view=sql-server-ver17).

**Errores y recuperación:** si el proyecto aparece incompatible, revisa SSDT con la ficha 3. Si MSBuild busca targets `v11.0` desde otra terminal, utiliza el comando de [entorno](entorno.md) con `VisualStudioVersion=18.0`. Las advertencias por nombres de tablas requieren corregir referencias durante la implementación; no justifican renombrar la tabla real improvisadamente. **Publicar** se explicará después de preparar el destino y revisar su script; el dacpac inicial no debe usarse todavía como una migración validada.

## 7. Conectarte a Analysis Services

**Objetivo y motivo:** reconocer el servidor analítico separado del motor relacional.

**Requisitos / programa:** SSMS 22.10.2 y servicio MSSQLServerOLAPService activo, misma cuenta Windows administradora.

**Preparado:** SSAS tabular en localhost, permisos administrativos y nivel 1700 soportado. **Pendiente:** no hay modelos desplegados ni procesamiento probado.

1. En SSMS, abre **Object Explorer > Connect > Analysis Services / Explorador de objetos > Conectar > Analysis Services**.
2. Usa servidor **`localhost`** y autenticación Windows; conecta.
3. Expande **Databases / Bases de datos** de esta conexión. Actualmente no hay ninguna base analítica; NorthWind y Northwind_DW pertenecen a la conexión del motor, no a esta.
4. Haz clic derecho en el servidor SSAS, abre **Properties / Propiedades** y revisa **Supported Compatibility Level / Nivel de compatibilidad soportado**: máximo 1700. Es una propiedad de lectura, no se cambia para preparar el modelo.

**Resultado esperado / verificación:** conexión al servicio tabular y sin modelos existentes. Modo, niveles y rol se verificaron automáticamente mediante AMO. La ubicación de la propiedad está documentada en [compatibilidad tabular](https://learn.microsoft.com/en-us/analysis-services/tabular-models/compatibility-level-for-tabular-models-in-analysis-services?view=sql-analysis-services-2025).

**Errores y recuperación:** si el servidor no conecta, comprueba el tipo de servidor seleccionado y el servicio SSAS. Poder conectar al motor no implica poder conectar a SSAS. Si aparece denegación de permisos, registra la identidad y error. Los permisos para que el servicio lea el DW se prepararán junto con el modelo; todavía no debes intentar procesar una base inexistente.

## 8. Preparación de bases de prueba

Ya están preparadas `Northwind_Test` y `Northwind_DW_Test`. Lee [bases de prueba aisladas](pruebas-aisladas.md) para reconocerlas en SSMS, repetir la preparación sin sobrescribir y ejecutar fixtures con guardas. No necesitas repetir la creación: se ejecutó y verificó automáticamente.

## 9. Próximo segmento

Corregir el contrato de marcas de cambios y la extracción de clientes, con pruebas en las copias. Cuando pidas continuar, elegiré automáticamente el siguiente segmento verificable y explicaré cualquier acción requerida en los programas con objetivo, valores, pasos, resultado y comprobación.
