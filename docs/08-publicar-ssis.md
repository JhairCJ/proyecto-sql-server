# 08. Publicar SSIS en el servidor

## 1. Crear el catálogo en SSMS

1. Conecta al motor `localhost` con **Autenticación de Windows**.
2. En **Explorador de objetos**, clic derecho en **Catálogos de Integration Services > Crear catálogo**.
3. Marca **Habilitar integración CLR**, conserva `SSISDB` e introduce y confirma una contraseña para su clave maestra. Guárdala para recuperación y pulsa **Aceptar**.
4. En `SSISDB`, clic derecho > **Crear carpeta**: `Northwind`.

Si ya existen `SSISDB` y `Northwind`, continúa con el paso 2.

## 2. Publicar el proyecto

En PowerShell, desde la carpeta de `Northwind.slnx`:

```powershell
& '.\scripts\Build-NorthwindETL.ps1'
```

En SSMS:

1. Abre **Catálogos de Integration Services > SSISDB > Northwind > Proyectos**.
2. Clic derecho en **Proyectos > Implementar proyecto**.
3. Selecciona **Archivo de implementación de proyecto**: `Northwind.ETL\bin\Development\Northwind.ETL.ispac`.
4. Destino: `localhost`, **Autenticación de Windows**, carpeta `/SSISDB/Northwind`. Pulsa **Conectar > Siguiente > Implementar**.
5. Comprueba que todas las acciones indiquen **Correcto / Passed**.

## 3. Ejecutar y comprobar

1. Abre `Northwind > Proyectos > Northwind.ETL > Paquetes`.
2. Clic derecho en `CargarNorthwind.dtsx` > **Ejecutar**.
3. En **Parámetros**, usa los cuatro valores de la [guía 07](07-ejecutar-ssis.md). Para `LogDirectory`, utiliza una carpeta existente donde la cuenta de ejecución tenga permiso de escritura.
4. Pulsa **Aceptar** y abre el informe de ejecución. Comprueba **Correcto / Succeeded** y ejecuta la consulta del paso 4 de la guía 07.

[Asistente de publicación](https://learn.microsoft.com/en-us/sql/integration-services/ssis-quickstart-deploy-ssms?view=sql-server-ver17). [Creación del catálogo](https://learn.microsoft.com/en-us/sql/integration-services/catalog/ssis-catalog?view=sql-server-ver17).
