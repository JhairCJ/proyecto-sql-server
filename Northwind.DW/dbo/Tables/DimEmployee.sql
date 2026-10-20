CREATE TABLE dbo.DimEmployee
(
    EmployeeKey INT IDENTITY(1,1) NOT NULL,
    EmployeeID INT NOT NULL,
    FirstName NVARCHAR(10) NOT NULL,
    LastName NVARCHAR(20) NOT NULL,
    FullName NVARCHAR(60) NOT NULL,
    Title NVARCHAR(30) NULL,
    TitleOfCourtesy NVARCHAR(25) NULL,
    BirthDate DATE NULL,
    HireDate DATE NULL,
    [Address] NVARCHAR(60) NULL,
    City NVARCHAR(15) NULL,
    Region NVARCHAR(15) NULL,
    Country NVARCHAR(15) NULL,
    PostalCode NVARCHAR(10) NULL,
    ReportsTo INT NULL,
    SupervisorName NVARCHAR(60) NULL,
    HomePhone NVARCHAR(24) NULL,
    Extension NVARCHAR(4) NULL,
    CONSTRAINT PK_DimEmployee PRIMARY KEY (EmployeeKey),
    CONSTRAINT UQ_DimEmployee_EmployeeID UNIQUE (EmployeeID)
);
