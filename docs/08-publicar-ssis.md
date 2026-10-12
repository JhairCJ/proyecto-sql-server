# 08. Publicar SSIS en el servidor

## 1. Crear el catálogo, solo si falta

1. En SSMS, conecta al motor `localhost` como administrador con autenticación Windows.
2. Clic derecho en **Catálogos de Integration Services > Crear catálogo**.
3. Marca **Habilitar integración CLR**, introduce una contraseña nueva y pulsa **Aceptar**. Guarda la contraseña para recuperar el catálogo.

**Resultado:** aparece `SSISDB`. Si ya existe, omite la creación. [Catálogo SSIS](https://learn.microsoft.com/en-us/sql/integration-services/catalog/ssis-catalog?view=sql-server-ver17).

## 2. Preparar entorno y registros

1. En SSMS: **Archivo > Abrir > Archivo**, abre `scripts/sql/Configure-NorthwindSSIS.sql` y pulsa **F5**.
2. En el Explorador de archivos crea `C:\ProgramData\NorthwindBI\Logs` si falta.
3. Clic derecho en esa carpeta > **Propiedades > Seguridad > Editar > Agregar**. Selecciona el equipo local como ubicación y agrega `NT SERVICE\MSSQLSERVER` y `NT SERVICE\SQLSERVERAGENT`; concede **Modificar** a ambas cuentas.

**Resultado:** carpeta `Northwind`, entorno `Northwind_Test` y directorio de registros preparados. Si los permisos ya existen, compruébalos y omite agregarlos.

## 3. Publicar desde Visual Studio

1. Abre `Northwind.sln` y selecciona **Compilar > Recompilar solución**.
2. Clic derecho en `Northwind.ETL` > **Implementar / Deploy**.
3. En el asistente, destino **SSIS en SQL Server**, servidor `localhost`, autenticación Windows; ruta `/SSISDB/Northwind/Northwind.ETL`. Pulsa **Implementar**.
4. Si abres el asistente desde SSMS (**SSISDB > Northwind > Proyectos > Implementar proyecto**), selecciona `Northwind.ETL/bin/Development/Northwind.ispac` como archivo de origen y el mismo destino.
5. Vuelve a ejecutar `Configure-NorthwindSSIS.sql` con **F5** para enlazar los cinco parámetros al entorno.

**Resultado:** `SSISDB > Northwind > Proyectos > Northwind.ETL`, seis paquetes y referencia `Northwind_Test`.

## 4. Ejecutar desde SSMS

1. Abre **Northwind > Proyectos > Northwind.ETL > Paquetes**.
2. Clic derecho en `CargarNorthwind.dtsx` > **Ejecutar**.
3. Marca el uso de entorno y selecciona `Northwind_Test`; pulsa **Aceptar**.
4. Abre el informe de ejecución: debe indicar **Correcto / Succeeded**.
5. Comprueba los totales con la consulta de [06](06-cargar-datos.md).

Continúa con [09. Modelo OLAP](09-procesar-y-consultar-olap.md).
