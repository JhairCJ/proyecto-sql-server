# 09. Procesar y consultar el modelo tabular

**Requisitos:** `Northwind_DW_Test` cargada con la [guía 01](01-guia-practica.md), SSMS y Visual Studio con Analysis Services Projects. Para preparar servicios y extensión por primera vez, sigue [02, pasos 3–4](02-entorno.md#3-configurar-visual-studio). El primer comando requiere permisos para crear el login del servicio SSAS y concederle `SELECT` en las seis tablas de `Northwind_DW_Test`.

## 1. Publicar y procesar

Abre PowerShell en la carpeta que contiene `Northwind.slnx`. Ejecuta:

```powershell
& '.\scripts\Deploy-NorthwindOLAP.ps1' -AnalysisServer localhost -WarehouseServer localhost -WarehouseDatabase Northwind_DW_Test -ModelDatabase NorthwindOLAP_Test
& '.\scripts\Process-NorthwindOLAP.ps1' -AnalysisServer localhost -ModelDatabase NorthwindOLAP_Test -WarehouseServer localhost -WarehouseDatabase Northwind_DW_Test
& '.\scripts\Compare-NorthwindOLAP.ps1'
```

**Resultado:** `PASS`; 830 pedidos, 51.317 unidades y pedido 10248 con 27 unidades y 440,00 bruto/neto.

## 2. Consultar en SSMS

1. En **Conectar > Analysis Services**, escribe `localhost` y usa autenticación de Windows.
2. En el modelo `NorthwindOLAP_Test`, elige **Nueva consulta > DAX**.
3. Ejecuta la consulta con **F5**:

```DAX
EVALUATE
ROW(
    "Ventas netas",
    CALCULATE([Ventas netas], Dim_Tiempo[Anio] = 1996, Dim_Producto[Categoria] = "Beverages")
)
```

**Resultado:** `47.919,00`.

```DAX
EVALUATE
ROW(
    "Pedidos",
    CALCULATE([Pedidos distintos], Dim_Cliente[Pais] = "Germany", Dim_Cliente[CustomerID] = "ALFKI"),
    "Ventas netas",
    CALCULATE([Ventas netas], Dim_Cliente[Pais] = "Germany", Dim_Cliente[CustomerID] = "ALFKI")
)
```

**Resultado:** 6 pedidos y `4.273,00` netos.

Los filtros de cliente/categoría usan sus atributos actuales (tipo 1). La fecha activa es la del pedido; para analizar por otras fechas, usa `[Ventas netas por fecha requerida]` o `[Ventas netas por fecha de envío]`. Un envío sin fecha no aparece en un mes real.

## 3. Volver a procesar después de una carga

Después de cada carga SSIS, vuelve a ejecutar el procesamiento y la comparación desde PowerShell:

```powershell
& '.\scripts\Process-NorthwindOLAP.ps1'
& '.\scripts\Compare-NorthwindOLAP.ps1'
```

**Resultado:** `PASS`. Registro en `docs\evidencias\olap\`.

Referencias para instalar/configurar [Analysis Services en modo tabular](https://learn.microsoft.com/en-us/analysis-services/instances/install-windows/install-analysis-services?view=sql-analysis-services-2025), la [extensión de proyectos](https://learn.microsoft.com/en-us/sql/ssdt/download-sql-server-data-tools-ssdt?view=sql-server-ver17) y ejecutar [consultas DAX](https://learn.microsoft.com/en-us/dax/dax-queries).
