# 07. Ejecutar SSIS

## 1. Preparar las bases, solo la primera vez

Completa [03](03-pruebas-aisladas.md) y [05](05-preparar-dw.md). Si ya tienes las copias y los proyectos SQL publicados, pasa al paso 2.

## 2. Abrir en Visual Studio

1. **Archivo > Abrir > Proyecto o solución**: selecciona `Northwind.sln`.
2. Abre **Ver > Explorador de soluciones** (atajo `Ctrl+Alt+L`). Expande `Northwind.ETL` y abre `Project.params`.
3. Comprueba los valores predeterminados:

| Parámetro | Valor |
| --- | --- |
| SourceServer | localhost |
| WarehouseServer | localhost |
| SourceDatabase | Northwind_Test |
| WarehouseDatabase | Northwind_DW_Test |
| LogDirectory | . |

En tu equipo usa esos valores tal como están. Solo cámbialos si el servidor o los nombres de las bases son distintos; deja `LogDirectory` como está para la primera ejecución.

4. En el **Explorador de soluciones**, expande `Northwind.ETL > Connection Managers`. Ahí están `Origen.conmgr` y `DW.conmgr`. También aparecen abajo en el diseñador SSIS con el prefijo `(project)`. Ambos lugares muestran las mismas conexiones del proyecto; no crees conexiones nuevas.
5. No hace falta editar ni probar las conexiones si usarás los valores de la tabla: el proyecto ya está configurado con `MSOLEDBSQL.1` y autenticación de Windows. Si cambiaste el servidor o la base, haz doble clic en cada `.conmgr`, pulsa **Probar conexión** y guarda con **Aceptar**.
6. Clic derecho en `Northwind.ETL` > **Propiedades**. Comprueba que `TargetServerVersion` indique `SQL Server 2025`; ya está configurado así. No necesitas cambiar propiedades para ejecutar la carga.

## 3. Cargar los datos

1. En **Explorador de soluciones > Northwind.ETL > SSIS Packages**, haz doble clic en `CargarNorthwind.dtsx`.
2. Abre la pestaña **Flujo de control / Control Flow**. Cada rectángulo llamado `Cargar Cliente`, `Cargar Empleado`, `Cargar Producto`, `Cargar Transportista` o `Cargar Ventas` es un **Sequence Container**: contiene las tareas que cargan esa entidad, en orden.
3. Si el rectángulo está contraído, pulsa la flecha pequeña de su esquina superior izquierda para expandirlo. Dentro, busca la tarea `Extraer a staging`.
4. Haz doble clic en `Extraer a staging`. Se abre el **Flujo de datos / Data Flow**, donde verás **OLE DB Source** conectado con **OLE DB Destination**. Vuelve a **Control Flow** con su pestaña.
5. En el espacio de diseño, clic derecho en `CargarNorthwind.dtsx` > **Ejecutar paquete**.
6. Espera **Package execution completed with success**. Detén la depuración con **Mayús+F5**.

## 4. Comprobar y repetir

En SSMS, conecta a `localhost` con **Autenticación de Windows**. En **Nueva consulta**, ejecuta con **F5**:

```sql
USE Northwind_DW_Test;
SELECT COUNT(*) Lineas, COUNT(DISTINCT OrderID) Pedidos,
       SUM(Cantidad) Unidades, SUM(ImporteNeto) Neto
FROM dbo.Fact_Ventas;
SELECT PackageName, CONVERT(bigint,LastRowVersion) Marca, LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

Resultado con Northwind original: **2155 líneas, 830 pedidos, 51317 unidades, neto 1265792.76**; cinco marcas con fecha. Ejecuta nuevamente el paquete: los conteos y el neto se mantienen.

## 5. Localizar un error

En Visual Studio abre **Progreso / Progress** del paquete y lee el primer error rojo.

Si aparece `SQLNCLI11 ... not registered`, cambia el proveedor a `MSOLEDBSQL.1`. Si falla una conexión, revisa los cuatro parámetros del paso 2 y **Probar conexión**. Si aparece `DW ocupado`, espera a que termine la otra carga y vuelve a ejecutar el principal.
