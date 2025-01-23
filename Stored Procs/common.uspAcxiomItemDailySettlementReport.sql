USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: [common].[uspAcxiomItemDailySettlementReport]
	CreatedBy: Larry Dugger
	Description: This procedure reports on D2C activity for the date range.

	Tables: [d2c].[Item] 

	Functions: 

	History:
		2022-05-04 - LBD - Created
			uncomment this line located below on line 61
				WHERE OrgCode not like '%Test%'  
			before pushing to UAT
		2025-01-09 - LXK - Replaced table variable with local temp table
*****************************************************************************************/
ALTER PROCEDURE [common].[uspAcxiomItemDailySettlementReport](
	 @piOrgId INT 
	,@pdtStartDate DATETIME2(7) = NULL
	,@pdtEndDate DATETIME2(7) = NULL
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #DownOrgListACX;
	create table #DownOrgListACX(
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
		,@ncCreateDate nchar(8) = REPLACE(CONVERT(nvarchar(25),GETDATE(),102),'.','') --YYYYMMDD
		,@dtStartDate datetime2(7) = @pdtStartDate
		,@dtEndDate datetime2(7) = @pdtEndDate
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@ncRecType nchar(1) = 'H'			--D detail, H header
		,@ncDelimiter nchar(1) = '|'		--pipe is used for Acxiom
		--,@nvVendorId nvarchar(4) = N'49'	--Acxiom supplied default Vendor Id
		--,@nvServiceId nvarchar(4) = N'05'	--Acxiom supplied default Sevice Id
		--,@nvActionCode nvarchar(2) = N'07'	--Acxiom supplied default Action Code
		--,@nvPurchaseQty nvarchar(3) = N'1'	--Acxiom supplied default Purchase Qty
		--,@nvCountryCode nvarchar(2) = N'US'	--Acxiom supplied default Country Code
		,@iRowCnt int						--Number of D2C records
		,@mFileAmt money					--sum of all Face Amt (CheckAmount)
		,@nvHeader nvarchar(4000) = N''		--built using detail info;

	INSERT INTO #DownOrgListACX(LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,ChannelName)
	SELECT LevelId,ParentId,OrgId,OrgCode,OrgName,ExternalCode,TypeId,[Type],StatusFlag,DateActivated,[common].[ufnOrgChannelName](OrgId)
	FROM [common].[ufnDownDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId)
	--WHERE OrgCode not like '%Test%'  Restore before pushing to UAT
	ORDER BY ParentId, OrgId;

	IF ISNULL(@dtStartDate,'') = ''
	BEGIN
		SET @dtStartDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE()-1)) + ' 00:00:00.0000000')
		SET @dtEndDate = CONVERT(DATETIME2(7),CONVERT(NVARCHAR(20),CONVERT(DATE,GETDATE())) + ' 00:00:00.0000000')
	END

	SELECT @nvHeader = @ncRecType + @ncDelimiter +		--Header 
		CONVERT(nvarchar(9), COUNT(1)) + @ncDelimiter +
		CONVERT(nvarchar(13), ISNULL(SUM(vw.FaceAmt),0.00)) + @ncDelimiter +
		@ncCreateDate 
	FROM [common].[vwAcxiomItemDailySettlementDetail] vw
	INNER JOIN #DownOrgListACX dol ON vw.D2COrgId = dol.OrgId
	WHERE DateCommitted >= @dtStartDate 
		AND DateCommitted < @dtEndDate

	SELECT CAST(@nvHeader AS NVARCHAR(4000)) AS Txt
	UNION ALL
	SELECT Txt
	FROM (SELECT TOP 1000000 Txt1 +	--@ncDelimiter +
		dol.ExternalCode +			--@ncDelimiter +
		Txt2 as Txt									
	FROM [common].[vwAcxiomItemDailySettlementDetail] vw
	INNER JOIN #DownOrgListACX dol ON vw.D2COrgId = dol.OrgId
	WHERE vw.DateCommitted >= @dtStartDate 
		AND vw.DateCommitted < @dtEndDate
	ORDER BY vw.DateCommitted) a

END
