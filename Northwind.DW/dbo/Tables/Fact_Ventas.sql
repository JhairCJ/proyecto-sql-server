CREATE TABLE dbo.Fact_Ventas (
    Venta_SK BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Fact_Ventas PRIMARY KEY,

    -- Llaves hacia dimensiones
    Cliente_SK INT NOT NULL,
    Empleado_SK INT NOT NULL,
    Producto_SK INT NOT NULL,
    Transportista_SK INT NULL,

    -- Dimensión tiempo
    FechaPedido_SK INT NOT NULL,
    FechaRequerida_SK INT NULL,
    FechaEnvio_SK INT NULL,

    -- Dimensión degenerada
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,

    -- Medidas
    Cantidad SMALLINT NOT NULL,
    PrecioUnitario DECIMAL(19,4) NOT NULL,
    Descuento DECIMAL(9,6) NOT NULL,

    ImporteBruto DECIMAL(18,2) NOT NULL,
    ImporteDescuento DECIMAL(18,2) NOT NULL,
    ImporteNeto DECIMAL(18,2) NOT NULL,

    CONSTRAINT UQ_FactVentas_Order_Product UNIQUE(OrderID,ProductID),
    CONSTRAINT CK_FactVentas_Cantidad CHECK(Cantidad>0),
    CONSTRAINT CK_FactVentas_Precio CHECK(PrecioUnitario>=0),
    CONSTRAINT CK_FactVentas_Descuento CHECK(Descuento>=0 AND Descuento<=1),
    -- Foreign Keys
    CONSTRAINT FK_FactVentas_Cliente
        FOREIGN KEY (Cliente_SK)
        REFERENCES dbo.Dim_Cliente(Cliente_SK),

    CONSTRAINT FK_FactVentas_Empleado
        FOREIGN KEY (Empleado_SK)
        REFERENCES dbo.Dim_Empleado(Empleado_SK),

    CONSTRAINT FK_FactVentas_Producto
        FOREIGN KEY (Producto_SK)
        REFERENCES dbo.Dim_Producto(Producto_SK),

    CONSTRAINT FK_FactVentas_Transportista
        FOREIGN KEY (Transportista_SK)
        REFERENCES dbo.Dim_Transportista(Transportista_SK),

    CONSTRAINT FK_FactVentas_FechaPedido
        FOREIGN KEY (FechaPedido_SK)
        REFERENCES dbo.Dim_Tiempo(Tiempo_SK),

    CONSTRAINT FK_FactVentas_FechaRequerida
        FOREIGN KEY (FechaRequerida_SK)
        REFERENCES dbo.Dim_Tiempo(Tiempo_SK),

    CONSTRAINT FK_FactVentas_FechaEnvio
        FOREIGN KEY (FechaEnvio_SK)
        REFERENCES dbo.Dim_Tiempo(Tiempo_SK)
);
GO
CREATE INDEX IX_FactVentas_Cliente ON dbo.Fact_Ventas(Cliente_SK);
GO
CREATE INDEX IX_FactVentas_Empleado ON dbo.Fact_Ventas(Empleado_SK);
GO
CREATE INDEX IX_FactVentas_Producto ON dbo.Fact_Ventas(Producto_SK);
GO
CREATE INDEX IX_FactVentas_FechaPedido ON dbo.Fact_Ventas(FechaPedido_SK);

