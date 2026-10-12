# 02. Comprobar el entorno y compilar

Necesitas SQL Server para ejecutar SQL, SSMS para las consultas, PowerShell para preparar copias y Visual Studio con SSDT para compilar.

## 1. Comprobar el servidor desde SSMS

Conecta al motor localhost con autenticación Windows, abre **Nueva consulta** y ejecuta:

```sql
SELECT SERVERPROPERTY('ServerName') AS Servidor,
       SERVERPROPERTY('ProductVersion') AS VersionMotor,
       SERVERPROPERTY('Edition') AS Edicion,SUSER_SNAME() AS Usuario,
       IS_SRVROLEMEMBER('sysadmin') AS EsAdministrador;
SELECT name,state_desc,compatibility_level FROM sys.databases
WHERE name IN(N'NorthWind',N'Northwind_DW');
```

**Comprueba:** servidor local y ambas bases ONLINE. En este equipo: motor 17.0.1000.7 (SQL Server 2025 Developer); compatibilidad 160 para NorthWind y 170 para Northwind_DW. La cuenta de preparación tiene EsAdministrador=1, necesario aquí para preparar/publicar; no es una exigencia para todo futuro usuario.

Si no conecta, abre **Inicio > Servicios**, busca **SQL Server (MSSQLSERVER)** y comprueba **En ejecución**. Usa **Iniciar** si está detenido y tienes permisos. Si tu instancia tiene otro nombre, registra el servidor correcto antes de preparar las copias.

## 2. Abrir PowerShell en el repositorio

Abre PowerShell y ejecuta:

```powershell
Set-Location -LiteralPath 'C:\Users\Admin\Desktop\practica sql\practica sql server'
Get-Location
Test-Path -LiteralPath '.\Northwind.slnx'
Test-Path -LiteralPath '.\tests\Prepare-TestDatabases.ps1'
$PSVersionTable.PSVersion
```

**Comprueba:** ubicación del repo y dos resultados True. Se usa PowerShell 7.6.5. En otra computadora sustituye la ruta por la carpeta que contiene Northwind.slnx. Conserva esta ventana para los comandos PowerShell siguientes; no los pegues en SSMS.

## 3. Abrir y compilar en Visual Studio

1. Abre Visual Studio > **Archivo > Abrir > Proyecto o solución**.
2. Elige **Northwind.slnx** de la carpeta anterior.
3. En el **Explorador de soluciones**, comprueba que aparece **Northwind.OLTP**.
4. Clic derecho en el proyecto > **Propiedades**: plataforma **SQL Server 2025**, configuración **Debug / Any CPU**.
5. Clic derecho en Northwind.OLTP > **Compilar**.
6. Abre **Ver > Salida** y **Ver > Lista de errores**.

**Comprueba:** sin errores y archivo Northwind.OLTP/bin/Debug/Northwind.OLTP.dacpac generado. Actualmente hay 19 advertencias SQL71502 heredadas por referencias a Order Details. Compilar no publica objetos ni carga ventas.

Si el proyecto aparece incompatible, abre **Visual Studio Installer > Modificar > Almacenamiento y procesamiento de datos** y comprueba SSDT. Este equipo usa Visual Studio Community 2026 18.10.3 y SSDT Sql170.

Alternativa desde PowerShell en la raíz del repo, usando la instalación de este equipo:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' '.\Northwind.OLTP\Northwind.OLTP.sqlproj' /t:Build /p:VisualStudioVersion=18.0 /nologo /v:minimal
```

**Comprueba:** código de salida 0. Si tu instalación tiene otra ruta, compila desde la interfaz.

## 4. Reconocer las herramientas posteriores

No se usan en los ejercicios de extracción 04–06.

| Herramienta | Dónde verla | Referencia del equipo |
| --- | --- | --- |
| SSMS | Ayuda > Acerca de | 22.10.2 |
| SSIS Projects | Visual Studio > Extensiones > Administrar extensiones | Integration Services Projects 2022+, 2.2 |
| SSAS Projects | Mismo listado | Analysis Services Projects, 4.0.0 |
| Servicio SSIS | Inicio > Servicios | MsDtsServer170 |
| Servicio SSAS | Inicio > Servicios | MSSQLServerOLAPService, tabular |
| Agent | Inicio > Servicios | SQLSERVERAGENT |

Los servicios de referencia están en ejecución. Los paquetes, modelo, SSISDB y job propio aún requieren implementación/configuración. Tener la herramienta instalada no prueba esas partes del sistema.

**Para pasar a [03](03-pruebas-aisladas.md):** conectas al motor, ves ambas bases originales y estás en la raíz del repositorio.
