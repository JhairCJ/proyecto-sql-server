# 05. Publicar y preparar el DW

El perfil `Northwind_DW.publish.xml` apunta al DW real. Revisa el servidor y destino antes de publicar. La compilación del DACPAC por sí sola no publica ni modifica la base.

## Publicación

Si existe `dbo.Fact_Ventas`, haz una copia de seguridad del DW y ejecuta `Northwind.DW/Deployment/Prepare-LegacyWarehouse.sql` en ese destino antes de publicar.

1. En Visual Studio, clic derecho en `Northwind.DW` > **Publicar** > **Cargar perfil** y elige `Northwind.DW/Properties/PublishProfiles/Northwind_DW.publish.xml`.
2. Revisa servidor `localhost` y destino `Northwind_DW`; pulsa **Generar script**, revisa el destino y publica.
3. En SSMS, abre `Northwind.DW/Deployment/Migrate-NorthwindStar.sql`, selecciona `Northwind_DW` y ejecútalo una vez. Si el DW estaba vacío, la etapa queda `SkippedEmpty`; con hechos anteriores, queda `Validated` después de copiar y conciliar los datos.
4. Comprueba la etapa y las ocho tablas con la consulta de [modelo y migración](referencias/modelo-dw.md).

**Resultado:** ocho tablas inglesas y seis controles de carga. La publicación conserva las tablas anteriores para que los consumidores activos puedan cambiarse en coordinación. El proceso de retirada manual posterior está en [modelo y migración del DW](referencias/modelo-dw.md#retirada-explícita-del-modelo-anterior).

Continúa con [07. Ejecutar SSIS](07-ejecutar-ssis.md).

## Apoyo automatizado

Desde PowerShell, en la carpeta de la solución:

```powershell
.\scripts\Publish-NorthwindWarehouse.ps1 -WarehouseDatabase Northwind_DW
```

**Resultado:** respaldo verificado del DW principal, DACPAC compilado desde fuentes limpias, publicación y migración; tablas anteriores y marcas conservadas. La ruta del respaldo queda en `docs/evidencias/seccion-dw/respaldo-dw.txt`.
