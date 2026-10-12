# Entorno de la práctica Northwind

Comprobado el 11 de octubre de 2026. Este registro corresponde al primer segmento (1.1, 1.2 y 1.4). La instalación permite comenzar; todavía no hay una carga ETL ni un modelo analítico desplegados y verificados.

## Programas y destinos comprobados

| Componente | Versión o estado real | Uso y destino |
| --- | --- | --- |
| Visual Studio Community 2026 | 18.10.3; instalación 18.10.12224.181 | Abrir `Northwind.slnx` y editar proyectos |
| MSBuild de Visual Studio 2026 | 18.10.1.42706 | Compilar proyectos SQL tradicionales |
| SSDT / DacFx | Schema.Sql 170.4.53.0; DACFacade 162.5.76.1 | El proyecto OLTP usa proveedor Sql170, SQL Server 2025 |
| SSMS 22 | 22.10.2; instalación 22.10.12217.157 | Conectar al motor y a Analysis Services |
| Motor SQL Server | 17.0.1000.7, Enterprise Developer Edition | Instancia predeterminada `localhost`, autenticación Windows |
| Integration Services Projects 2022+ | Extensión 2.2 | Destino previsto SSIS `SQLServer2025`, a comprobar compilando paquetes en 5.1 |
| Runtime SSIS / DTExec | 170 / 17.0.1000.7 | Runtime local SQL Server 2025 |
| Microsoft Analysis Services Projects | Extensión 4.0.0 | Crear y compilar el modelo tabular en 6.1 |
| Analysis Services | 17.0.25.218, modo **Tabular** | `localhost`; nivel 1700 soportado por el servidor y previsto para el modelo |
| SQL Server Agent | Servicio activo | Ejecutar el futuro job, inicialmente deshabilitado |

Hay además Build Tools 2022 instalado; para esta referencia se utilizó **MSBuild de Visual Studio 2026**, no el de 2022. El archivo de targets SSDT existe en `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Microsoft\VisualStudio\v18.0\SSDT\Microsoft.Data.Tools.Schema.SqlTasks.targets`.

El modo tabular y la lista de niveles compatibles se consultaron mediante AMO conectado al servidor. El nivel máximo observado fue 1700; no se modificó el modo ni el nivel de ninguna base. El intento de leer directamente `msmdsrv.ini` no tuvo acceso, por lo que ese archivo no se utilizó como evidencia.

Los destinos previstos concuerdan con [SSIS Projects](https://marketplace.visualstudio.com/items?itemName=SSIS.MicrosoftDataToolsIntegrationServices) y los [niveles tabulares soportados](https://learn.microsoft.com/en-us/analysis-services/tabular-models/compatibility-level-for-tabular-models-in-analysis-services?view=sql-analysis-services-2025). La presencia de extensiones no demuestra que un paquete o modelo compile: esas pruebas quedan en 5.1 y 6.1. La compilación SQL sí se ejecutó en este segmento.

## Servicios y cuentas

Los cuatro servicios estaban `Running`:

| Servicio | Cuenta Windows | Responsabilidad |
| --- | --- | --- |
| MSSQLSERVER | `NT Service\MSSQLSERVER` | Alojar las bases relacionales |
| MsDtsServer170 | `NT Service\MsDtsServer170` | Servicio Integration Services; no demuestra ejecución de paquetes |
| MSSQLServerOLAPService | `NT Service\MSSQLServerOLAPService` | Alojar/procesar el modelo tabular |
| SQLSERVERAGENT | `NT Service\SQLSERVERAGENT` | Ejecutar trabajos programados |

La sesión actual usa `usuario Windows de la sesión`:

- Motor: `sysadmin = 1`, `CREATE ANY DATABASE = 1`. Tiene permisos para crear las bases de prueba y publicar proyectos SQL.
- SSAS: conexión correcta y pertenencia directa al rol de servidor `Administrators`. Tiene permisos administrativos para un futuro despliegue.
- SSIS: **SSISDB no existe**. El permiso `sysadmin` permitirá prepararlo más adelante, pero no hay todavía carpeta, permisos de catálogo ni ejecución de paquetes comprobada.
- Procesamiento SSAS: no existe login explícito del servicio `NT Service\MSSQLServerOLAPService` en el motor. Si se usa esa cuenta para leer el DW habrá que preparar y comprobar su acceso de lectura en 6.1/7.1. La conexión del usuario administrador no prueba ese acceso. No se otorgaron permisos en este segmento.
- Agent: solamente se encontró el job `syspolicy_purge_history`; no existe un job Northwind. Su identidad efectiva y sus conexiones deberán probarse al ejecutar el job propio en 7.2/8.2.

## Bases existentes

| Base | Compatibilidad relacional | Estado | Función |
| --- | --- | --- | --- |
| NorthWind | 160 | ONLINE | Origen operativo existente |
| Northwind_DW | 170 | ONLINE | Almacén existente, tablas comerciales vacías en esta captura |
| BikeStores | 170 | ONLINE | Referencia del usuario |

La compatibilidad **160/170 de una base SQL** y el nivel **1700 del modelo SSAS** son propiedades diferentes. El motor 17 aloja NorthWind con nivel 160; esta comprobación no cambia esa propiedad. El proyecto apunta a SQL Server 2025, la versión del motor.

En la captura del segmento 01 no existían `Northwind_Test`, `Northwind_DW_Test` ni bases analíticas SSAS. **Actualización del segmento 02:** ambas bases de prueba ya están creadas y verificadas; consulta [pruebas aisladas](03-pruebas-aisladas.md). El modelo SSAS sigue pendiente.

## Compilación inicial

Se ejecutó:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'C:\Proyectos\proyecto-sql-server\Northwind.OLTP\Northwind.OLTP.sqlproj' /t:Build /p:VisualStudioVersion=18.0 /nologo /v:minimal
```

Resultado: código de salida **0**, archivo `Northwind.OLTP\bin\Debug\Northwind.OLTP.dacpac` generado. Hay **19 advertencias SQL71502**, relacionadas con procedimientos heredados que referencian `[dbo].[Order Details]` mientras la tabla del proyecto se llama `[dbo].[OrderDetails]`. Esto permite compilar, pero deja referencias por corregir y verificar antes de publicar. No demuestra que los extractores o el DW funcionen.

Los scripts DW incluidos como `None` en OLTP no forman parte del esquema compilado. Compilar OLTP no crea el DW ni ejecuta esos scripts. La separación en proyectos seguirá las responsabilidades de BikeStores.

## Evidencia y próximos requisitos

La evidencia está en `evidencias/segmento-01`: `herramientas.json`, `visual-studio.json`, `servicios-ssas.json`, `permisos-procesamiento.txt`, `compilacion.txt` y `referencia-sql.txt`. La [validación](validacion.md) registra resultados y diferencias. La [guía inicial](01-guia-practica.md) explica cómo conectarse, abrir y compilar.

No necesitas reinstalar componentes para estos segmentos. Las bases aisladas y herramientas de fixtures ya se prepararon en el segmento 02, usando PowerShell **7.6.5**. Antes del despliegue de paquetes se preparará SSISDB y, antes del procesamiento, la identidad que leerá el DW. Cada preparación tendrá instrucciones y una comprobación en su etapa. Si en otra máquina faltan componentes, seguir la ficha de revisión de herramientas de la guía y la [instalación oficial de SSDT](https://learn.microsoft.com/en-us/sql/ssdt/download-sql-server-data-tools-ssdt?view=sql-server-ver17).
