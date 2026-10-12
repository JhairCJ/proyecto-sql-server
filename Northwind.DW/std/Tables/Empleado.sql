CREATE TABLE std.Empleado
(
    EmployeeID INT NOT NULL,

    FirstName NVARCHAR(10) NULL,
    LastName NVARCHAR(20) NULL,
    Title NVARCHAR(30) NULL,

    City NVARCHAR(15) NULL,
    Region NVARCHAR(15) NULL,
    Country NVARCHAR(15) NULL,

    ReportsTo INT NULL,

    SourceRowVersion BINARY(8) NULL,
    SupervisorName NVARCHAR(60) NULL,

    CONSTRAINT PK_STD_Empleado
        PRIMARY KEY (EmployeeID)
);
