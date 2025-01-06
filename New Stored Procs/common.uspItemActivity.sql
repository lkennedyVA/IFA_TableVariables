USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****************************************************************************************
	Name: uspItemActivity
	CreatedBy: Larry Dugger
	Descr: This procedure will email when the activity count for Channel
		for the time period supplied (@piMinutesback)

	Tables: [ifa].[Item]
		,[ifa].[Process]

	Functions: [common].[ufnDownDimensionByOrgIdILTF]

	History:
		2018-08-13 - LBD - Created
		2018-08-22 - LBD_ Modified, corrected @iItemCnt 'If'
		2019-08-22 - MWW - Modified to Email for a specific time then Text
*****************************************************************************************/
ALTER PROCEDURE [common].[uspItemActivity](
------DECLARE
	 @piMinutesBack INT = 30
	,@piEmailOnly   INT = 30
	,@piOrgClientId INT	= 100009
	,@pnvRecipientsEmail NVARCHAR(100)	= 'Brisk.alert@validsystems.net'  -- Changed to EMail - MWW 2019-08-22
	,@pnvRecipientsSMS NVARCHAR(100)	= 'brisk.support.sms@validsystems.net' -- Added SMS variable - MWW 2019-08-22
	,@pnvChannel NVARCHAR(25) = 'Mobile'
)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @tblDownOrgList table (OrgId int primary key, OrgName nvarchar(50));

	DECLARE @iOrgClientId int = @piOrgClientId
		,@nvOrgClientName nvarchar(50)
		,@iOrgDimension int = [common].[ufnDimension]('Organization')
		,@iChannelDimension int = [common].[ufnDimension]('Channel')
		,@iItemCnt int = 0
		,@dtStart datetime2(7)
		,@dtEnd datetime2(7) = sysdatetime()
		,@nvProfileName nvarchar(128) = 'SSDB-PRDTRX01'
		,@nvBody nvarchar(255) 
		,@nvSubject nvarchar(255)
		,@iMinutesBack int = (@piMinutesBack)*-1
		,@SMSDelayMinutes int
		,@SendEmail bit
		,@instancename nvarchar(256)
		,@MonitorSQL nvarchar(256) = '[IFA].[common].[uspItemActivity]';

	SET @instancename = CONVERT(NVARCHAR(256),SERVERPROPERTY('ServerName'))

	--Load all orgs tied to @piOrgClientId
	INSERT INTO @tblDownOrgList(OrgId,OrgName)
	SELECT udd.OrgId, OrgName
	FROM [common].[ufnDownDimensionByOrgIdILTF](@piOrgClientId,@iOrgDimension) udd
	INNER JOIN [organization].[OrgXref] ox on udd.OrgId = ox.OrgChildId
										AND ox.DimensionId = @iChannelDimension
	INNER JOIN [organization].[Org] o on ox.OrgParentId = o.OrgId
	WHERE o.[Name] = @pnvChannel
		and udd.OrgId <> @piOrgClientId

	--Set the client Name
	SELECT @nvOrgClientName = [Name]
	FROM [organization].[Org]
	WHERE OrgId = @piOrgClientId;
	
	SET @nvBody = 'No '+@nvOrgClientName+' '+@pnvChannel+' Transaction Processed within last YY minutes @'+ CONVERT(NVARCHAR(16),@dtEnd);
	SET @nvSubject = @nvOrgClientName++' '+@pnvChannel+' Transaction Activity Suspect (uspItemActivity)';

	SET @dtStart = dateadd(minute,@iMinutesBack,@dtEnd);

	SELECT @iItemCnt = SUM(p.ItemCount)
	FROM @tblDownOrgList dol 
	LEFT OUTER JOIN [ifa].[Process] p on dol.OrgId = p.OrgId
	WHERE p.DateActivated between @dtStart and @dtEnd;


	IF ISNULL(@iItemCnt,0) = 0
	BEGIN;

		INSERT INTO [DBA].[common].[MonitorLogging]
				   ([InstanceName], [OrgClientId], [MonitorName], [MLDatetime], [SMSDelayMinutes], [MonitorSQL])
		SELECT @instancename, @piOrgClientId, @pnvChannel, getdate(), @piEmailOnly, @MonitorSQL;

		SET @SMSDelayMinutes = (SELECT TOP 1 SMSDelayMinutes FROM [DBA].[common].[MonitorLogging] 
		                         WHERE [OrgClientId] = @piOrgClientId AND [MonitorName] = @pnvChannel 
								 ORDER BY MLID DESC  )

		--Email for a pre-determined time frame - MWW 2019-08-22
		  IF (SELECT DATEDIFF(minute,MIN(MLDatetime),MAX(MLDatetime)) FROM  [DBA].[common].[MonitorLogging]
		       WHERE [OrgClientId] = @piOrgClientId AND [MonitorName] = @pnvChannel) < @SMSDelayMinutes
			  BEGIN;
				SET @nvBody = REPLACE(@nvBody,'YY',CONVERT(nvarchar(10),ABS(@iMinutesBack)));
				EXEC msdb.dbo.sp_send_dbmail
					@profile_name = @nvProfileName,
					@recipients = @pnvRecipientsEmail,
					@body = @nvBody,
					@subject = @nvSubject;
			  END

		--Text after the pre-determined has expired - MWW 2019-08-22
		  IF (SELECT DATEDIFF(minute,MIN(MLDatetime),MAX(MLDatetime)) FROM  [DBA].[common].[MonitorLogging]
		       WHERE [OrgClientId] = @piOrgClientId AND [MonitorName] = @pnvChannel) >= @SMSDelayMinutes
			  BEGIN;
				SET @nvBody = REPLACE(@nvBody,'YY',CONVERT(nvarchar(10),ABS(@iMinutesBack)));
				EXEC msdb.dbo.sp_send_dbmail
					@profile_name = @nvProfileName,
					@recipients = @pnvRecipientsSMS,
					@body = @nvBody,
					@subject = @nvSubject;
			  END

	END
	ELSE
	BEGIN; -- Clean up table that is keeping up with the negative polling - MWW 2019-08-22
	  DELETE [DBA].[common].[MonitorLogging] WHERE [OrgClientId] = @piOrgClientId AND [MonitorName] = @pnvChannel;
	  PRINT 'Transactions are Flowing'
	END


END
