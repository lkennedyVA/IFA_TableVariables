USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspItemUpdateOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the Item, it will not update the StatusFlag
	Tables: [ifa].[Item]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2016-06-10 - LBD - Modified, insert ItemActivity at this point
		2017-12-18 - LBD - Modified, adjusts ItemActivity schema
			and aware of Retail
		2019-12-10 - LBD - Modified, corrected the 'ItemActivity' ItemStatusId
			it was improperly updating the ItemTypeId...
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspItemUpdateOut](
	 @pnvRuleBreak NVARCHAR(25) = N''
	,@pnvRuleBreakResponse NVARCHAR(255) = N''
	,@pmAmount MONEY = -1.0
	,@pbRetail BIT = 0
	,@piItemStatusId INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiItemId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Item table (
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
		,OriginalCheckTypeId int
		,AcctChkNbrSwitch bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,InsertedDateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'ifa';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [ifa].[Item]
			SET RuleBreak = CASE WHEN @pnvRuleBreak = N'' THEN RuleBreak ELSE @pnvRuleBreak END
				,RuleBreakResponse = CASE WHEN @pnvRuleBreakResponse = N'' THEN RuleBreakResponse ELSE @pnvRuleBreakResponse END
				,Amount = CASE WHEN ISNULL(@pmAmount,-1.0) = -1.0 THEN Amount ELSE @pmAmount END
				,ItemStatusId = CASE WHEN  ISNULL(@piItemStatusId,-1) = -1 THEN ItemStatusId ELSE @piItemStatusId END
				,DateActivated = SYSDATETIME()
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
				,deleted.Amount
				,deleted.MICR
				,deleted.Scanned
				,deleted.RuleBreak
				,deleted.RuleBreakResponse
				,deleted.ItemStatusId
				,inserted.ItemStatusId
				,deleted.ClientAcceptedId
				,deleted.OriginalPayerId
				,deleted.OriginalCheckTypeId
				,deleted.AcctChkNbrSwitch
				,deleted.StatusFlag
				,deleted.DateActivated
				,inserted.DateActivated
				,deleted.UserName
			INTO @Item
			WHERE ItemId = @pbiItemId;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @pbiItemId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			--UPDATE ItemActivity
			--2017-12-18
			IF @pbRetail = 0
				UPDATE ia
				--2019-12-10 SET ItemTypeId = i.InsertedItemStatusId
				SET ItemStatusId = i.InsertedItemStatusId
					,DateActivated = i.InsertedDateActivated
					,@pbiItemId = i.ItemId
				FROM @Item i
				INNER JOIN [financial].[ItemActivity] ia on i.ItemId = ia.ItemId
			ELSE
				UPDATE ia
				--2019-12-10 SET ItemTypeId = i.InsertedItemStatusId
				SET ItemStatusId = i.InsertedItemStatusId
					,DateActivated = i.InsertedDateActivated
					,@pbiItemId = i.ItemId
				FROM @Item i
				INNER JOIN [retail].[ItemActivity] ia on i.ItemId = ia.ItemId
		END
	END
END
