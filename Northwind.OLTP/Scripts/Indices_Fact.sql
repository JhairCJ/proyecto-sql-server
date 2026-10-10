-- Indice de la tabla de hechos
Use Northwind_DW;
go

CREATE INDEX IX_FactVentas_Cliente
ON dbo.Fact_Ventas(Cliente_SK);
GO

CREATE INDEX IX_FactVentas_Empleado
ON dbo.Fact_Ventas(Empleado_SK);
GO

CREATE INDEX IX_FactVentas_Producto
ON dbo.Fact_Ventas(Producto_SK);
GO

CREATE INDEX IX_FactVentas_FechaPedido
ON dbo.Fact_Ventas(FechaPedido_SK);
GO