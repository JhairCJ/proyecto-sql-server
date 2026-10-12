# 02. Configurar el entorno

## 1. Conectar al motor

En SSMS: **Conectar > Motor de base de datos**; servidor **localhost**, **Autenticación de Windows**. Si el servidor local falla por certificado, activa **Confiar en el certificado del servidor**.

En **Nueva consulta**, ejecuta:

```sql
SELECT SERVERPROPERTY('ProductVersion') AS VersionMotor;
SELECT name,state_desc FROM sys.databases WHERE name IN(N'NorthWind',N'Northwind_DW');
```

**Resultado en este equipo:** motor 17.0.1000.7, ambas bases ONLINE. Si falta conexión, comprueba **Inicio > Servicios > SQL Server (MSSQLSERVER)** en ejecución.

## 2. Abrir el repositorio en PowerShell

```powershell
Set-Location -LiteralPath 'C:\Users\Admin\Desktop\practica sql\practica sql server'
Test-Path -LiteralPath '.\Northwind.slnx'
```

**Resultado:** True. En otra ubicación, reemplaza la ruta por tu carpeta del repositorio. Los comandos siguientes usan esta ventana; no se pegan en SSMS.

## 3. Configurar Visual Studio

1. Abre **Northwind.slnx** en Visual Studio 2026. En `Northwind.OLTP` y `Northwind.DW`, configura **Propiedades > Plataforma de destino: SQL Server 2025** y **Debug / Any CPU**. En el Explorador de soluciones, haz clic derecho en cada proyecto y selecciona **Compilar**.
2. Para el modelo tabular, abre **Extensiones > Administrar extensiones**, busca **Microsoft Analysis Services Projects** e instálala.
3. Cierra y vuelve a abrir Visual Studio cuando el instalador lo solicite.

**Resultado:** los dos proyectos SQL compilan y generan sus dacpac en `bin/Debug`. El OLTP conserva 19 advertencias SQL71502 heredadas. Si un proyecto es incompatible, comprueba **Visual Studio Installer > Modificar > Almacenamiento y procesamiento de datos > SSDT**.

## 4. Preparar Analysis Services

1. En **Servicios de Windows**, comprueba que **SQL Server (MSSQLSERVER)** y **SQL Server Analysis Services (MSSQLSERVER)** estén en ejecución.
2. Si falta Analysis Services, abre **SQL Server Installation Center > Installation > New SQL Server stand-alone installation or add features to an existing installation**. Selecciona **Analysis Services**, configura el modo **Tabular** y agrega tu usuario a sus administradores.
3. En SSMS, elige **Conectar > Analysis Services** y servidor `localhost`. El icono de la instancia en el Explorador de objetos debe indicar modo tabular.

**Resultado:** ambos servicios están en ejecución y SSMS se conecta a una instancia tabular. Si el icono indica modo multidimensional, instala otra instancia en modo tabular; el modo se define durante la instalación. [Instalar Analysis Services](https://learn.microsoft.com/en-us/analysis-services/instances/install-windows/install-analysis-services?view=sql-analysis-services-2025) · [Instalar extensiones de SSDT](https://learn.microsoft.com/en-us/sql/ssdt/download-sql-server-data-tools-ssdt?view=sql-server-ver17).
