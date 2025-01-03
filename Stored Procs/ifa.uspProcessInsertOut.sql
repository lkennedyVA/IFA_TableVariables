USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert a new record
	Tables: [ifa].[Process]
		,[ifa].[TransactionKey]
	Functions: [common].[ufnZeroFill]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2016-07-07 - LBD - Modified, added ProcessTypeId
		2017-08-08 - LBD - Modified, added timing internally
		2019-02-13 - LBD - Modified, enabled direct logging
		2019-02-23 - LBD - Modified, improved direct logging
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspProcessInsertOut](
	@piProcessTypeId INT
	,@piOrgId INT
	,@pbiCustomerId BIGINT
	,@pnvProcessKey NVARCHAR(25)
	,@pnvClientRequestId NVARCHAR(50)
	,@pnvClientRequestId2 NVARCHAR(50)
	,@pbiAccountId BIGINT
	,@piItemCount INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiProcessId BIGINT OUTPUT
)
AS
BEGIN
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspProcessInsertOut]')),1)	--2019-02-23 LBD
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = N'ifa'
		,@ncObjectName nchar(50) = N'uspProcessInsertOut'
		,@ncProcessKey NCHAR(25) = @pnvProcessKey;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  		
		SET @dtTimerDate = SYSDATETIME();
	END

	--2017-08-03
	DECLARE @Process table (
		ProcessId bigint
		,ProcessTypeId int
		,OrgId int
		,CustomerId bigint
		,ProcessKey nvarchar(25)
		,ClientRequestId nvarchar(50)
		,ClientRequestId2 nvarchar(50)
		,AccountId bigint
		,ItemCount int
		,ValidStatusCodes nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iTransactionTypeId int = [common].[ufnTransactionType]('Process')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'ifa';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [ifa].[Process]
			OUTPUT inserted.ProcessId 
				,inserted.ProcessTypeId
				,inserted.OrgId
				,inserted.CustomerId
				,inserted.ProcessKey
				,inserted.ClientRequestId
				,inserted.ClientRequestId2
				,inserted.AccountId
				,inserted.ItemCount
				,inserted.ValidStatusCodes
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @Process
		SELECT @piProcessTypeId 
			,@piOrgId
			,@pbiCustomerId
			,@pnvProcessKey
			,@pnvClientRequestId
			,@pnvClientRequestId2
			,@pbiAccountId
			,@piItemCount
			,NULL
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @pbiProcessId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		--Since we have created the Process, now lets insert our reference record 
		INSERT INTO [ifa].[TransactionKey](TransactionKey,TransactionId,TransactionTypeId,StatusFlag,DateActivated,UserName)
		SELECT ProcessKey,ProcessId,@iTransactionTypeId,@piStatusFlag,SYSDATETIME(),UserName
		FROM @Process;
		SELECT @pbiProcessId = ProcessId
		FROM @Process;
	END
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());

END
