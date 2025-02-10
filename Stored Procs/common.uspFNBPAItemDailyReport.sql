USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspFNBPAItemDailyReport]    Script Date: 2/10/2025 8:18:54 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFNBPAItemDailyReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2021-09-20 - LBD - Created CCF2676
		2022-05-26 - CBS - VALID:255 - Replace Item.Amount with Item.CheckAmount
		2025-01-08 - LXK - Removed table Variable to local temp table:
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFNBPAItemDailyReport](
    @piOrgId INT = 172436,
    @pdtStartDate DATETIME2(7) = NULL,
    @pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

IF 1 = 0
BEGIN
    SELECT 
        CAST(NULL AS DATETIME2(7)) AS DateActivated,
        CAST(NULL AS INT) AS OrgId,
        CAST(NULL AS NVARCHAR(25)) AS TransactionKey,
        CAST(NULL AS NVARCHAR(50)) AS ClientRequestId,
        CAST(NULL AS NVARCHAR(50)) AS ClientRequestId2,
        CAST(NULL AS NVARCHAR(100)) AS [Customer Identifier],
        CAST(NULL AS NVARCHAR(50)) AS [ClientItem ID],
        CAST(NULL AS NVARCHAR(25)) AS TransactionItemID,
        CAST(NULL AS MONEY) AS ItemAmount,
        CAST(NULL AS NVARCHAR(25)) AS [Item Rule Break Code],
        CAST(NULL AS NVARCHAR(25)) AS [Client Response];
    RETURN;
END;

        DROP TABLE IF EXISTS #ItemDailyReportFNBPA;

    CREATE TABLE #ItemDailyReportFNBPA (
        LevelId INT,
        ParentId INT,
        OrgId INT,
        OrgCode NVARCHAR(25),
        OrgName NVARCHAR(255),
        ExternalCode NVARCHAR(50),
        TypeId INT,
        [Type] NVARCHAR(50),
        StatusFlag INT,
        DateActivated DATETIME2(7)
    );

CREATE TABLE #FinalResults (
    DateActivated DATETIME2(7),
    OrgId INT,
    TransactionKey NVARCHAR(25),
    ClientRequestId NVARCHAR(50),
    ClientRequestId2 NVARCHAR(50),
    [Customer Identifier] NVARCHAR(100),
    [ClientItem ID] NVARCHAR(50),
    TransactionItemID NVARCHAR(25),
    ItemAmount MONEY,
    [Item Rule Break Code] NVARCHAR(25),
    [Client Response] NVARCHAR(25)
);

    DECLARE @iOrgId INT = @piOrgId,
            @dtStartDate DATETIME2(7) = @pdtStartDate,
            @dtEndDate DATETIME2(7) = @pdtEndDate,
            @iOrgDimensionId INT = [common].[ufnDimension]('Organization');

    -- Populate the local temporary table
    INSERT INTO #ItemDailyReportFNBPA (LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated)
    SELECT 
        LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated
    FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
    WHERE OrgCode <> 'FNBTest'
    ORDER BY ParentId, OrgId;

    -- Handle default date range if not provided
    IF @dtStartDate IS NULL OR @dtEndDate IS NULL
    BEGIN
        SET @dtStartDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 1)) + ' 21:00:00.0000000');
        SET @dtEndDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE())) + ' 21:00:00.0000000');
    END;

    -- Open the symmetric key for decryption
    OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;

-- Insert data into the final results temp table
INSERT INTO #FinalResults (DateActivated, OrgId, TransactionKey, ClientRequestId, ClientRequestId2, 
    [Customer Identifier], [ClientItem ID], TransactionItemID, ItemAmount, [Item Rule Break Code], [Client Response])

    SELECT 
        p.DateActivated AS 'DateActivated',
        p.OrgId AS 'OrgId',
        p.ProcessKey AS 'TransactionKey',
        ClientRequestId,
        ClientRequestId2,
        CONVERT(NVARCHAR(100), CONVERT(NVARCHAR(50), DECRYPTBYKEY(cix.IdEncrypted))) AS 'Customer Identifier',
        i.ClientItemId AS 'ClientItem ID',
        i.ItemKey AS 'TransactionItemID',
        i.CheckAmount AS 'ItemAmount', --2022-05-26
        i.Rulebreak AS 'Item Rule Break Code',
        ca.Code AS 'Client Response'
    FROM [ifa].[Process] p WITH (READUNCOMMITTED)
    INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
    INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
    INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) ON p.CustomerId = cix.CustomerId
    INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
    LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) ON i.ItemId = rbd.ItemId
    CROSS APPLY #ItemDailyReportFNBPA dol
    WHERE p.DateActivated >= @dtStartDate
      AND p.DateActivated < @dtEndDate
      AND cix.IdTypeId = 25
      AND dol.OrgId = p.OrgId;

-- Return results
SELECT
    DateActivated,
    OrgId,
    TransactionKey,
    ClientRequestId,
    ClientRequestId2,
    [Customer Identifier],
    [ClientItem ID],
    TransactionItemID,
    ItemAmount,
    [Item Rule Break Code],
    [Client Response]
FROM #FinalResults;

    -- Close the symmetric key
    CLOSE SYMMETRIC KEY VALIDSYMKEY;
END;
