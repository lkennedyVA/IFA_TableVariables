USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*******************************************************************
	Name: [ifa].[uspAutoFraudSwitch]
	Created By: Larry Dugger
	Description: Procedure to switch the trio of [%}.[AutoFraud] tables 
		Usage Example:

		set identity_insert [new].[AutoFraud] on
		insert into [new].[AutoFraud]([AutoFraudId], [AutoFraudTypeId], [OrgId], [KeyId], [StatusFlag], [DateActivated], [DateExpired], [UserName])
		select [AutoFraudId], [AutoFraudTypeId], [OrgId], [KeyId], [StatusFlag], [DateActivated], [DateExpired], [UserName]
		from [ifa].[AutoFraud]
		where StatusFlag = 1;
		set identity_insert [new].[AutoFraud] off

		execute [ifa].[uspAutoFraudSwitch]

		exec sp_spaceused '[new].[AutoFraud]'
		exec sp_spaceused '[ifa].[AutoFraud]'
		exec sp_spaceused '[old].[AutoFraud]'

	Tables: [ifa].[AutoFraud]
		,[new].[AutoFraud]
		,[old].[AutoFraud]

	History:
		2020-12-18 - LBD - Created, this is the fastest way to reload/trim high activity
			tables.
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspAutoFraudSwitch]
AS
BEGIN
	DECLARE @tblIFATiming [dbo].[IFATimingType];
	DECLARE @ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','');
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspAutoFraudSwitch]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID));

	DECLARE @bEnableTimer bit = 1
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate = SYSDATETIME()
	END

	--TABLE SWITCHING
	BEGIN TRY
		--Let the Renaming Begin, these tables need no updates, just replacements
		--SWITCH New and Current DuplicateItme
		IF [mac].[ufnTableExists](N'[ifa].[AutoFraud]') = 1
			AND [mac].[ufnTableExists](N'[new].[AutoFraud]') = 1
			AND [mac].[ufnTableExists](N'[old].[AutoFraud]') = 1
		BEGIN
			BEGIN TRAN
				--Anyone who tries to query the table after the switch has happened and before
				--the transaction commits will be blocked: we've got a schema mod lock on the table

				--cycle out Current DollarStrat
				ALTER TABLE [ifa].[AutoFraud] SWITCH PARTITION 1 TO [old].[AutoFraud] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

				--Cycle in New DollarStrat
				ALTER TABLE [new].[AutoFraud] SWITCH PARTITION 1 TO [ifa].[AutoFraud] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

				-- Cycle Old to New
				ALTER TABLE [old].[AutoFraud] SWITCH PARTITION 1 TO [new].[AutoFraud] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
			COMMIT

			IF @iLogLevel > 0
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched AutoFraud',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
				SET @dtTimerDate  = SYSDATETIME();
			END
		END
		ELSE --SWITCH New and Current DuplicateItem
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'AutoFraud Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW 50000,N'AutoFraud Not Switched',1;
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
