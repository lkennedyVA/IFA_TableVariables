USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspItemUpdateRBOut
	CreatedBy: Larry Dugger
	Descr: This procedure will update the Item, it will not update the StatusFlag
	Tables: [ifa].[Item]
		,[ifa].[ItemType] --WE only pass in what we need not all fields are populated
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2016-01-08 - LBD - Created
		2017-05-01 - LBD - Modified, added new XML output to minimize re-reading data
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-07-10 - LBD - Modified, added Fee to the fields updated.
		2020-11-19 - LBD - RuleBreak is only 0 or 1 adjusted for that
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspItemUpdateRBOut](
	 @ptblItem [ifa].[ItemType] READONLY
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiItemId BIGINT OUTPUT
	,@pxItem XML OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblItem table (
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
		,ClientAcceptedId int
		,OriginalPayerId int
		,OriginalCheckTypeId int
		,AcctChkNbrSwitch bit
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		,insertedRuleBreak nvarchar(25)
		,insertedRuleBreakResponse nvarchar(255)
		,insertedAmount money
		,insertedItemStatusId int
		,insertedDateActivated datetime2(7)
		,insertedUserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'ifa';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE i
			SET i.RuleBreak = CONVERT(INT,CONVERT(BIT,i0.RuleBreak)) --2020-11-19
				,i.RuleBreakResponse = i0.RuleBreakResponse
				,i.Fee = i0.Fee
				,i.Amount = i0.Amount
				,i.ItemStatusId = i0.ItemStatusId
				,i.DateActivated = SYSDATETIME()
				,i.UserName = @pnvUserName
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
				,deleted.ClientAcceptedId
				,deleted.OriginalPayerId
				,deleted.OriginalCheckTypeId
				,deleted.AcctChkNbrSwitch
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
				,inserted.RuleBreak 
				,inserted.RuleBreakResponse
				,inserted.Amount
				,inserted.ItemStatusId
				,inserted.DateActivated
				,inserted.UserName
			INTO @tblItem
			FROM [ifa].[Item] i
			INNER JOIN @ptblItem i0 on i.ItemId = i0.ItemId;
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
			SELECT @pbiItemId = MAX(ItemId)
			FROM @tblItem;
			SET @pxItem = (SELECT ItemId,ItemTypeId,ProcessId,PayerId,ItemKey,ClientItemId,CheckNumber,CheckAmount
								,CheckTypeId,ItemTypeDate,Fee,insertedAmount as Amount,MICR,Scanned
								,insertedRuleBreak as RuleBreak,insertedRuleBreakResponse as RuleBreakResponse
								,insertedItemStatusId as ItemStatusId,ClientAcceptedId,OriginalPayerId
								,OriginalCheckTypeId,AcctChkNbrSwitch,StatusFlag,insertedDateActivated as DateActivated
								,insertedUserName as UserName
							FROM @tblItem Item
							ORDER BY ItemId
							FOR XML PATH('Item')--element set identifier
			)

		END
	END
END
