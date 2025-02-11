USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFTBItemDailyReport
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[common].[ClientAccepted]
		,[common].[ProcessType]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2020-10-05 - LBD - Created
		2020-11-17 - LBD - Added ChannelName
		2020-11-25 - LBD - Only return IdTypeID 25, added rulegroupcode
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFTBItemDailyReport](
    @piOrgId INT,
    @pdtStartDate DATETIME2(7) = NULL,
    @pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    -- Metadata definition for SSIS to ensure column structure
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
            CAST(NULL AS NVARCHAR(25)) AS [Client Response],
            CAST(NULL AS NVARCHAR(50)) AS Channel,
            CAST(NULL AS NVARCHAR(50)) AS ProcessType,
            CAST(NULL AS NVARCHAR(50)) AS RuleGroupCode;
        RETURN;
    END;

    -- Drop temp tables if they exist
    DROP TABLE IF EXISTS #ItemDailyReportFTB;
    DROP TABLE IF EXISTS #FinalResults;

    -- Create temp table for organization details
    CREATE TABLE #ItemDailyReportFTB (
        LevelId INT,
        ParentId INT,
        OrgId INT,
        OrgCode NVARCHAR(25),
        OrgName NVARCHAR(255),
        ExternalCode NVARCHAR(50),
        TypeId INT,
        [Type] NVARCHAR(50),
        StatusFlag INT,
        DateActivated DATETIME2(7),
        ChannelName NVARCHAR(50)
    );

    -- Create final results temp table
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
        [Client Response] NVARCHAR(25),
        Channel NVARCHAR(50),
        ProcessType NVARCHAR(50),
        RuleGroupCode NVARCHAR(50)
    );

    -- Declare variables
    DECLARE @iOrgId INT = @piOrgId,
            @dtStartDate DATETIME2(7) = @pdtStartDate,
            @dtEndDate DATETIME2(7) = @pdtEndDate,
            @iOrgDimensionId INT = [common].[ufnDimension]('Organization');

    -- Populate temp table with organization hierarchy data
    INSERT INTO #ItemDailyReportFTB(LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, ChannelName)
    SELECT LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, [common].[ufnOrgChannelName](OrgId)
    FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
    WHERE OrgCode <> 'FTBTest'
    ORDER BY ParentId, OrgId;

    -- Handle default date range if not provided
    IF @dtStartDate IS NULL OR @dtEndDate IS NULL
    BEGIN
        SET @dtStartDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 1)) + ' 21:00:00.0000000');
        SET @dtEndDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE())) + ' 21:00:00.0000000');
    END;

    -- Open encryption key
    OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;

    -- Insert final data into #FinalResults temp table
    INSERT INTO #FinalResults
    SELECT DISTINCT 
        p.DateActivated AS DateActivated,
        p.OrgId AS OrgId,
        p.ProcessKey AS TransactionKey,
        ClientRequestId,
        ClientRequestId2,
        CONVERT(NVARCHAR(100), CONVERT(NVARCHAR(50), DECRYPTBYKEY(cix.IdEncrypted))) AS [Customer Identifier],
        i.ClientItemId AS [ClientItem ID],
        i.ItemKey AS TransactionItemID,
        i.CheckAmount AS ItemAmount,
        i.Rulebreak AS [Item Rule Break Code],
        ca.Code AS [Client Response],
        dol.ChannelName AS Channel,
        UPPER(pt.[Code]) AS ProcessType,
        CASE 
            WHEN ISNULL(rbd.Code, '0') = '0' THEN '0' 
            ELSE rbd.Code 
        END AS RuleGroupCode
    FROM [ifa].[Process] p WITH (READUNCOMMITTED)
    INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
    INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) 
        ON p.CustomerId = cix.CustomerId AND cix.IdTypeId = 25 AND cix.StatusFlag = 1
    INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
    INNER JOIN [common].[ProcessType] pt WITH (READUNCOMMITTED) ON p.ProcessTypeId = pt.ProcessTypeId
    LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) ON i.ItemId = rbd.ItemId
    CROSS APPLY #ItemDailyReportFTB dol
    WHERE p.DateActivated >= @dtStartDate 
      AND p.DateActivated < @dtEndDate
      AND dol.OrgId = p.OrgId
    ORDER BY p.DateActivated, i.ClientItemId;

    -- Close encryption key
    CLOSE SYMMETRIC KEY VALIDSYMKEY;

    -- Return final results
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
    [Client Response],
    Channel,
    ProcessType,
    RuleGroupCode
FROM #FinalResults;

END;

