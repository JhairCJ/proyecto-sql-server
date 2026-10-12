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

Abre **Northwind.slnx** en Visual Studio 2026. En cada proyecto SQL, **Propiedades > Plataforma de destino: SQL Server 2025**; configuración **Debug / Any CPU**. Compila la solución.

**Resultado:** dos proyectos compilados y sus dacpac en bin/Debug. El OLTP conserva 19 advertencias SQL71502 heredadas. Si un proyecto es incompatible, comprueba **Visual Studio Installer > Modificar > Almacenamiento y procesamiento de datos > SSDT**.
