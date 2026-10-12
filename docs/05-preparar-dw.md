# 05. Preparar el DW y poblar el calendario

Usa la base real `Northwind_DW`. Si todavía no existe, créala vacía siguiendo el paso 02.2 de la [guía paso a paso](<guia paso a paso.md>); no restaures allí `NorthWind.bak`.

## 1. Preparar el esquema

1. En SSMS, ejecuta en `Northwind_DW`:

   ```sql
   USE Northwind_DW;
   SELECT (SELECT COUNT(*) FROM sys.tables) AS TotalTablas,
          OBJECT_ID(N'dbo.Dim_Cliente',N'U') AS DimCliente,
          OBJECT_ID(N'dbo.Fact_Ventas',N'U') AS Hechos;
   ```

2. Si `TotalTablas` es 0 y los otros resultados son `NULL`, omite la migración del DW anterior.
3. Si aparecen `DimCliente` y `Hechos`, abre `Northwind.DW/Deployment/Prepare-LegacyWarehouse.sql` en SSMS, confirma la base seleccionada y pulsa **F5**. Si hay tablas pero falta una de esas dos, detente y revisa la estructura.
4. En Visual Studio, clic derecho en `Northwind.DW` > **Publicar > Cargar perfil**; selecciona `Northwind.DW/Properties/PublishProfiles/Northwind_DW.publish.xml`.
5. Confirma servidor `localhost` y destino `Northwind_DW`. Pulsa **Generar script**, confirma el destino y pulsa **Publicar**.

**Resultado:** se crean tablas, cinco controles y miembros desconocidos iniciales. La publicación no elimina objetos ajenos y bloquea cambios con posible pérdida de datos.

## 2. Poblar calendario

En SSMS, ejecuta con **F5**:

```sql
USE Northwind_DW;
DECLARE @Desde date, @Hasta date;
SELECT @Desde=MIN(Fecha), @Hasta=MAX(Fecha)
FROM NorthWind.dbo.Orders
CROSS APPLY (VALUES(CONVERT(date,OrderDate)),(CONVERT(date,RequiredDate)),
                   (CONVERT(date,ShippedDate))) d(Fecha);
EXEC dbo.DW_LoadDimTiempo @FechaInicio=@Desde,@FechaFin=@Hasta;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

**Resultado de referencia:** 708 días, del 1996-07-04 al 1998-06-11; cinco controles inicializados. Continúa con [07. Ejecutar SSIS](07-ejecutar-ssis.md).
