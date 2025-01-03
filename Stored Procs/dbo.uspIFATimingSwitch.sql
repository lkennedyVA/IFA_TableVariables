USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************
	Name: [ifa].[uspIFATimingSwitch]
	Created By: Larry Dugger
	Description: Procedure to switch the trio of [%}.[IFATiming] tables 
		Usage Example:

		set identity_insert [new].[IFATiming] on
		insert into [new].[IFATiming]([IFATimingId], [ProcessKey], [SchemaName], [ObjectName], [Msg], [Microseconds], [DateExecuted], [DateActivated])
		select [IFATimingId], [ProcessKey], [SchemaName], [ObjectName], [Msg], [Microseconds], [DateExecuted], [DateActivated]
		from [dbo].[IFATiming]
		where DateActivated > 'getdate()-10;
		set identity_insert [new].[IFATiming] off

		execute [dbo].[uspIFATimingSwitch]

		exec sp_spaceused '[new].[IFATiming]'
		exec sp_spaceused '[dbo].[IFATiming]'
		exec sp_spaceused '[old].[IFATiming]'

	Tables: [dbo].[IFATiming]
		,[new].[IFATiming]
		,[old].[IFATiming]

	History:
		2020-12-18 - LBD - Created, this is the fastest way to reload/trim high activity
			tables.
*****************************************************************************************/
ALTER   PROCEDURE [dbo].[uspIFATimingSwitch]
AS
BEGIN
	DECLARE @tblIFATiming [dbo].[IFATimingType];
	DECLARE @ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','');
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [dbo].[uspIFATimingSwitch]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID));

	DECLARE @bEnableTimer bit = 1
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [new].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate = SYSDATETIME()
	END

	--TABLE SWITCHING
	BEGIN TRY
		--Let the Renaming Begin, these tables need no updates, just replacements
		--SWITCH New and Current DuplicateItme
		IF [mac].[ufnTableExists](N'[dbo].[IFATiming]') = 1
			AND [mac].[ufnTableExists](N'[new].[IFATiming]') = 1
			AND [mac].[ufnTableExists](N'[old].[IFATiming]') = 1
		BEGIN
			BEGIN TRAN
				--Anyone who tries to query the table after the switch has happened and before
				--the transaction commits will be blocked: we've got a schema mod lock on the table

				--cycle out Current DollarStrat
				ALTER TABLE [dbo].[IFATiming] SWITCH PARTITION 1 TO [old].[IFATiming] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

				--Cycle in New DollarStrat
				ALTER TABLE [new].[IFATiming] SWITCH PARTITION 1 TO [dbo].[IFATiming] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

				-- Cycle Old to New
				ALTER TABLE [old].[IFATiming] SWITCH PARTITION 1 TO [new].[IFATiming] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
			COMMIT

			IF @iLogLevel > 0
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched IFATiming',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
				SET @dtTimerDate  = SYSDATETIME();
			END
		END
		ELSE --SWITCH New and Current DuplicateItem
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'IFATiming Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW 50000,N'IFATiming Not Switched',1;
		END
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
		THROW
	END CATCH
	--ADJUSTED TO HANDLE THE RETURN LIMIT
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' 
			,CASE WHEN DATEDIFF(SECOND,@dtInitial,SYSDATETIME()) < 2147 --2017-08-11 LBD
				THEN DATEDIFF(microsecond,@dtInitial,SYSDATETIME())
				ELSE 0
			END
			,SYSDATETIME());  

END
