USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspFiServItemDailyReport]
	Created By: Larry Dugger
	Description: This procedure reports on Indicated Client Item activity for the date range.

	Tables: [organization].[Org]

	Procedures: [common].[uspFiServPNCItemDailyReport]
		,[common].[uspFiServTDBItemDailyReport]
		,[common].[uspFiServMTBItemDailyReport]
		,[common].[uspFiServFTBItemDailyReport]
		,[common].[uspFiServFNBPAItemDailyReport]
		,[common].[uspFiServKEYItemDailyReport]
		,[common].[uspFiServTFBItemDailyReport]
		,[common].[uspFiServBMOItemDailyReport]
		,[common].[uspFiServCMBItemDailyReport]

	History:
		2017-02-08 - LBD - Recreated using [common].[uspFiServItemDailyReport], that 
			was renamed to [common].[uspFiServItemDailyReportOrginal] 
		2023-04-18 - LBD - Added KEY to the mix VALID-898
		2023-07-12 - CBS - VALID-1112: Adjusted KeyBank Logic to use GETDATE()-2 + 22:00:00
			if the report executes after midnight, else use the standard calculation
		2023-07-21 - CBS - VALID-1136: This was impacted by VALID-1112. A section of code that 
			was erroneous prior to setting KEY’s date if the report runs after midnight is no 
			longer erroneous.
		2023-08-30 - CBS - VALID-1221: Added support for TFB, replaced hardcoded KeyBank 
			reporting date logic with [common].[ufnGetReportDatesByClient](@pnvOrgName)
		2024-04-03 - CBS - VALID-1754: Added support for BMO
		2024-10-16 - CBS - VALID-2137: Added support for CMB
		2024-12-02 - CBS - VALID-2231: Added RtlaScore for CMB header
		2025-01-08 - LXK - Updated this proc to match the other for consistency
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFiServItemDailyReport](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	/*Testing*/
--declare @piOrgId INT = 180467
--	,@pdtStartDate DATETIME2(7) = '2025-02-19 00:00:00.0000000'
--	,@pdtEndDate DATETIME2(7) = '2025-02-20 00:00:00.0000000'

	drop table if exists #FiServItemDailyReport
	drop table if exists #tblFiServDetail
	CREATE TABLE #FiServItemDailyReport(
		 LevelId int
		,ParentId int
		,OrgId int
		,OrgCode nvarchar(25)
		,OrgName nvarchar(255)
		,ExternalCode nvarchar(50)
		,TypeId int
		,[Type] nvarchar(50)
		,StatusFlag int
		,DateActivated datetime2(7)
		,ChannelName nvarchar(50)
	);

CREATE TABLE #tblFiServDetail (
    Txt NVARCHAR(MAX)
);


	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@nvOrgName nvarchar(50)
		,@nvHeader nvarchar(4000) = N'DateActivated,OrgId,TransactionKey,ClientRequestId,ClientRequestId2,Customer Identifier,ClientItem ID,TransactionItemID,Item Rule Break Code,Client Response,Check Amount,NotEligible,CarveOut,Demo';

	SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;

	SET @nvHeader = @nvHeader +
			CASE WHEN @nvOrgName = 'PNC Bank' THEN N',Channel'
				WHEN @nvOrgName = 'FTB Bank' THEN N',Channel,ProcessType,AccountTypeCode,Express,AccountType'
				WHEN @nvOrgName = 'Truist Client' THEN N',OnUs' --2023-08-30
				WHEN @nvOrgName = 'Commerce Bank' THEN N',RtlaScore' --2024-12-02
				ELSE ''
			END;

	--2023-08-30 Adding this so we have a single place where the Start and End Dates are kept
	IF ISNULL(@dtStartDate,'') = ''
		SELECT @dtStartDate = StartDate
			,@dtEndDate = EndDate
		FROM [common].[ufnGetReportDatesByClient](@nvOrgName);

	IF @nvOrgName = N'PNC Bank'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServPNCItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'TD Bank'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServTDBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'MTB Bank'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServMTBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'FTB Bank'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServFTBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'FNBPA Bank'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServFNBPAItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'KeyBank Client'
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServKEYItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'Truist Client' --2023-08-30
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServTFBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader; 
	ELSE IF @nvOrgName = N'BMO Harris Client' --2024-04-03
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServBMOItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader; 
	ELSE IF @nvOrgName = N'Commerce Bank' --2024-10-16
		INSERT INTO #tblFiServDetail (Txt)
		EXECUTE [common].[uspFiServCMBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader; 
	--ELSE IF Add new client here 


--Output for SSIS Package
IF @piOrgId IN (181434, 163769, 180467, 172436, 179612, 100008, 100009, 100010, 179912) 
BEGIN
    SELECT Txt FROM #tblFiServDetail ORDER BY Txt DESC;
END
ELSE 
BEGIN
    SELECT @nvHeader AS Txt
    UNION ALL
    SELECT Txt FROM #tblFiServDetail;
END

END
