USE [IFA]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
    Name: [common].[uspTFBItemDailyReport]
    Created By: Chris Sharp
    Description: This procedure reports on Item activity for the date range.
    
    Tables: [ifa].[Process] 
        ,[ifa].[Item]
        ,[payer].[Payer]
        ,[common].[ClientAccepted]
        ,[common].[ProcessType]
        ,[ifa].[RuleBreakData]
        ,[customer].[Account]
        ,[customer].[CustomerIdXref]

    Functions: [common].[ufnDownDimensionByOrgIdILTF]
        ,[common].[ufnOrgClientId]
        ,[common].[ufnOnUsRoutingNumber]

    History:
        2023-08-30 - CBS - VALID-1221: Created
        2025-02-17 - LXK - Modified to replace table variable with temporary table.
*****************************************************************************************/

ALTER PROCEDURE [common].[uspTFBItemDailyReport](
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
            CAST(NULL AS MONEY) AS ItemAmount,
            CAST(NULL AS NVARCHAR(25)) AS ItemRuleBreakCode,
            CAST(NULL AS NVARCHAR(25)) AS ClientResponse,
            CAST(NULL AS NVARCHAR(5)) AS OnUs;
        RETURN;
    END;

    -- Drop temp tables if they exist
    DROP TABLE IF EXISTS #DownOrgList;
    DROP TABLE IF EXISTS #FinalResults;

    -- Create temp table for organizational hierarchy data
    CREATE TABLE #DownOrgList (
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

    -- Create temp table for final results
    CREATE TABLE #FinalResults (
        DateActivated DATETIME2(7),
        OrgId INT,
        TransactionKey NVARCHAR(25),
        ClientRequestId NVARCHAR(50),
        ClientRequestId2 NVARCHAR(50),
        CustomerIdentifier NVARCHAR(100),
        ClientItemID NVARCHAR(50),
        TransactionItemID NVARCHAR(25),
        ItemAmount MONEY,
        ItemRuleBreakCode NVARCHAR(25),
        ClientResponse NVARCHAR(25),
        OnUs NVARCHAR(5)
    );

    -- Declare local variables
    DECLARE @iOrgId INT = @piOrgId,
            @dtStartDate DATETIME2(7) = @pdtStartDate,
            @dtEndDate DATETIME2(7) = @pdtEndDate,
            @iOrgDimensionId INT = [common].[ufnDimension]('Organization'),
            @nvOrgName NVARCHAR(50);

    -- Retrieve organization name
    SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;

    -- Populate organizational hierarchy temp table
    INSERT INTO #DownOrgList (LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, ChannelName)
    SELECT 
        LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated,
        [common].[ufnOrgChannelName](OrgId)
    FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
    WHERE OrgCode NOT LIKE '%Test%'
    ORDER BY ParentId, OrgId;

    -- Retrieve default start and end dates if not provided
    IF @dtStartDate IS NULL OR @dtEndDate IS NULL
    BEGIN
        SELECT @dtStartDate = StartDate, @dtEndDate = EndDate
        FROM [common].[ufnGetReportDatesByClient](@nvOrgName);
    END;

    -- Open symmetric key for encryption
    OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;

    -- Insert into final results table
    INSERT INTO #FinalResults (DateActivated, OrgId, TransactionKey, ClientRequestId, ClientRequestId2, 
                               CustomerIdentifier, ClientItemID, TransactionItemID, ItemAmount, 
                               ItemRuleBreakCode, ClientResponse, OnUs)
    SELECT DISTINCT
        p.DateActivated AS DateActivated,
        p.OrgId AS OrgId,
        p.ProcessKey AS TransactionKey,
        ClientRequestId,
        ClientRequestId2,
        CONVERT(NVARCHAR(100), CONVERT(NVARCHAR(50), DECRYPTBYKEY(cix.IdEncrypted))) AS CustomerIdentifier,
        i.ClientItemId AS ClientItemID,
        i.ItemKey AS TransactionItemID,
        i.CheckAmount AS ItemAmount,
        i.Rulebreak AS ItemRuleBreakCode,
        ca.Code AS ClientResponse,
        CASE 
            WHEN [common].[ufnOnUsRoutingNumber]([common].[ufnOrgClientId](p.OrgId), pa.RoutingNumber) = 1 THEN 'Yes' 
            ELSE 'No' 
        END AS OnUs
    FROM [ifa].[Process] p WITH (READUNCOMMITTED)
    INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
    INNER JOIN [payer].[Payer] pa WITH (READUNCOMMITTED) ON i.PayerId = pa.PayerId
    INNER JOIN [customer].[CustomerIdXref] cix WITH (READUNCOMMITTED) ON p.CustomerId = cix.CustomerId
        AND cix.IdTypeId = 25 
        AND cix.StatusFlag = 1
    INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
    INNER JOIN [customer].[Account] a WITH (READUNCOMMITTED) ON p.AccountId = a.AccountId  
        AND p.CustomerId = a.CustomerId
        AND a.AccountTypeId = 1
    LEFT OUTER JOIN [ifa].[RuleBreakData] rbd WITH (READUNCOMMITTED) ON i.ItemId = rbd.ItemId
    CROSS APPLY #DownOrgList dol
    WHERE p.DateActivated >= @dtStartDate 
      AND p.DateActivated < @dtEndDate
      AND dol.OrgId = p.OrgId
    ORDER BY p.DateActivated, i.ClientItemId;

    -- Return explicitly defined columns
    SELECT 
        DateActivated, 
        OrgId, 
        TransactionKey, 
        ClientRequestId, 
        ClientRequestId2, 
        CustomerIdentifier, 
        ClientItemID, 
        TransactionItemID, 
        ItemAmount, 
        ItemRuleBreakCode, 
        ClientResponse, 
        OnUs
    FROM #FinalResults;

    -- Close symmetric key
    CLOSE SYMMETRIC KEY VALIDSYMKEY;
END;
