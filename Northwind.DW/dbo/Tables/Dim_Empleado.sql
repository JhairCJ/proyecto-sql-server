CREATE TABLE dbo.Dim_Empleado (
    Empleado_SK INT IDENTITY(1,1) NOT NULL,
    EmployeeID INT NOT NULL,

    NombreCompleto NVARCHAR(60),
    Titulo NVARCHAR(30),

    Ciudad NVARCHAR(15),
    Region NVARCHAR(15),
    Pais NVARCHAR(15),

    ReportsTo INT,
    NombreSupervisor NVARCHAR(60),
    CONSTRAINT PK_Dim_Empleado PRIMARY KEY (Empleado_SK),
    CONSTRAINT UQ_Dim_Empleado_EmployeeID UNIQUE (EmployeeID)
);
