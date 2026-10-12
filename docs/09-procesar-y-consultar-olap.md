# 09. Publicar, procesar y consultar OLAP

## 1. Dar acceso al DW

Con el DW cargado, en SSMS conectado al motor `localhost`, abre `scripts/sql/Configure-NorthwindOLAPAccess.sql` y ejecuta con **F5**.

**Resultado:** la cuenta `NT SERVICE\MSSQLServerOLAPService` puede leer las seis tablas de `Northwind_DW`.

## 2. Publicar desde Visual Studio

1. Abre `Northwind.sln`. Clic derecho en `Northwind.OLAP` > **Propiedades**.
2. En **Implementación / Deployment**, comprueba **Servidor = localhost**, **Base de datos = NorthwindOLAP**; acepta.
3. Abre `Northwind.OLAP.bim`. En **Explorador del modelo tabular > Orígenes de datos**, comprueba que `NorthwindDW` use `localhost` y `Northwind_DW`.
4. Clic derecho en `Northwind.OLAP` > **Implementar / Deploy**. Espera el mensaje de implementación correcta.

**Resultado:** `NorthwindOLAP` aparece en SSMS al conectar a **Analysis Services > localhost**.

## 3. Procesar desde SSMS

1. En SSMS: **Conectar > Analysis Services**, servidor `localhost`, autenticación Windows.
2. Actualiza **Bases de datos**. Clic derecho en `NorthwindOLAP` > **Procesar base de datos / Process Database**.
3. Selecciona **Procesar completo / Process Full**, pulsa **Aceptar** y espera el resultado correcto.

Repite este paso después de cada nueva carga SSIS; si ejecutas el job de [10](10-ejecutar-job.md), su segundo paso ya procesa el modelo.

## 4. Consultar

Selecciona `NorthwindOLAP` y abre **Nueva consulta > DAX**. Ejecuta con **F5**:

```DAX
EVALUATE
ROW("Pedidos", [Pedidos distintos], "Unidades", [Unidades], "Neto", [Ventas netas])
```

**Resultado de referencia:** 830 pedidos, 51.317 unidades y neto 1.265.792,76.

```DAX
EVALUATE
ROW("Ventas netas", CALCULATE([Ventas netas],
    Dim_Tiempo[Anio] = 1996, Dim_Producto[Categoria] = "Beverages"))
```

**Resultado:** 47.919,00.

```DAX
EVALUATE
ROW("Pedidos", CALCULATE([Pedidos distintos],
    Dim_Cliente[Pais] = "Germany", Dim_Cliente[CustomerID] = "ALFKI"),
    "Ventas netas", CALCULATE([Ventas netas],
    Dim_Cliente[Pais] = "Germany", Dim_Cliente[CustomerID] = "ALFKI"))
```

**Resultado:** 6 pedidos y 4.273,00 netos. Continúa con [10](10-ejecutar-job.md).
