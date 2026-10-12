CREATE TABLE dbo.Dim_Producto (
    Producto_SK INT IDENTITY(1,1) NOT NULL,
    ProductID INT NOT NULL,

    NombreProducto NVARCHAR(40),
    CantidadPorUnidad NVARCHAR(20),

    CategoryID INT,
    Categoria NVARCHAR(15),

    SupplierID INT,
    Proveedor NVARCHAR(40),
    PaisProveedor NVARCHAR(15),

    Descontinuado BIT,
    CONSTRAINT PK_Dim_Producto PRIMARY KEY (Producto_SK),
    CONSTRAINT UQ_Dim_Producto_ProductID UNIQUE (ProductID)
);
