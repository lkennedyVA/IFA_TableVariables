USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspVaeActivity
	CreatedBy: Larry Dugger
	Descr: This procedure will email when the activity count for Channel
		for the time period supplied (@piMinutesback)

	Tables: [organization].[Org]
		,[riskprocessingflow].[BriskConfig] 
		,[riskprocessingflow].[OrgVaeModelXref]
		,[ValidBankLogging].[dbo].[TransactionPluginLog]

	Functions: [common].[ufnDownOrgListByOrgIdILTF]

	History:
		2019-01-31 - LBD - Created
		2025-01-08 - LXK - Removed tTable Variables
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspVaeActivity](
	 @piMinutesBack INT = 30
	,@piOrgClientId INT	= 100009
	,@pnvRecipients NVARCHAR(100) = 'brisk.support.sms@validsystems.net'
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ActivityVAE
	CREATE TABLE #ActivityVAE(
		OrgId int primary key, 
		OrgName nvarchar(50)
		);

	DECLARE @iOrgClientId int = @piOrgClientId
		,@nvOrgClientName nvarchar(50)
		,@dtStart datetime2(7)
		,@dtEnd datetime2(7) = sysdatetime()
		,@nvProfileName nvarchar(128) = 'SSDB-PRDTRX01'
		,@nvBody nvarchar(255) 
		,@nvSubject nvarchar(255)
		,@iMinutesBack int = (@piMinutesBack)*-1;

	--Set the client Name
	SELECT @nvOrgClientName = [Name]
	FROM [organization].[Org]
	WHERE OrgId = @iOrgClientId;
	
	INSERT INTO #ActivityVAE(OrgId,OrgName)
	SELECT OrgId, OrgName
	FROM [common].[ufnDownOrgListByOrgIdILTF](@iOrgClientId);

	SET @dtStart = dateadd(minute,@iMinutesBack,@dtEnd);

	--Set the client Name
	SELECT @nvOrgClientName = [Name]
	FROM [organization].[Org]
	WHERE OrgId = @iOrgClientId;
	
	SET @nvBody = 'No '+@nvOrgClientName+' Vae Processed within last YY minutes @'+ CONVERT(NVARCHAR(16),@dtEnd);
	SET @nvSubject = @nvOrgClientName+ ' Vae Activity Suspect (uspVaeActivity)';

	IF EXISTS (SELECT 'X' FROM [riskprocessingflow].[BriskConfig] 
				WHERE KeyName = 'GuvnahBriskEnabled' 
					AND ValueName = 'true')
		AND EXISTS (SELECT 'X' FROM [riskprocessingflow].[OrgVaeModelXref] ovmx
					INNER JOIN #ActivityVAE dol on ovmx.OrgId = dol.OrgId
					WHERE ovmx.StatusFlag = 1)
		AND NOT EXISTS (SELECT 'X'FROM [ValidBankLogging].[dbo].[TransactionPluginLog] tpl
						INNER JOIN #ActivityVAE dol on tpl.OrgId = dol.OrgId
						WHERE tpl.InfoDesc = 'VaeBriskResponse'
							AND DATEDIFF(MINUTE,tpl.DateSubmitted,@dtStart) > ABS(@iMinutesBack)
						)
	BEGIN
		SET @nvBody = REPLACE(@nvBody,'YY',CONVERT(nvarchar(10),ABS(@iMinutesBack)));

		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = @nvProfileName,
			@recipients = @pnvRecipients,
			@body = @nvBody,
			@subject = @nvSubject;
	END
END
