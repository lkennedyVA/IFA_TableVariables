USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessConfirmationRequest
	CreatedBy: Larry Dugger
	Description: This procedure will initiate an brisk confirmation process
	Tables: [ifa].[Item]
		,[organization].[Org]
		,[financial].[ItemActivity]
		,[stat].[Payer]
		,[stat].[Customer]

	Functions: [common].[ufnItemStatus]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2017-10-25 - LBD - Created, used [ifa].[uspProcessConfirmationRequest]
		2017-12-18 - LBD - Modified, adjusted ItemActivity schema, and added update
			for retail (only one ItemActivity table will be updated, since the ProcessTypeId
			was already used to creat the record.)
		2025-01-15 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [import].[uspProcessConfirmationRequest](
	 @pnvProcessKey NVARCHAR(25)						
	,@piOrgId INT										
	,@ptblItemConfirmRequest [ifa].[ItemConfirmRequestType] READONLY
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piStatusFlag BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ncSchemaName nchar(20) = N'import'
		,@iOrgId int
		,@ncProcessKey NCHAR(25) = @pnvProcessKey;

	drop table if exists #ProcessConfirmationRequestItem
	create table #ProcessConfirmationRequestItem(
		 ItemId bigint not null
		,ItemTypeId int not null
		,ProcessId bigint not null
		,PayerId bigint null
		,ItemKey nvarchar(25) null
		,ClientItemId nvarchar(50) not null
		,CheckNumber nvarchar(50) null
		,CheckAmount money null
		,CheckTypeId int not null
		,ItemTypeDate datetime null
		,DeletedFee money null
		,InsertedFee money null
		,DeletedAmount money null
		,InsertedAmount money null
		,MICR nvarchar(255) null
		,Scanned bit null
		,RuleBreak nvarchar(25) null
		,RuleBreakResponse nvarchar(255) null
		,DeletedItemStatusId int not null
		,InsertedItemStatusId int not null
		,DeletedClientAcceptedId int not null
		,InsertedClientAcceptedId int not null
		,OriginalPayerId int null
		,AcctChkNbrSwitch bit null
		,StatusFlag int not null
		,DeletedDateActivated datetime2(7) not null
		,InsertedDateActivated datetime2(7) not null
		,UserName nvarchar(100) not null
	);
	DECLARE @iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iProcessedItemStatusid int = [common].[ufnItemStatus]('Processed')
		,@iInitialItemStatusid int = [common].[ufnItemStatus]('Initial')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import'
		,@iItemStatus int = 0
		,@iRowCount int = 0;

	SET @piStatusFlag = 1; -- ASSUME No Problem
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE i
		SET ClientAcceptedId = 
				CASE WHEN EXISTS (SELECT 'X' FROM [common].[ufnOrgClientAcceptedXrefByOrgId](p.OrgId) WHERE ClientAcceptedId = icr.ClientAccepted) THEN icr.ClientAccepted ELSE i.ClientAcceptedId END
			,ItemStatusId = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN @iFinalItemStatusId ELSE i.ItemStatusId END
			,Fee = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN icr.Fee ELSE i.Fee END
			,Amount = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN icr.PayoutAmount ELSE i.Amount END
			,DateActivated = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN SYSDATETIME() ELSE i.DateActivated END
			,UserName = @pnvUserName
		OUTPUT deleted.ItemId
			,deleted.ItemTypeId
			,deleted.ProcessId
			,deleted.PayerId
			,deleted.ItemKey
			,deleted.ClientItemId
			,deleted.CheckNumber
			,deleted.CheckAmount
			,deleted.CheckTypeId
			,deleted.ItemTypeDate
			,deleted.Fee
			,inserted.Fee
			,deleted.Amount
			,inserted.Amount
			,deleted.MICR
			,deleted.Scanned
			,deleted.RuleBreak
			,deleted.RuleBreakResponse
			,deleted.ItemStatusId
			,inserted.ItemStatusId
			,deleted.ClientAcceptedId
			,inserted.ClientAcceptedId
			,deleted.OriginalPayerId
			,deleted.AcctChkNbrSwitch
			,deleted.StatusFlag
			,deleted.DateActivated
			,inserted.DateActivated  
			,deleted.UserName
		INTO #ProcessConfirmationRequestItem
		FROM [ifa].[Item] i
		INNER JOIN [ifa].[Process] p ON i.ProcessId = p.ProcessId
										AND p.ProcessKey = @pnvProcessKey
										AND p.OrgId = @piOrgId
		INNER JOIN @ptblItemConfirmRequest icr ON i.ItemKey = icr.ItemKey
												AND i.ClientItemId = icr.ClientItemId;
		SET @iRowCount = @@ROWCOUNT;	
		IF @iRowCount = 0
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
		END
		ELSE IF EXISTS (SELECT 'X' FROM #ProcessConfirmationRequestItem WHERE DeletedItemStatusId = @iInitialItemStatusid)
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('UnProcessed');
		END
		ELSE IF EXISTS (SELECT 'X' FROM #ProcessConfirmationRequestItem WHERE DeletedItemStatusId = @iFinalItemStatusid
												AND DeletedClientAcceptedId = InsertedClientAcceptedId)
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('AlreadyConfirmed');
		END
		ELSE IF EXISTS (SELECT 'X' FROM #ProcessConfirmationRequestItem WHERE DeletedItemStatusId > @iFinalItemStatusId)
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('AlreadyReversed');
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;		
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@pnvProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		BEGIN TRY	--2017-07-18
			--2017-12-18
			UPDATE ia
			SET ItemStatusId = i.InsertedItemStatusId
				,ClientAcceptedId = i.InsertedClientAcceptedId
				,RuleBreak = TRY_CONVERT(INT,i.RuleBreak)
				,DateActivated = i.InsertedDateActivated
			FROM #ProcessConfirmationRequestItem i
			INNER JOIN [financial].[ItemActivity] ia on i.ItemId = ia.ItemId;
			UPDATE ia
			SET ItemStatusId = i.InsertedItemStatusId
				,ClientAcceptedId = i.InsertedClientAcceptedId
				,RuleBreak = TRY_CONVERT(INT,i.RuleBreak)
				,DateActivated = i.InsertedDateActivated
			FROM #ProcessConfirmationRequestItem i
			INNER JOIN [retail].[ItemActivity] ia on i.ItemId = ia.ItemId;
		END TRY
		BEGIN CATCH
			EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@ncProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
		END CATCH;
	END
END
