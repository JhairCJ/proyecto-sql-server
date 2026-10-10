USE NorthWind_DW;
GO

CREATE TABLE Fact_Ventas (
    Venta_SK BIGINT IDENTITY(1,1) PRIMARY KEY,

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

    -- Medidas
    Cantidad SMALLINT NOT NULL,
    PrecioUnitario MONEY NOT NULL,
    Descuento REAL NOT NULL,

    ImporteBruto DECIMAL(18,2) NOT NULL,
    ImporteDescuento DECIMAL(18,2) NOT NULL,
    ImporteNeto DECIMAL(18,2) NOT NULL,

    -- Foreign Keys
    CONSTRAINT FK_FactVentas_Cliente
        FOREIGN KEY (Cliente_SK)
        REFERENCES Dim_Cliente(Cliente_SK),

    CONSTRAINT FK_FactVentas_Empleado
        FOREIGN KEY (Empleado_SK)
        REFERENCES Dim_Empleado(Empleado_SK),

    CONSTRAINT FK_FactVentas_Producto
        FOREIGN KEY (Producto_SK)
        REFERENCES Dim_Producto(Producto_SK),

    CONSTRAINT FK_FactVentas_Transportista
        FOREIGN KEY (Transportista_SK)
        REFERENCES Dim_Transportista(Transportista_SK),

    CONSTRAINT FK_FactVentas_FechaPedido
        FOREIGN KEY (FechaPedido_SK)
        REFERENCES Dim_Tiempo(Tiempo_SK),

    CONSTRAINT FK_FactVentas_FechaRequerida
        FOREIGN KEY (FechaRequerida_SK)
        REFERENCES Dim_Tiempo(Tiempo_SK),

    CONSTRAINT FK_FactVentas_FechaEnvio
        FOREIGN KEY (FechaEnvio_SK)
        REFERENCES Dim_Tiempo(Tiempo_SK)
);
GO