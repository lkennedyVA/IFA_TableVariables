USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspFiServBMOItemDailyReport]    Script Date: 2/18/2025 9:52:20 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
    Name: [common].[uspFiServBMOItemDailyReport]
    Description: This procedure reports on BMO Item activity for the date range.

    Tables: 
        [ifa].[Process]
        ,[ifa].[Item]
        ,[payer].[Payer]
        ,[customer].[CustomerIdXref]
        ,[common].[ClientAccepted]
        ,[ifa].[RuleBreakData]

    Functions: 
        [common].[ufnDownDimensionByOrgIdILTF]
        ,[common].[ufnNotEligibleAndCarveOutILTFDeux]
        ,[common].[ufnCleanNumber]

    History:
        2024-04-03 - CBS - VALID-1754: Created
        2025-02-18 - LXK - Removed table variable and replaced with local temp tables.
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFiServBMOItemDailyReport](
    @piOrgId INT,
    @pdtStartDate DATETIME2(7),
    @pdtEndDate DATETIME2(7),
    @pnvHeader NVARCHAR(4000)
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
        CAST(NULL AS NVARCHAR(25)) AS ItemRuleBreakCode,
        CAST(NULL AS NVARCHAR(25)) AS ClientResponse,
        CAST(NULL AS MONEY) AS ItemAmount,
        CAST(NULL AS NVARCHAR(1)) AS NotEligible,
        CAST(NULL AS NVARCHAR(1)) AS CarveOut,
        CAST(NULL AS NVARCHAR(1)) AS SmallItemFlag;
    RETURN;
END;

    -- Drop temp tables if they exist
    DROP TABLE IF EXISTS #FiServItemDailyReportBMO;
    DROP TABLE IF EXISTS #tblFiServDetailBMO;

    -- Create temp table for hierarchical organization data
    CREATE TABLE #FiServItemDailyReportBMO (
        LevelId INT,
        ParentId INT,
        OrgId INT PRIMARY KEY,
        OrgCode NVARCHAR(25),
        OrgName NVARCHAR(255),
        ExternalCode NVARCHAR(50),
        TypeId INT,
        [Type] NVARCHAR(50),
        StatusFlag INT,
        DateActivated DATETIME2(7),
        ChannelName NVARCHAR(50)
    );

    -- Create temp table for detailed transaction data
    CREATE TABLE #tblFiServDetailBMO (
        RowId INT IDENTITY(1,1),
        DateActivated DATETIME2(7),
        OrgId INT,
        TransactionKey NVARCHAR(25),
        ClientRequestId NVARCHAR(50),
        ClientRequestId2 NVARCHAR(50),
        CustomerIdentifier NVARCHAR(100),
        ClientItemID NVARCHAR(50),
        TransactionItemID NVARCHAR(25),
        ItemRuleBreakCode NVARCHAR(25),
        ClientResponse NVARCHAR(25),
        ItemAmount MONEY,
        NotEligible NVARCHAR(1),
        CarveOut NVARCHAR(1),
        SmallItemFlag NVARCHAR(1)
    );

    -- Declare local variables
    DECLARE @iOrgId INT = @piOrgId,
            @dtStartDate DATETIME2(7) = @pdtStartDate,
            @dtEndDate DATETIME2(7) = @pdtEndDate,
            @iOrgDimensionId INT = [common].[ufnDimension]('Organization'),
            @nvHeader NVARCHAR(4000) = @pnvHeader;

    -- Populate temporary table with organizational hierarchy data
    INSERT INTO #FiServItemDailyReportBMO (LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, ChannelName)
    SELECT 
        LevelId, ParentId, OrgId, OrgCode, OrgName, ExternalCode, TypeId, [Type], StatusFlag, DateActivated, [common].[ufnOrgChannelName](OrgId)
    FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId)
    WHERE OrgCode NOT LIKE '%Test%'
    ORDER BY ParentId, OrgId;

    -- Open the symmetric key for decryption
    OPEN SYMMETRIC KEY VALIDSYMKEY DECRYPTION BY ASYMMETRIC KEY VALIDASYMKEY;

    -- Insert data into the detail temp table
    INSERT INTO #tblFiServDetailBMO (
        DateActivated, OrgId, TransactionKey, ClientRequestId, ClientRequestId2, 
        CustomerIdentifier, ClientItemID, TransactionItemID, ItemRuleBreakCode, 
        ClientResponse, ItemAmount, NotEligible, CarveOut, SmallItemFlag
    )
    SELECT TOP 1000000 
        p.DateActivated,
        p.OrgId,
        p.ProcessKey,
        ClientRequestId,
        ClientRequestId2,
        CONVERT(NVARCHAR(100), p.CustomerId),
        i.ClientItemId,
        i.ItemKey,
        i.Rulebreak,
        ca.Code,
        i.CheckAmount,
        ISNULL(CONVERT(NVARCHAR(1), neaco.NotEligible), '1'),
        ISNULL(CONVERT(NVARCHAR(1), neaco.CarveOut), '0'),
        CONVERT(NVARCHAR(1), CASE 
            WHEN CheckAmount < 25.00 AND i.PayerId IN (
                45511602, 46749418, 57286220, 75780082, 49162868, 49162869, 49162870,
                49162871, 44140511, 72675662, 62086301, 75019594, 65055313, 56231928,
                56231929, 56208484, 60818649, 60818650, 60818651, 63767456, 72897759, 44983753
            ) 
            THEN 1 ELSE 0 END)
    FROM [ifa].[Process] p WITH (READUNCOMMITTED)
    INNER JOIN [ifa].[Item] i WITH (READUNCOMMITTED) ON p.ProcessId = i.ProcessId
    INNER JOIN [payer].[Payer] py WITH (READUNCOMMITTED) ON i.PayerId = py.PayerId
    INNER JOIN [common].[ClientAccepted] ca WITH (READUNCOMMITTED) ON i.ClientAcceptedId = ca.ClientAcceptedId
    INNER JOIN #FiServItemDailyReportBMO dol ON p.OrgId = dol.OrgId
    OUTER APPLY [common].[ufnNotEligibleAndCarveOutILTFDeux](@iOrgId, i.ItemId) neaco 
    WHERE p.DateActivated >= @dtStartDate 
      AND p.DateActivated < @dtEndDate
    ORDER BY i.ItemId;

    -- Close the symmetric key
    CLOSE SYMMETRIC KEY VALIDSYMKEY;

    -- Output final formatted result
    SELECT @nvHeader AS Txt
    UNION ALL
    SELECT Txt
    FROM (
        SELECT 
            CONVERT(NVARCHAR(27), DateActivated) + ',' +
            CONVERT(NVARCHAR(10), OrgId) + ',' +
            CONVERT(NVARCHAR(25), TransactionKey) + ',' +
            CONVERT(NVARCHAR(25), ClientRequestId) + ',' +
            CONVERT(NVARCHAR(25), ISNULL(ClientRequestId2, '')) + ',' +
            CONVERT(NVARCHAR(100), CustomerIdentifier) + ',' +
            CONVERT(NVARCHAR(50), ClientItemID) + ',' +
            CONVERT(NVARCHAR(25), TransactionItemID) + ',' +
            CONVERT(NVARCHAR(25), ItemRuleBreakCode) + ',' +
            CONVERT(NVARCHAR(25), ClientResponse) + ',' +
            CONVERT(NVARCHAR(25), ItemAmount) + ',' +
            NotEligible + ',' +
            CarveOut + ',' +
            SmallItemFlag AS Txt
        FROM #tblFiServDetailBMO
    ) a;
END;
