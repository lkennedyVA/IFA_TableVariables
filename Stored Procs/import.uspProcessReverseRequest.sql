USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessReverseRequest
	CreatedBy: Larry Dugger
	Description: This procedure will initiate a Process reversal, but doesn't 
		error out when not found
	Tables: [ifa].[Process]
		,[ifa].[Item]
		,[common].[ItemStatus]
 
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2017-10-25 - LBD - Create, copied from [ifa].[uspProcessReverseRequest]	 
		2017-12-18 - LBD - Modified, adjusted ItemActivity schema, and added update
			for retail (only one ItemActivity table will be updated, since the ProcessTypeId
			was already used to creat the record.)
		2025-01-15 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [import].[uspProcessReverseRequest](
	 @pnvProcessKey NVARCHAR(25)
	,@pnvItemKey NVARCHAR(25)
	,@piOrgId INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piStatusFlag INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ProcessReverseRequestItem
	create table #ProcessReverseRequestItem(
		 ItemId bigint
		,ItemTypeId int
		,ProcessId bigint
		,PayerId bigint
		,ItemKey nvarchar(25) 
		,ClientItemId nvarchar(50)
		,CheckNumber nvarchar(50)
		,CheckAmount money
		,CheckTypeId int
		,ItemTypeDate date
		,Fee money
		,Amount money
		,MICR nvarchar(255)
		,Scanned bit
		,RuleBreak nvarchar(25)
		,RuleBreakResponse nvarchar(255)
		,ItemStatusId int
		,InsertedItemStatusId int
		,ClientAcceptedId int
		,OriginalPayerId int
		,AcctChkNbrSwitch bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,InsertedDateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@biPayerId bigint = 0
		,@nvCheckNumber nvarchar(50)
		,@nvRuleBreak nvarchar(25)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = N'import';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @piStatusFlag = 1; -- ASSUME No Problem
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE i
		SET ItemStatusId = CASE WHEN i.ItemStatusId <> @iReverseItemStatusId THEN @iReverseItemStatusId ELSE i.ItemStatusId END
			,DateActivated = CASE WHEN i.ItemStatusId <> @iReverseItemStatusId THEN SYSDATETIME() ELSE i.DateActivated END
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
			,deleted.Amount
			,deleted.MICR
			,deleted.Scanned
			,deleted.RuleBreak
			,deleted.RuleBreakResponse
			,deleted.ItemStatusId
			,inserted.ItemStatusId
			,deleted.ClientAcceptedId
			,deleted.OriginalPayerId
			,deleted.AcctChkNbrSwitch
			,deleted.StatusFlag
			,deleted.DateActivated 
			,inserted.DateActivated 
			,deleted.UserName 
		INTO #ProcessReverseRequestItem
		FROM [ifa].[Item] i
		INNER JOIN [ifa].[Process] p on i.ProcessId = p.ProcessId
		WHERE p.ProcessKey = @pnvProcessKey
			and i.ItemKey = @pnvItemKey
			AND p.OrgId = @piOrgId;
		IF EXISTS (SELECT 'X' FROM #ProcessReverseRequestItem WHERE ItemStatusId = @iReverseItemStatusId)
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('AlreadyReversed');
		END
		ELSE IF NOT EXISTS (SELECT 'X' FROM #ProcessReverseRequestItem)
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			SET @piStatusFlag = [import].[ufnStatusFlag]('DoesntExist');
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
		--REMOVE Reversal from DuplicateItem, if it was a finalstatus, with no rule break
		SELECT @biPayerId = PayerId
			,@nvCheckNumber = CheckNumber
		FROM #ProcessReverseRequestItem
		WHERE ItemStatusId = @iFinalItemStatusId
			AND RuleBreak = '0';
		IF @biPayerId <> 0
			EXECUTE [condensed].[uspDuplicateItemDelete2] @pbiPayerId=@biPayerId,@pnvCheckNumber=@nvCheckNumber;
		--UPDATE ItemActivity
		--2017-12-18
		UPDATE ia
		SET ItemTypeId = i.InsertedItemStatusId
			,DateActivated = i.InsertedDateActivated
		FROM #ProcessReverseRequestItem i
		INNER JOIN [financial].[ItemActivity] ia on i.ItemId = ia.ItemId;
		UPDATE ia
		SET ItemTypeId = i.InsertedItemStatusId
			,DateActivated = i.InsertedDateActivated
		FROM #ProcessReverseRequestItem i
		INNER JOIN [retail].[ItemActivity] ia on i.ItemId = ia.ItemId;
	END 
END
