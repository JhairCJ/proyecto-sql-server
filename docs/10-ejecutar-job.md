# 10. Ejecutar y programar el job

## 1. Comprobar servicios y permisos

1. Completa [08](08-publicar-ssis.md) y [09](09-procesar-y-consultar-olap.md).
   En SSMS conectado a **Analysis Services > localhost**, actualiza **Bases de datos** y confirma que `NorthwindOLAP` existe y contiene las ocho tablas finales antes de crear el job.
2. En **Inicio > Servicios**, comprueba **SQL Server Agent (MSSQLSERVER)** en ejecución. En sus **Propiedades > Iniciar sesión**, comprueba la cuenta `NT SERVICE\SQLSERVERAGENT`; si es otra, usa esa cuenta en el paso siguiente.
3. En SSMS conectado a **Analysis Services > localhost**, abre **Bases de datos > NorthwindOLAP > Roles**. Clic derecho en `NorthwindBIJobProcessor` > **Propiedades**; si falta, clic derecho en **Roles > Nuevo rol**.
4. En **General**, nombre `NorthwindBIJobProcessor`, permiso **Procesar base de datos**. Descripción: `Northwind practice processing role managed by Configure-NorthwindJobAccess.ps1.`
5. En **Pertenencia / Membership > Agregar**, agrega la cuenta del Agent; acepta. Revisa este rol después de volver a implementar el modelo desde Visual Studio.

**Resultado:** Agent puede procesar el modelo. [Administrar roles en SSMS](https://learn.microsoft.com/en-us/analysis-services/tabular-models/manage-roles-by-using-ssms-ssas-tabular?view=sql-analysis-services-2025).

## 2. Crear el job

1. En SSMS, conecta al **Motor de base de datos > localhost** con autenticación Windows como administrador.
2. Abre `scripts/sql/Create-NorthwindBIJob.sql` con **Archivo > Abrir > Archivo**.
3. Para cambiar la hora, edita `@StartTime`, por ejemplo `'04:30:00'`; conserva `@EnableJob` y `@EnableSchedule` en `0`. Pulsa **F5**.
4. Actualiza **SQL Server Agent > Trabajos / Jobs**.

**Resultado:** `NorthwindBIJob`, con dos pasos y horario diario deshabilitado. Repetir el script actualiza el mismo job.

## 3. Ejecutar y comprobar

1. Clic derecho en `NorthwindBIJob` > **Iniciar trabajo en el paso… / Start Job at Step…**.
2. Selecciona el paso 1 y pulsa **Iniciar**.
3. Clic derecho en el job > **Ver historial / View History**. Expande la ejecución: carga SSIS y procesamiento tabular deben indicar **Correcto / Succeeded**.
4. Comprueba los totales del DW con [06, paso 2](06-cargar-datos.md#2-comprobar-en-ssms) y los del modelo con [09, paso 4](09-procesar-y-consultar-olap.md#4-consultar).

**Resultado de referencia:** 830 pedidos, 51.317 unidades y neto 1.265.792,76 en ambos destinos.

## 4. Activar o desactivar el horario

Después de comprobar el paso 3:

1. Clic derecho en `NorthwindBIJob` > **Propiedades > Programaciones / Schedules**.
2. Selecciona la programación > **Editar**. Comprueba **Diariamente**, intervalo y hora; marca **Habilitada / Enabled**, acepta.
3. En **General**, marca **Habilitado / Enabled** y acepta.

Para detener futuras ejecuciones, desmarca **Habilitado** en **General**. La ejecución manual sigue disponible.

## 5. Recuperar una ejecución fallida

1. Abre **Ver historial**, expande la ejecución fallida y selecciona el paso rojo para leer el mensaje.
2. Si falla SSIS: en **Catálogos de Integration Services > SSISDB > Northwind > Proyectos > Northwind.ETL**, clic derecho > **Informes > Informes estándar > Todas las ejecuciones**. Abre **Todos los mensajes** de la ejecución fallida.
3. Si falla OLAP: comprueba la conexión a **Analysis Services > localhost**, la base `NorthwindOLAP` y el rol del paso 1.
4. Corrige la causa señalada y vuelve a iniciar el job desde el paso 1. Comprueba de nuevo los totales del apartado 3.

Si el paso 2 informa que no encuentra `NorthwindOLAP`, comprueba su publicación en la misma instancia y el rol de procesamiento de la cuenta del Agent. Si el paso 1 informa `VS_NEEDSNEWMETADATA`, vuelve a publicar los extractores de [03](03-preparar-origen.md) y los siete paquetes de [08](08-publicar-ssis.md), con el mismo origen y DW del entorno.

**Resultado:** ambos pasos correctos. Conserva los datos y las marcas del DW durante el reintento.
