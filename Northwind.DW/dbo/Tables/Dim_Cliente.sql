CREATE TABLE dbo.Dim_Cliente (
    Cliente_SK INT IDENTITY(1,1) NOT NULL,
    CustomerID NCHAR(5) NOT NULL,

    NombreEmpresa NVARCHAR(40),
    NombreContacto NVARCHAR(30),
    TituloContacto NVARCHAR(30),

    Ciudad NVARCHAR(15),
    Region NVARCHAR(15),
    CodigoPostal NVARCHAR(10),
    Pais NVARCHAR(15),
    CONSTRAINT PK_Dim_Cliente PRIMARY KEY (Cliente_SK),
    CONSTRAINT UQ_Dim_Cliente_CustomerID UNIQUE (CustomerID)
);
