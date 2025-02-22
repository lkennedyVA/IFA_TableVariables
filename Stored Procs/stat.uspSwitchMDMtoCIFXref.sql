USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/***************************************************************************************
	Name: [stat].[uspSwitchMDMtoCIFXref]
	Created By: Larry Dugger
	Description: Procedure to resynch the following table.
 	 
	Tables: [new].[MDMtoCIFXref]
		,[old].[MDMtoCIFXref]
		,[stat].[MDMtoCIFXref]

	History:
		2023-03-30 - LBD - Created, we only truncate [old].[MDMtoCIFXref] as a precaution.
*****************************************************************************************/
ALTER   PROCEDURE [stat].[uspSwitchMDMtoCIFXref]
AS
BEGIN
	DECLARE @tblIFATiming [dbo].[IFATimingType];
	DECLARE @ncProcessKey nchar(25) = REPLACE(REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(50),sysdatetime(),121),'-',''),' ',''),':',''),'.','');
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [stat].[uspSwitchMDMtoCIFXref]')),1)
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@nvTargetTable sysname = N'old.MDMtoCIFXref'
		,@nvSQLCmd nvarchar(4000);

	DECLARE @bEnableTimer bit = 1
		,@iErrorDetailId INT
		,@sSchemaName nvarchar(128) = 'stat';

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME()); 
		SET @dtTimerDate = SYSDATETIME()
	END
	--Clean out old schema table
	IF [stat].[ufnTableExists](@nvTargetTable) = 1
	BEGIN
		SET @nvSQLCmd = 'TRUNCATE TABLE ' + @nvTargetTable
		EXEC (@nvSQLCmd)
	END
	--TABLE SWITCHING
	BEGIN TRY
		--Let the Renaming Begin, these tables need no updates, just replacements
		--SWITCH New and Current DollarStrat
		IF [stat].[ufnTableExists](N'[stat].[MDMtoCIFXref]') = 1
			AND [stat].[ufnTableExists](N'[new].[MDMtoCIFXref]') = 1
		BEGIN
			BEGIN TRAN
				--Anyone who tries to query the table after the switch has happened and before
				--the transaction commits will be blocked: we've got a schema mod lock on the table

				--cycle out Current DollarStrat
				ALTER TABLE [stat].[MDMtoCIFXref] SWITCH PARTITION 1 TO [old].[MDMtoCIFXref] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  

				--Cycle in New DollarStrat
				ALTER TABLE [new].[MDMtoCIFXref] SWITCH PARTITION 1 TO [stat].[MDMtoCIFXref] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));

				-- Cycle Old to New
				ALTER TABLE [old].[MDMtoCIFXref] SWITCH PARTITION 1 TO [new].[MDMtoCIFXref] PARTITION 1
					WITH ( WAIT_AT_LOW_PRIORITY ( MAX_DURATION = 1 MINUTES, ABORT_AFTER_WAIT = BLOCKERS ));  
			COMMIT

			IF @iLogLevel > 0
			BEGIN
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Switched MDMtoCIFXref',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
				SET @dtTimerDate  = SYSDATETIME();
			END
		END
		ELSE --SWITCH New and Current MDMtoCIFXref
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'MDMtoCIFXref Not Switched',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			THROW 50000,N'MDMtoCIFXref Not Switched',1;
		END
	END TRY
	BEGIN CATCH
		ROLLBACK
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
			,CASE WHEN DATEDIFF(SECOND,@dtInitial,SYSDATETIME()) < 2147 
				THEN DATEDIFF(microsecond,@dtInitial,SYSDATETIME())
				ELSE 0
			END
			,SYSDATETIME());  

END
