USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFTBOrgItemClientAcceptedUpdate
	CreatedBy: Larry Dugger
	Description: This procedure will check and update the records whose ItemStatus 
		has remained in 'Processed' for more than the TimerMinutes setting
	Tables: [dbo].[FTBOrg]
		,[ifa].[Item]
		,[financial].[ItemActivity]
		,[retail].[ItemActivity]

	History:
		2020-12-10 - LBD - Created
		2025-01-13 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspFTBOrgItemClientAcceptedUpdate]
AS
BEGIN
	SET NOCOUNT ON;

	drop table if exists #FTBOrgItemClientAcceptedUpdate
	create table #FTBOrgItemClientAcceptedUpdate(
		ItemId int primary key
		);
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspFTBOrgItemClientAcceptedUpdate]')),1)	
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@iClientAcceptedId int = [common].[ufnClientAccepted]('Accepted') 
		,@iClientNotOffered int = [common].[ufnClientAccepted]('NotOffered') 
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(20),sysdatetime(),121),'-',''),' ',''),':',''),'.','')
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = OBJECT_NAME(@@PROCID)
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@nvMsg nvarchar(50) = N'Update Item(s): '
		,@ncMsg nchar(50) = ''
		,@iRowCount int = 0;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate = SYSDATETIME();
	END

	BEGIN TRY
		--Financial
		UPDATE ia
			SET ClientAcceptedId = @iClientAcceptedId
				,DateActivated = sysdatetime()
		OUTPUT
			inserted.ItemId
		INTO #FTBOrgItemClientAcceptedUpdate
		FROM [financial].[ItemActivity] ia
		INNER JOIN [dbo].[FTBOrg] o on ia.OrgId = o.OrgId
								AND ia.DateActivated BETWEEN DATEADD(minute,(o.TimerMinutes-2),@dtTimerDate)
															AND DATEADD(minute,o.TimerMinutes,@dtTimerDate)
		INNER JOIN [ifa].[Item] i on ia.ItemId = i.ItemId
		INNER JOIN [ifa].[Misc] m on i.ProcessId = m.ProcessId
									and m.MiscTypeId = 8
									and m.MiscInfo = '324'
		WHERE ia.ItemStatusId = @iFinalItemStatusId
			AND ia.RuleBreak = '0'
			AND ia.ClientAcceptedId = @iClientNotOffered
			AND i.Fee <> 0.0
			AND o.StatusFlag = 1
			AND @dtTimerDate BETWEEN o.DateActivated AND o.DateDeactivated;
		SET @iRowCount = @@ROWCOUNT;

		--Retail
		UPDATE ia
			SET ClientAcceptedId = @iClientAcceptedId
				,DateActivated = sysdatetime()
		OUTPUT
			inserted.ItemId
		INTO #FTBOrgItemClientAcceptedUpdate
		FROM [retail].[ItemActivity] ia
		INNER JOIN [dbo].[FTBOrg] o on ia.OrgId = o.OrgId
								AND ia.DateActivated BETWEEN DATEADD(minute,(o.TimerMinutes-2),@dtTimerDate)
																			AND DATEADD(minute,o.TimerMinutes,@dtTimerDate)
		INNER JOIN [ifa].[Item] i on ia.ItemId = i.ItemId
		INNER JOIN [ifa].[Misc] m on i.ProcessId = m.ProcessId
									and  m.MiscTypeId = 8
									and m.MiscInfo = '324'
		WHERE @iRowCount = 0  --only if financial not found
			AND ia.ItemStatusId = @iFinalItemStatusId
			AND ia.RuleBreak = '0'
			AND ia.ClientAcceptedId = @iClientNotOffered
			AND i.Fee <> 0.0
			AND o.StatusFlag = 1
			AND @dtTimerDate BETWEEN o.DateActivated AND o.DateDeactivated;
		SET @iRowCount = CASE WHEN @iRowCount = 0 THEN @@ROWCOUNT ELSE @iRowCount END;

		--NOW Item
		UPDATE i
			SET ClientAcceptedId = @iClientAcceptedId
				--,DateActivated = sysdatetime()
		FROM [ifa].[Item] i
		INNER JOIN #FTBOrgItemClientAcceptedUpdate ia on i.ItemId = ia.ItemId
		WHERE @iRowCount > 0;

		INSERT INTO [dbo].[FTBItemAdjusted](ItemId)
		SELECT ItemId
		FROM  #FTBOrgItemClientAcceptedUpdate
		WHERE @iRowCount > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Error' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
	END CATCH;

	SELECT @nvMsg = @nvMsg + CONVERT(NVARCHAR(10),ItemId) + ',' 
	FROM #FTBOrgItemClientAcceptedUpdate
	WHERE @iLogLevel > 0
		AND @iRowCount > 0;
	SET @ncMsg = SUBSTRING(@nvMsg,1,50);
	IF @iLogLevel > 0
		AND @iRowCount > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,@ncMsg,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate = SYSDATETIME();
	END

END
