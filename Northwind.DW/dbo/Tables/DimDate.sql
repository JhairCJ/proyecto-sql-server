CREATE TABLE dbo.DimDate
(
    DateKey INT NOT NULL,
    FullDate DATE NOT NULL,
    DayNumber TINYINT NOT NULL,
    DayName NVARCHAR(20) NOT NULL,
    MonthNumber TINYINT NOT NULL,
    MonthName NVARCHAR(20) NOT NULL,
    QuarterNumber TINYINT NOT NULL,
    YearNumber SMALLINT NOT NULL,
    WeekNumber TINYINT NULL,
    IsWeekend BIT NULL,
    IsUnknown BIT NOT NULL CONSTRAINT DF_DimDate_IsUnknown DEFAULT (0),
    CONSTRAINT PK_DimDate PRIMARY KEY (DateKey),
    CONSTRAINT UQ_DimDate_FullDate UNIQUE (FullDate),
    CONSTRAINT CK_DimDate_Key CHECK
        ((IsUnknown=1 AND DateKey=0) OR
         (IsUnknown=0 AND DateKey=YEAR(FullDate)*10000+MONTH(FullDate)*100+DAY(FullDate))),
    CONSTRAINT CK_DimDate_Week CHECK (WeekNumber IS NULL OR WeekNumber BETWEEN 1 AND 53)
);
