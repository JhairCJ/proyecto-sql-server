# 05. Preparar el DW y poblar el calendario

## 1. Publicar

1. Completa [03](03-pruebas-aisladas.md).
2. En SSMS: **Archivo > Abrir > Archivo**, abre `Northwind.DW/Deployment/Prepare-LegacyWarehouse.sql`. Selecciona `Northwind_DW_Test` en la lista de bases de la consulta y pulsa **F5**.
3. En Visual Studio, clic derecho en `Northwind.DW` > **Publicar > Cargar perfil**; selecciona `Northwind.DW/Properties/PublishProfiles/Northwind_DW_Test.publish.xml`.
4. Comprueba servidor `localhost`, destino `Northwind_DW_Test`, y pulsa **Publicar**.

**Resultado:** publicación correcta; datos y marcas existentes conservados.

## 2. Poblar calendario

En SSMS, ejecuta con **F5**:

```sql
USE Northwind_DW_Test;
DECLARE @Desde date, @Hasta date;
SELECT @Desde=MIN(Fecha), @Hasta=MAX(Fecha)
FROM Northwind_Test.dbo.Orders
CROSS APPLY (VALUES(CONVERT(date,OrderDate)),(CONVERT(date,RequiredDate)),
                   (CONVERT(date,ShippedDate))) d(Fecha);
EXEC dbo.DW_LoadDimTiempo @FechaInicio=@Desde,@FechaFin=@Hasta;
SELECT COUNT(*) AS Dias,MIN(Fecha) AS Desde,MAX(Fecha) AS Hasta
FROM dbo.Dim_Tiempo WHERE Tiempo_SK<>0;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
```

**Resultado de referencia:** 708 días, del 1996-07-04 al 1998-06-11; cinco controles. En una copia nueva, las marcas son cero y las fechas NULL. Continúa con [07. Ejecutar SSIS](07-ejecutar-ssis.md).
