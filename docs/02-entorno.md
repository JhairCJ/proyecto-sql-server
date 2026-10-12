# 02. Configurar el entorno

## 1. Conectar SQL Server

1. En **Inicio > Servicios**, comprueba que **SQL Server (MSSQLSERVER)** esté en ejecución.
2. En SSMS: **Conectar > Motor de base de datos**, servidor `localhost`, **Autenticación de Windows**. Si aparece un error de certificado local, marca **Confiar en el certificado del servidor**.
3. En **Bases de datos**, comprueba que existan `NorthWind` y `Northwind_DW`.

## 2. Abrir y compilar

1. En Visual Studio: **Archivo > Abrir > Proyecto o solución**, abre `Northwind.sln` desde la carpeta del repositorio.
2. En **Ver > Explorador de soluciones**, deben aparecer `Northwind.OLTP`, `Northwind.DW`, `Northwind.ETL` y `Northwind.OLAP` sin «incompatible» ni «descargado».
3. Selecciona **Compilar > Recompilar solución**; en **Ver > Salida**, selecciona **Compilación / Build**.

**Resultado:** `4 succeeded, 0 failed, 0 skipped`. La compilación SSIS de Visual Studio produce `Northwind.ETL\bin\Development\Northwind.ispac`.

Si falta soporte SQL, instala **Visual Studio Installer > Modificar > Almacenamiento y procesamiento de datos > SSDT**. Para ETL y OLAP, instala **SQL Server Integration Services Projects** y **Microsoft Analysis Services Projects** desde **Extensiones > Administrar extensiones**; reinicia Visual Studio cuando lo solicite. Instala **Microsoft OLE DB Driver for SQL Server** si falla el proveedor `MSOLEDBSQL.1`.

## 3. Conectar Analysis Services

1. En **Servicios**, comprueba **SQL Server Analysis Services (MSSQLSERVER)** en ejecución.
2. En SSMS: **Conectar > Analysis Services**, servidor `localhost`, autenticación Windows.
3. Si falta el servicio, abre el instalador de SQL Server > **Agregar características**, selecciona **Analysis Services**, modo **Tabular**, y agrega tu usuario como administrador.

**Resultado:** conexión a Analysis Services Tabular. [Instalación de Analysis Services](https://learn.microsoft.com/en-us/analysis-services/instances/install-windows/install-analysis-services?view=sql-analysis-services-2025).
