CREATE PROCEDURE dbo.DW_MergeDimEmpleado
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS(SELECT 1 FROM std.Empleado WHERE EmployeeID=0)
        THROW 52408,'Empleado: identidad reservada para desconocido.',1;
    IF EXISTS
    (
        SELECT 1 FROM std.Empleado source
        WHERE source.ReportsTo IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM std.Empleado supervisor WHERE supervisor.EmployeeID=source.ReportsTo)
          AND NOT EXISTS(SELECT 1 FROM dbo.DimEmployee supervisor WHERE supervisor.EmployeeID=source.ReportsTo)
    )
        THROW 52414,'Empleado: ReportsTo no tiene empleado correspondiente.',1;

    MERGE dbo.DimEmployee WITH(HOLDLOCK) AS target
    USING std.Empleado AS source
       ON target.EmployeeID=source.EmployeeID
    WHEN MATCHED THEN UPDATE SET
        FirstName=source.FirstName,
        LastName=source.LastName,
        FullName=source.FullName,
        Title=source.Title,
        TitleOfCourtesy=source.TitleOfCourtesy,
        BirthDate=source.BirthDate,
        HireDate=source.HireDate,
        [Address]=source.[Address],
        City=source.City,
        Region=source.Region,
        Country=source.Country,
        PostalCode=source.PostalCode,
        ReportsTo=source.ReportsTo,
        SupervisorName=source.SupervisorName,
        HomePhone=source.HomePhone,
        Extension=source.Extension
    WHEN NOT MATCHED BY TARGET THEN INSERT
        (EmployeeID,FirstName,LastName,FullName,Title,TitleOfCourtesy,BirthDate,HireDate,
         [Address],City,Region,Country,PostalCode,ReportsTo,SupervisorName,HomePhone,Extension)
    VALUES
        (source.EmployeeID,source.FirstName,source.LastName,source.FullName,source.Title,
         source.TitleOfCourtesy,source.BirthDate,source.HireDate,source.[Address],source.City,
         source.Region,source.Country,source.PostalCode,source.ReportsTo,source.SupervisorName,
         source.HomePhone,source.Extension);
END;
