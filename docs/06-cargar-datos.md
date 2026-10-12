# 06. Cargar dimensiones y ventas

**Requisito:** [05. Publicar el DW](05-preparar-dw.md) completada. PowerShell en la carpeta de Northwind.slnx.

## 1. Cargar

```powershell
& '.\scripts\Load-NorthwindWarehouse.ps1'
& '.\scripts\Compare-NorthwindWarehouse.ps1'
```

**Resultado:** cinco entidades «Confirmado»; todas las comparaciones True. Referencia: 91 clientes, 9 empleados, 77 productos, 3 transportistas, 2.155 ventas y 830 pedidos; neto 1.265.792,76. Destinos: Northwind_Test → Northwind_DW_Test, servidor localhost. Otro servidor: añade `-Server 'SERVIDOR\INSTANCIA'` a ambos comandos.

## 2. Repetir

Ejecuta otra vez los mismos comandos.

**Resultado sin cambios de origen:** cero filas extraídas en las cinco entidades; mismas ventas, claves e importes; todas las comparaciones True.

## 3. Ver las cargas en SSMS

En Nueva consulta, ejecuta con F5:

```sql
USE Northwind_DW_Test;
SELECT PackageName,LastRowVersion,LastSuccessfulLoad
FROM dbo.PackageConfig ORDER BY PackageName;
SELECT OrderID,ProductID,Cantidad,PrecioUnitario,Descuento,ImporteNeto
FROM dbo.Fact_Ventas WHERE OrderID=10248 ORDER BY ProductID;
```

**Resultado:** cinco marcas y fechas de éxito; pedido 10248 con tres líneas y neto total 440,00.

**Si falla:** corrige la causa indicada y repite el comando de carga. Si falta una dimensión, ejecuta el cargador completo. Si indica DW ocupado, espera a que termine la otra carga. Si detecta marca incompatible o destino vacío con avance, detén la carga y revisa el origen/destino. No borres tablas finales ni reinicies marcas.
