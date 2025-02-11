USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspKEYItemDailyReport]
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
		2022-11-12 - LBD - Created
		2023-02-08 - LBD - Adjusted to return AccountNumber presented VALID-766
		2023-03-02 - LBD - Adjusted from 9pm to 11pm VALID-826
		2023-04-06 - LBD - Pushed to prod VALID-883 adjusted to run 10pm to 10pm
		2023-07-12 - CBS - VALID-1112: Adjusted KeyBank Logic to use GETDATE()-2 + 22:00:00
			if the report executes after midnight, else use the standard calculation
		2025-01-08 - LXK - Removed table Variable to local temp table, BMO proc written the same, implementing same change

*****************************************************************************************/
ALTER PROCEDURE [common].[uspKEYItemDailyReport](
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
            CAST(NULL AS NVARCHAR(100)) AS CustomerIdentifier,
            CAST(NULL AS NVARCHAR(50)) AS ClientItemID,
            CAST(NULL AS NVARCHAR(25)) AS TransactionItemID,
            CAST(NULL AS NVARCHAR(25)) AS ItemRuleBreak,
            CAST(NULL AS NVARCHAR(25)) AS ItemRuleBreakCode,
            CAST(NULL AS NVARCHAR(25)) AS ClientResponse,
            CAST(NULL AS MONEY) AS ItemAmount,
            CAST(NULL AS MONEY) AS Fee,
            CAST(NULL AS NVARCHAR(50)) AS CustomerAccountNumber;
        RETURN;
    END;

    -- Drop temp tables if they exist
    DROP TABLE IF EXISTS #ItemDailyReportKEY;
    DROP TABLE IF EXISTS #FinalResults;

    -- Create temp table for organization details
    CREATE TABLE #ItemDailyReportKEY (
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
        CustomerIdentifier NVARCHAR(100),
        ClientItemID NVARCHAR(50),
        TransactionItemID NVARCHAR(25),
        ItemRuleBreak NVARCHAR(25),
        ItemRuleBreakCode NVARCHAR(25),
        ClientResponse NVARCHAR(25),
        ItemAmount MONEY,
        Fee MONEY,
        CustomerAccountNumber NVARCHAR(50)
    );

    -- Declare variables
    DECLARE @iOrgId INT = @piOrgId,
            @dtStartDate DATETIME2(7) = @pdtStartDate,
            @dtEndDate DATETIME2(7) = @pdtEndDate,
            @tTime TIME,
            @iOrgDimensionId INT = [common].[ufnDimension]('Organization');

    -- Populate temp table with organization hierarchy data
    INSERT INTO #ItemDailyReportKEY(LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, ChannelName)
    SELECT LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, [common].[ufnOrgChannelName](OrgId)
    FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
    WHERE OrgCode NOT LIKE '%Test%'
    ORDER BY ParentId, OrgId;

    -- Handle default date range if not provided
    IF @dtStartDate IS NULL OR @dtEndDate IS NULL
    BEGIN
        SET @tTime = CONVERT(TIME, GETDATE());

        -- Use standard calculation (prior day 22:00 to current day 22:00)
        IF @tTime NOT BETWEEN '00:00:00.0000000' AND '08:00:00.0000000'
        BEGIN
            SET @dtStartDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 1)) + ' 22:00:00.0000000');
            SET @dtEndDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE())) + ' 22:00:00.0000000');
        END
        -- Use two days ago (22:00) to prior day (22:00)
        ELSE IF @tTime BETWEEN '00:00:00.0000000' AND '08:00:00.0000000'
        BEGIN
            SET @dtStartDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 2)) + ' 22:00:00.0000000');
            SET @dtEndDate = CONVERT(DATETIME2(7), CONVERT(NVARCHAR(20), CONVERT(DATE, GETDATE() - 1)) + ' 22:00:00.0000000');
        END
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
        CONVERT(NVARCHAR(100), CONVERT(NVARCHAR(50), DECRYPTBYKEY(cix.IdEncrypted))) AS CustomerIdentifier,
        i.ClientItemId AS ClientItemID,
        i.ItemKey AS TransactionItemID,
        i.Rulebreak AS ItemRuleBreak,
        ISNULL(rbd.Code, '') AS ItemRuleBreakCode,
        ca.Code AS ClientResponse,
        i.CheckAmount AS ItemAmount,
        i.Fee AS Fee,
        a.AccountNumber AS CustomerAccountNumber
    FROM [ifa].[Process] p WITH (READUNCOMMITTED)
    INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
    INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) ON p.CustomerId = cix.CustomerId AND cix.IdTypeId = 25 AND cix.StatusFlag = 1
    INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
    INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) ON p.AccountId = a.AccountId  AND p.CustomerId = a.CustomerId AND a.AccountTypeId = 1
    LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) ON i.ItemId = rbd.ItemId
    CROSS APPLY #ItemDailyReportKEY dol
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
    CustomerIdentifier,
    ClientItemID,
    TransactionItemID,
    ItemRuleBreak,
    ItemRuleBreakCode,
    ClientResponse,
    ItemAmount,
    Fee,
    CustomerAccountNumber
FROM #FinalResults;

END;
