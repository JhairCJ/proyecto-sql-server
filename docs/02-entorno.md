# 02. Configurar el entorno desde cero

Si en esta computadora faltan SQL Server o las bases, sigue primero los pasos 01 y 02 de la [guía paso a paso](<guia paso a paso.md>). Allí se instala el motor, se restaura `NorthWind.bak` y se crea `Northwind_DW` vacía desde SSMS.

## 1. Instalar lo necesario

1. Instala SQL Server 2025 Developer con **Database Engine Services** e **Integration Services**; usa instancia predeterminada `MSSQLSERVER` y autenticación Windows.
2. Instala **Analysis Services** en modo **Tabular** y agrega tu usuario como administrador.
3. Instala SSMS.
4. Instala Visual Studio 2026 y SSDT desde la carga de trabajo **Almacenamiento y procesamiento de datos**.
5. En Visual Studio > **Extensiones > Administrar extensiones**, instala **SQL Server Integration Services Projects** y **Microsoft Analysis Services Projects**.
6. Instala Microsoft OLE DB Driver 18 para usar el proveedor `MSOLEDBSQL.1` que ya configura el proyecto.

La guía detallada enlaza las páginas oficiales y muestra las opciones exactas del instalador.

## 2. Conectar y compilar

1. En **Inicio > Servicios**, inicia **SQL Server (MSSQLSERVER)** y **SQL Server Analysis Services (MSSQLSERVER)**. Inicia también **SQL Server Agent (MSSQLSERVER)** para crear o ejecutar el job.
2. En SSMS, conecta al **Motor de base de datos** con servidor `localhost` y autenticación Windows; confirma que aparezcan `NorthWind` y `Northwind_DW`.
3. En Visual Studio, abre `Northwind.sln`. En **Explorador de soluciones** deben estar cargados `Northwind.OLTP`, `Northwind.DW`, `Northwind.ETL` y `Northwind.OLAP`.
4. Selecciona **Compilar > Recompilar solución**; en **Ver > Salida**, selecciona **Compilación / Build**.

**Resultado:** `4 succeeded, 0 failed, 0 skipped`. El paquete compilado está en `Northwind.ETL\bin\Development\Northwind.ispac`.

## 3. Conectar Analysis Services

En SSMS, conecta a **Analysis Services**, servidor `localhost`, autenticación Windows. Si falta el servicio, sigue la [instalación de Analysis Services](https://learn.microsoft.com/en-us/analysis-services/instances/install-windows/install-analysis-services) y selecciona el modo **Tabular**.
