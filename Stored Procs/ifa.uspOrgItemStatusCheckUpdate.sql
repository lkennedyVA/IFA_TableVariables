USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgItemStatusCheckUpdate
	CreatedBy: Larry Dugger
	Description: This procedure will check and update the records whose ItemStatus 
		has remained in 'Processed' for more than the TimerMinutes setting
	Tables: [organization].[OrgItemStatusTimerXref]
		,[ifa].[Item]
		,[financial].[ItemActivity]
		,[retail].[ItemActivity]

	History:
		2019-05-16 - LBD - Created
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspOrgItemStatusCheckUpdate]
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #OrgItemStatusCheckUpdateActivity
	create table #OrgItemStatusCheckUpdateActivity table (
		ItemId int primary key
		);
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspOrgItemStatusCheckUpdate]')),1)	
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@iInitialItemStatusId int = [common].[ufnItemStatus]('Initial') 
		,@iProcessedItemStatusId int = [common].[ufnItemStatus]('Processed') 
		,@ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(20),sysdatetime(),121),'-',''),' ',''),':',''),'.','')
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'ifa'
		,@ncSchemaName nchar(20) = N'ifa'
		,@ncObjectName nchar(50) = N'uspOrgItemStatusCheckUpdate'
		,@nvMsg nvarchar(50) = N'Update Item(s): '
		,@ncMsg nchar(50) = ''
		,@iRowCount int = 0;

	BEGIN TRY
		--Financial
		UPDATE ia
			SET ItemStatusId = @iInitialItemStatusId
				,DateActivated = sysdatetime()
		OUTPUT
			inserted.ItemId
		INTO #OrgItemStatusCheckUpdateActivity
		FROM [financial].[ItemActivity] ia
		INNER JOIN [organization].[OrgItemStatusTimerXref] oistx ON ia.OrgId = oistx.OrgId
																AND ia.DateActivated BETWEEN DATEADD(minute,(oistx.TimerMinutes-2),@dtTimerDate)
																						AND DATEADD(minute,oistx.TimerMinutes,@dtTimerDate)
		WHERE ia.ItemStatusId = @iProcessedItemStatusId
			AND oistx.StatusFlag = 1
			AND oistx.DateActivated < @dtTimerDate;
		SET @iRowCount = @@ROWCOUNT;
		--Retail
		UPDATE ia
			SET ItemStatusId = @iInitialItemStatusId
				,DateActivated = sysdatetime()
		OUTPUT
			inserted.ItemId
		INTO #OrgItemStatusCheckUpdateActivity
		FROM [retail].[ItemActivity] ia
		INNER JOIN [organization].[OrgItemStatusTimerXref] oistx ON ia.OrgId = oistx.OrgId
																AND ia.DateActivated BETWEEN DATEADD(minute,(oistx.TimerMinutes-2),@dtTimerDate) 
																						AND DATEADD(minute,oistx.TimerMinutes,@dtTimerDate)
		WHERE @iRowCount = 0  --only if retail not found
			AND ia.ItemStatusId = @iProcessedItemStatusId
			AND oistx.StatusFlag = 1
			AND oistx.DateActivated < @dtTimerDate;
		SET @iRowCount = CASE WHEN @iRowCount = 0 THEN @@ROWCOUNT ELSE @iRowCount END;
		--Item
		UPDATE i
			SET ItemStatusId = @iInitialItemStatusId
				,DateActivated = sysdatetime()
		FROM [ifa].[Item] i
		INNER JOIN #OrgItemStatusCheckUpdateActivity ia on i.ItemId = ia.ItemId
		WHERE @iRowCount > 0;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Error' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
	END CATCH;

	SELECT @nvMsg = @nvMsg + CONVERT(NVARCHAR(10),ItemId) + ',' 
	FROM #OrgItemStatusCheckUpdateActivity
	WHERE @iLogLevel > 0
		AND @iRowCount > 0;
	SET @ncMsg = SUBSTRING(@nvMsg,1,50);
	IF @iLogLevel > 0
		AND @iRowCount > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,@ncMsg,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());

END
