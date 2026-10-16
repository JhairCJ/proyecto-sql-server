CREATE PROCEDURE dbo.DW_LoadDimDate
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @StartDate IS NULL OR @EndDate IS NULL
    BEGIN
        DECLARE @MinDate DATE,@MaxDate DATE;
        SELECT @MinDate=MIN(d.FullDate),@MaxDate=MAX(d.FullDate)
        FROM std.Ventas AS s
        CROSS APPLY (VALUES(CONVERT(DATE,s.OrderDate)),
                           (CONVERT(DATE,s.RequiredDate)),
                           (CONVERT(DATE,s.ShippedDate))) AS d(FullDate);
        SET @StartDate=COALESCE(@StartDate,@MinDate);
        SET @EndDate=COALESCE(@EndDate,@MaxDate);
    END;

    IF @StartDate IS NULL OR @EndDate IS NULL OR @StartDate>@EndDate
        THROW 52110,'DimDate: indique un rango válido o cargue fechas en std.Ventas.',1;
    IF @StartDate<='19000101' AND @EndDate>='19000101'
        THROW 52111,'DimDate: 1900-01-01 está reservada para la fecha desconocida.',1;

    BEGIN TRY
        BEGIN TRANSACTION;
        ;WITH Dates AS
        (
            SELECT @StartDate AS FullDate
            UNION ALL
            SELECT DATEADD(DAY,1,FullDate) FROM Dates WHERE FullDate<@EndDate
        ),
        Numbered AS
        (
            SELECT FullDate,
                   ((DATEDIFF(DAY,CONVERT(DATE,'19000101'),FullDate)%7+7)%7) AS MondayIndex,
                   ((DATEDIFF(DAY,CONVERT(DATE,'19000101'),DATEFROMPARTS(YEAR(FullDate),1,1))%7+7)%7) AS FirstDayIndex,
                   DATEPART(DAYOFYEAR,FullDate) AS DayOfYear
            FROM Dates
        )
        INSERT dbo.DimDate
            (DateKey,FullDate,DayNumber,DayName,MonthNumber,MonthName,
             QuarterNumber,YearNumber,WeekNumber,IsWeekend,IsUnknown)
        SELECT YEAR(n.FullDate)*10000+MONTH(n.FullDate)*100+DAY(n.FullDate),
               n.FullDate,DAY(n.FullDate),
               CHOOSE(n.MondayIndex+1,N'Lunes',N'Martes',N'Miércoles',N'Jueves',
                      N'Viernes',N'Sábado',N'Domingo'),
               MONTH(n.FullDate),
               CHOOSE(MONTH(n.FullDate),N'Enero',N'Febrero',N'Marzo',N'Abril',
                      N'Mayo',N'Junio',N'Julio',N'Agosto',N'Septiembre',
                      N'Octubre',N'Noviembre',N'Diciembre'),
               DATEPART(QUARTER,n.FullDate),YEAR(n.FullDate),
               CONVERT(TINYINT,((n.DayOfYear-1+n.FirstDayIndex)/7)+1),
               CONVERT(BIT,CASE WHEN n.MondayIndex IN(5,6) THEN 1 ELSE 0 END),0
        FROM Numbered AS n
        WHERE NOT EXISTS
            (SELECT 1 FROM dbo.DimDate AS existing WITH(UPDLOCK,HOLDLOCK)
             WHERE existing.FullDate=n.FullDate)
        OPTION(MAXRECURSION 0);
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
