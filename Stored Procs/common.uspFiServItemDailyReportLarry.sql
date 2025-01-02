USE [IFA]
GO
/****** Object:  StoredProcedure [common].[uspFiServItemDailyReportLarry]    Script Date: 1/2/2025 8:42:17 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFiServItemDailyReportLarry
	CreatedBy: Larry Dugger
	Description: This procedure reports on Item activity for the date range.

	Tables: [ifa].[Process] p
		,[ifa].[Item]
		,[payer].[Payer]
		,[customer].[CustomerIdXref]
		,[common].[ClientAccepted]
		,[ifa].[RuleBreakData]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]
		,[common].[ufnNotEligibleAndCarveOutILTFDeux]
		,[common].[ufnCleanNumber]

	History:
		2017-02-08 - LBD - Recreated using [common].[uspFiServItemDailyReport], that 
		was renamed to [common].[uspFiServItemDailyReportOrginal] 
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspFiServItemDailyReportLarry](
	 @piOrgId INT
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DownOrgList table(
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

	DECLARE @iOrgId int = @piOrgId
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@nvOrgName nvarchar(50)
		,@nvHeader nvarchar(4000) = N'DateActivated,OrgId,TransactionKey,ClientRequestId,ClientRequestId2,Customer Identifier,ClientItem ID,TransactionItemID,Item Rule Break Code,Client Response,Check Amount,NotEligible,CarveOut,Demo';

	SELECT @nvOrgName = [Name] FROM [organization].[Org] WHERE OrgId = @iOrgId;

	SET @nvHeader = @nvHeader +
			CASE WHEN @nvOrgName = 'PNC Bank' THEN N',Channel'
				WHEN @nvOrgName = 'FTB Bank' THEN N',Channel,ProcessType,AccountTypeCode,Express,AccountType'
				ELSE ''
			END;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 21:00:00.0000000')
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 21:00:00.0000000')
	END

	IF @nvOrgName = 'PNC Bank'
		EXECUTE [common].[uspFiServPNCItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'TD Bank'
		EXECUTE [common].[uspFiServTDBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'MTB Bank'
		EXECUTE [common].[uspFiServMTBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'FTB Bank'
		EXECUTE [common].[uspFiServFTBItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;
	ELSE IF @nvOrgName = N'FNBPA Bank'
		EXECUTE [common].[uspFiServFNBPAItemDailyReport] @piOrgId = @iOrgId, @pdtStartDate = @dtStartDate, @pdtEndDate = @dtEndDate, @pnvHeader = @nvHeader;

END
