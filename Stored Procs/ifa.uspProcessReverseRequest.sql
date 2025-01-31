USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessReverseRequest
	CreatedBy: Larry Dugger
	Description: This procedure will initiate a Process reversal
	Tables: [ifa].[Process]
		,[ifa].[Item]
		,[common].[ItemStatus]

	Functions: [common].[ufnDimension]
		,[common].[ufnItemStatus]
		,[common].[ufnTransactionType]
		,[ifa].[ufnProcessMethodologyDeux]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2014-10-08 - LBD - Created
		2015-06-18 - LBD - Modified, adjusted return parameter and some conditional logic
		2015-08-04 - LBD - Modified, Added ClientAcceptedId
		2016-03-03 - LBD - Modified, Adjusted error messages to correctly report error.
		2016-06-10 - LBD - Modified, update ItemActivity at this point
		2016-08-09 - LBD - Modified, added @piOrgId to add another verification 
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-08-18 - LBD - Modified, remove any duplicate item created when finalized.
		2017-12-18 - LBD - Modified, adjusted ItemActivity schema, and added update
			for retail (only one ItemActivity table will be updated, since the ProcessTypeId
			was already used to creat the record.)
		2018-05-04 - LBD - Modified, added 'Deluxe' support added update for authorized
		2018-08-06 - LBD - Modified, added additional parameter and changed
			Raise errors to become pass backs
		2018-08-31 - LBD - Modified, adjusted to function like Confirmation
		2019-02-13 - LBD - Modified, enabled direct logging
		2019-02-23 - LBD - Modified, improved direct logging
		2019-12-10 - LBD - Modified, corrected the 'ItemActivity' ItemStatusId
			it was improperly updating the ItemTypeId...
		2020-02-07 - LBD - Modified, use new function to grab ProcessMethodology 
			streamlined code
		2020-04-17 - LBD - Adjusted to handle ItemActivity proceduralization
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-09-13 - LBD - Replace [ifa].[ufnProcessMethodology] with
			[ifa].[ufnProcessMethodologyDeux]
		2025-01-14 - LXK - Replaced table variable with local temp table.
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspProcessReverseRequest](
	@pnvProcessKey NVARCHAR(25)							--aka TransactionKey
	,@piOrgId INT										--This is the system id for a given locationid
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiReverse BIGINT OUTPUT
	,@pnvMsg NVARCHAR(100) OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblItem [ifa].[ItemType]
		,@tblOL [ifa].[OrgListType];

/* drop table if exists #ProcessReverseRequestItemType
create table #ProcessReverseRequestItemType(
	[ItemId] [bigint] NULL,
	[ItemTypeId] [int] NULL,
	[ProcessId] [bigint] NULL,
	[PayerId] [bigint] NULL,
	[ItemKey] [nvarchar](25) NULL,
	[ClientItemId] [nvarchar](50) NULL,
	[CheckNumber] [nvarchar](50) NULL,
	[CheckAmount] [money] NULL,
	[CheckTypeId] [int] NULL,
	[ItemTypeDate] [datetime] NULL,
	[Fee] [money] NULL,
	[Amount] [money] NULL,
	[MICR] [nvarchar](255) NULL,
	[Scanned] [bit] NULL,
	[RuleBreak] [nvarchar](25) NULL,
	[RuleBreakResponse] [nvarchar](255) NULL,
	[ItemStatusId] [int] NULL,
	[ClientAcceptedId] [int] NULL,
	[OriginalPayerId] [int] NULL,
	[OriginalCheckTypeId] [int] NULL,
	[AcctChkNbrSwitch] [bit] NULL,
	[StatusFlag] [int] NULL,
	[DateActivated] [datetime2](7) NULL,
	[UserName] [nvarchar](100) NULL
);

drop table if exists #ProcessReverseRequestOL
create table #ProcessReverseRequestOL(
	[LevelId] [nvarchar](25) NULL,
	[RelatedOrgId] [int] NULL,
	[OrgId] [int] NULL,
	[OrgCode] [nvarchar](25) NULL,
	[OrgName] [nvarchar](50) NULL,
	[ExternalCode] [nvarchar](50) NULL,
	[OrgDescr] [nvarchar](255) NULL,
	[OrgTypeId] [int] NULL,
	[Type] [nvarchar](50) NULL,
	[StatusFlag] [int] NULL,
	[DateActivated] [datetime2](7) NULL,
	[UserName] [nvarchar](100) NULL
); */

drop table if exists #ProcessReverseRequestItem
	create table #ProcessReverseRequestItem table (
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
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspProcessReverseRequest]')),1) --2018-08-31 LBD 
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME( @@PROCID ))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME( @@PROCID ))
		,@iOrgId int = @piOrgId
		,@ncProcessKey NCHAR(25) = @pnvProcessKey
		,@iReverseItemStatusId int = [common].[ufnItemStatus]('Reversed')
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@biTransactionId bigint 
		,@iTransactionTypeId int = [common].[ufnTransactionType]('Item')
		,@biPayerId bigint = 0
		,@nvCheckNumber nvarchar(50)
		,@nvRuleBreak nvarchar(25)
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME( @@PROCID )
		,@iItemStatus int
		,@iProcessItemCount int = 0
		,@bRetail bit = 0
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@iProcessMethodology int
		--,@iOrgClientId int = [common].[ufnOrgClientId](@piOrgId)
		,@iProcessTypeId int;

	SET @pnvMsg = NULL;

	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		SET @dtTimerDate = SYSDATETIME();
	END

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @pbiReverse = -1; -- ASSUME error

	--SET @iProcessMethodology = [ifa].[ufnProcessMethodology](@iOrgClientId,@iOrgId) --2020-02-07 2020-09-13

	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE i
		SET  @iProcessItemCount = p.ItemCount
			,@iItemStatus = ItemStatusId 
			,@bRetail = [common].[ufnRetail](p.ProcessTypeId)
			,@iProcessTypeId = p.ProcessTypeId
			,ItemStatusId = CASE WHEN i.ItemStatusId <> @iReverseItemStatusId THEN @iReverseItemStatusId ELSE i.ItemStatusId END
			,DateActivated = CASE WHEN i.ItemStatusId <> @iReverseItemStatusId THEN SYSDATETIME() ELSE i.DateActivated END
			,UserName = CASE WHEN i.ItemStatusId <> @iReverseItemStatusId THEN @pnvUserName ELSE i.UserName END
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
			AND p.OrgId = @piOrgId;

		--2018-08-31
		SELECT @pbiReverse = ProcessId
		FROM #ProcessReverseRequestItem;

		IF @iProcessItemCount = 0 
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'TransactionKey and Item Confirmations Disconnect',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  --2019-02-23
			SET @pnvMsg = 'Your Transaction Key doesn''t match'
			SET @pbiReverse = -1;
			RETURN
		END
		ELSE IF @iItemStatus = @iReverseItemStatusId
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item Reversals not valid for Reversed Status',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  --2019-02-23
			SET @pnvMsg = 'The Item Reversals have already been reversed'
			SET @pbiReverse = @pbiReverse * -1;
			RETURN
		END
		--2018-08-31
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  --2019-02-23
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		--2019-02-23
		IF @iLogLevel > 1
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Update Items',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  
			SET @dtTimerDate = SYSDATETIME();
		END
		--2019-02-23
		--REMOVE Reversal from DuplicateItem, if it was a finalstatus, with no rule break
		SELECT @biPayerId = PayerId
			,@nvCheckNumber = CheckNumber
		FROM #ProcessReverseRequestItem
		WHERE ItemStatusId = @iFinalItemStatusId
			AND RuleBreak = '0';
		IF @biPayerId <> 0
			EXECUTE [condensed].[uspDuplicateItemDelete2] @pbiPayerId=@biPayerId,@pnvCheckNumber=@nvCheckNumber;

		--PROVIDE what ItemActivityUpdate needs
		INSERT INTO @tblItem (ItemId,ItemStatusId,DateActivated)
		SELECT ItemId,InsertedItemStatusId,InsertedDateActivated
		FROM #ProcessReverseRequestItem;
		--2020-09-13	
		INSERT INTO @tblOL (LevelId, RelatedOrgId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, OrgTypeId, [Type], StatusFlag)
		SELECT LevelId, ChildId, OrgId, OrgCode, OrgName, ExternalCode, OrgDescr, TypeId, [Type], StatusFlag
		FROM [common].[ufnUpDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId); 

		SELECT @iProcessMethodology = ProcessMethodologyId
		FROM [ifa].[ufnProcessMethodologyDeux](@tblOL,@iProcessTypeId);

		--UPDATE ItemActivity via procedure
		EXECUTE [ifa].[uspItemActivityUpdate]
			 @ptblItem = @tblItem 
			,@piProcessMethodology = @iProcessMethodology
			,@pncProcessKey = @ncProcessKey
			,@pnvSrc = @ncObjectName;	--uspProcessReverseRequest

		SELECT @pbiReverse = i.ProcessId
		FROM #ProcessReverseRequestItem i;
	END 
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME());  --2019-02-23

END
