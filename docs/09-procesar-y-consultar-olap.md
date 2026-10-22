# 09. Publicar, procesar y consultar el modelo tabular

## Conceder lectura

Con el DW cargado, conecta SSMS a **Motor de base de datos > localhost**, abre `scripts/sql/Configure-NorthwindOLAPAccess.sql` y pulsa **F5**.

**Resultado:** la cuenta del servicio SSAS tiene `SELECT` en las ocho tablas finales de `Northwind_DW`.

## Publicar y procesar

1. En Visual Studio, abre `Northwind.sln`; clic derecho en `Northwind.OLAP` > **Propiedades** > **Implementación**. Confirma servidor `localhost` y modelo `NorthwindOLAP`.
2. En `Northwind.OLAP.bim`, confirma que el origen `NorthwindDW` use `localhost/Northwind_DW`.
3. Clic derecho en el proyecto > **Implementar**. En SSMS conectado a **Analysis Services > localhost**, procesa `NorthwindOLAP` con **Procesamiento completo**.
4. Actualiza **Bases de datos > NorthwindOLAP > Tablas**: deben aparecer `FactSales`, `DimDate`, `DimProduct`, `DimCustomer`, `DimEmployee`, `DimShipper`, `DimSupplier` y `DimGeography`.

Después de cargar datos nuevos, vuelve a procesar el modelo. El job de [10](10-ejecutar-job.md) también hace ese segundo paso.

Para Power BI Desktop usa **Obtener datos > SQL Server Analysis Services**, servidor `localhost`, base `NorthwindOLAP` y **Conectar en vivo**. La cuenta Windows que abre Power BI necesita **Lectura** en el modelo: en SSMS > **NorthwindOLAP > Roles**, crea un rol de lectura y agrega esa cuenta si no tiene acceso. El permiso de procesamiento del Agent es independiente.

Como apoyo, desde PowerShell en la carpeta de la solución, ejecuta con una cuenta administradora de SSAS:

```powershell
.\scripts\Configure-NorthwindPowerBIAccess.ps1 -ModelDatabase NorthwindOLAP
```

**Resultado:** el usuario actual queda en el rol `NorthwindPowerBIReader`, con lectura del modelo. Para otro usuario Windows, agrega `-MemberName 'EQUIPO\Usuario'` con su identidad real.

## Consultar con DAX

En SSMS, selecciona `NorthwindOLAP` y abre **Nueva consulta > DAX**.

```DAX
EVALUATE
ROW("Pedidos", [Pedidos distintos], "Unidades", [Unidades],
    "Ventas netas", [Ventas netas], "Flete", [Flete total],
    "Pedidos sin flete", [Pedidos sin flete informado])
```

Para pedido 10248, el flete de 32,38 aparece una sola vez aunque el pedido tenga tres líneas:

```DAX
EVALUATE
CALCULATETABLE(
    ROW("Líneas", COUNTROWS(FactSales), "Flete", [Flete total],
        "Neto", [Ventas netas]),
    FactSales[OrderID] = 10248)
```

Ubicación del cliente y destino son filtros separados:

```DAX
EVALUATE
ROW(
    "Ventas por cliente en Alemania",
    CALCULATE([Ventas netas], DimCustomer[CustomerID] = "ALFKI",
        DimCustomer[Country] = "Germany"),
    "Flete de pedido enviado a Francia",
    CALCULATE([Flete total], FactSales[OrderID] = 10248,
        DimGeography[ShipCountry] = "France"))
```

Para analizar por fecha requerida o envío, usa las medidas `... por fecha requerida` y `... por fecha de envío`; la relación activa corresponde a la fecha de pedido. Al segmentar por producto o proveedor, los subtotales de Freight pueden solaparse: no los sumes entre grupos. Continúa con [10](10-ejecutar-job.md).
