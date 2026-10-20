CREATE PROCEDURE [dbo].[GetEmployeeChangesByRowVersion]
    @startRow BIGINT,
    @endRow BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    IF @startRow IS NULL OR @endRow IS NULL OR @startRow < 0 OR @endRow < @startRow
        THROW 51104, 'Intervalo invalido: requiere 0 <= inicio <= fin y valores no nulos.', 1;
    DECLARE @start BINARY(8), @end BINARY(8);
    EXEC dbo.BigIntToRowVersion @startRow, @start OUTPUT;
    EXEC dbo.BigIntToRowVersion @endRow, @end OUTPUT;

    SELECT e.EmployeeID, e.FirstName, e.LastName,
           CONVERT(NVARCHAR(60), CONCAT(e.FirstName, N' ', e.LastName)) AS FullName,
           e.Title, e.TitleOfCourtesy,
           CONVERT(DATE, e.BirthDate) AS BirthDate,
           CONVERT(DATE, e.HireDate) AS HireDate,
           e.[Address], e.City, e.Region, e.Country, e.PostalCode,
           e.HomePhone, e.Extension, e.ReportsTo,
           CONVERT(BINARY(8), e.[rowversion]) AS SourceRowVersion,
           CASE WHEN s.EmployeeID IS NULL THEN CONVERT(NVARCHAR(60), NULL)
                ELSE CONVERT(NVARCHAR(60), CONCAT(s.FirstName, N' ', s.LastName)) END AS SupervisorName
    FROM dbo.Employees AS e
    LEFT JOIN dbo.Employees AS s ON s.EmployeeID = e.ReportsTo
    WHERE e.[rowversion] <= @end
      AND (s.EmployeeID IS NULL OR s.[rowversion] <= @end)
      AND (e.[rowversion] > @start OR s.[rowversion] > @start);
END;
