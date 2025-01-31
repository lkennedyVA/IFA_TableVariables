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
		,[Condensed].[stat].[NewDuplicateItem]

	Functions: [common].[ufnItemStatus]
		,[ifa].[ufnProcessMethodologyDeux]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2015-06-29 - LBD - Modified, rollback in the case of an error....
			don't return the error code...
			--WE NEED TO ADD CLIENT ACCEPTED ON EACH ITEM 
			--NOTE WE REQUIRE ALL ITEMS MUST BE PASSED IN FOR A CONFIRMATION
		2015-08-04 - LBD - Modified, adjusted to handle ClientAcceptedId
		2015-08-17 - LBD - Modified, adjusted to allow varied item statuses
		2016-05-23 - CBS - Modified, adding check number and removing user name in 
			[financial].[ItemActivity]
		2016-06-10 - LBD - Modified, changed insert ItemActivity to update
		2016-06-28 - LBD - Modified, added update/insert for PayerCount
		2016-07-01 - CBS - Modified, added update/insert for CustomerCount
		2016-08-09 - LBD - Modified, added @piOrgId to add another verification 
		2017-02-06 - LBD - Modified, commented out use of count tables
		2017-03-08 - LDB - Modified, added DuplicateItem Insert
		2017-06-03 - LBD - Modified, removed use of archive tables
		2017-06-28 - LBD - Modified, added timing to differentiate between ItemActivity
			and DuplicateItem timing
		2017-07-12 - LBD - Modified, adjusted to write to [stat].[NewDuplicateItem]
		2017-07-15 - LBD - Modified, Removed check for dups ON NewDuplicateItem
			,it doesn't need them
		2017-07-16 - LBD - Modified, removed explicit Transaction around DuplicateItemInsert
			and ItemActivity update
		2017-07-18 - LBD - Modified, reordered, to prevent IFATiming being within an
			explicit transaction
		2017-07-21 - LBD - Modified, turned off timing, except for entry and exit
		2017-08-01 - LBD - Modified, moved initial timing call to very top, per Mike R.
		2017-08-03 - LBD - Modified, converted to new timing procedure, adjusted message lengths
		2017-08-23 - LBD - Disabled NewDuplicateItem Insert
		2017-08-21 - LBD - Modified, adjusted output message to new V106 exceptions
		2017-08-23 - LBD - Modified, disabled additional timing checks
		2017-09-18 - LBD - Modified, re-adjusted some V101 messages
		2017-12-18 - LBD - Modified, adjusted ItemActivity schema, and added update
			for retail (only one ItemActivity table will be updated, since the ProcessTypeId
			was already used to creat the record.)
		2018-05-04 - LBD - Modified, added 'Deluxe' support added update for authorized
		2018-08-06 - LBD - Modified, added additional parameter and changed
			Raise errors to become pass backs 
		2018-08-31 - LBD - Modified, adjusted to function like Reversal
		2018-11-20 - LBD - Modified, update the AuthorizedFlag to 0 when the 
			confirmation is from the Push Pay org...under Deluxe Client 
		2019-02-13 - LBD - Modified, enabled direct logging
		2019-02-23 - LBD - Modified, improved direct logging
		2020-02-07 - LBD - Modified, use new function to grab ProcessMethodology 
			streamlined code
		2020-04-17 - LBD - Adjusted to handle ItemActivity proceduralization
		2020-06-03 - LBD - Adjusted logging so it operates without locking (unless necessary)
		2020-09-13 - LBD - Replace [ifa].[ufnProcessMethodology] with
			[ifa].[ufnProcessMethodologyDeux], added restriction that Items Confirmed
			must equal Process.ItemCount
		2022-04-04 - LBD - VALID-211. Added support for new ProcessMethodolgy D2C
			this includes adding the @Item.InsertedFee (Fee) 
			and @Item.InsertedAmount (PayoutAmount) to @tblItem.Fee 
			and @tblItem.Amount respectively, for [ifa].[uspItemActivityUpdate] 
		2023-04-03 - CBS - VALID-872: Added check to ensure the ClientAcceptedIds on the Items
			exist in the return of [common].[ufnOrgClientAcceptedXrefByOrgId] prior to performing
			the update
		2025-01-13 - LXK - Replaced table variable with local temp table.
*****************************************************************************************/
ALTER   PROCEDURE [ifa].[uspProcessConfirmationRequest](
	@pnvProcessKey NVARCHAR(25)							--aka TransactionKey
	,@piOrgId INT										--This is the system id for a given locationid
	,@ptblItemConfirmRequest [ifa].[ItemConfirmRequestType] READONLY
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@pbiConfirmation BIGINT OUTPUT
	,@pnvMsg NVARCHAR(100) OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	
	DECLARE @tblItem [ifa].[ItemType]
		,@tblOL [ifa].[OrgListType];

/* drop table if exists #ProcessConfirmRequestItemType
create table #ProcessConfirmRequestItemType(
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
drop table if exists #ProcessConfirmRequestOrgListType
create table #ProcessConfirmRequestOrgListType(
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
	drop table if exists #ProcessConfirmRequestItem
	create table #ProcessConfirmRequestItem(
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
	DECLARE @iLogLevel int = ISNULL(TRY_CONVERT(INT,[common].[ufnConfigValue](N'LogLevel [ifa].[uspProcessConfirmationRequest]')),1)	--2019-02-23 LBD
		,@dtTimerDate datetime2(7) = SYSDATETIME()
		,@dtInitial datetime2(7) = SYSDATETIME() --used for complete time in procedure
		,@ncSchemaName nchar(20) = CONVERT(nchar(20),OBJECT_SCHEMA_NAME(@@PROCID))
		,@ncObjectName nchar(50) = CONVERT(nchar(50),OBJECT_NAME(@@PROCID))
		,@iOrgId int = @piOrgId
		,@ncProcessKey NCHAR(25) = @pnvProcessKey
		,@iFinalItemStatusId int = [common].[ufnItemStatus]('Final')
		,@iProcessedItemStatusid int = [common].[ufnItemStatus]('Processed')
		,@iInitialItemStatusid int = [common].[ufnItemStatus]('Initial')
		,@iReversedlItemStatusid int = [common].[ufnItemStatus]('Reversed')
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID)
		,@iItemStatus int = 0
		,@bClientAcceptedInvalid int = 0
		,@iProcessItemCount int = 0
		,@iItemCount int = 0
		,@iFoundClientAcceptedIds int = 0 --2023-04-03
		,@bUniqueItems bit = 0
		,@iUniqueItemsKeys int = 0
		,@iUniqueClientItemIds int = 0
		,@iItemsUpdated int = 0 --2020-09-13
		,@iConfirmedCount int = 0
		,@vbDuplicateItemMac varbinary(32)
		,@bRetail bit = 0
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@iProcessMethodology int
		,@iProcessTypeId int;	--2020-09-13

	SET @pnvMsg = NULL;
	
	IF @iLogLevel > 0
	BEGIN
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Enter' ,DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());  	
		SET @dtTimerDate = SYSDATETIME();
	END

	SET @pbiConfirmation = -1;-- ASSSUME error
	--Are the Items submitted unique?
	SELECT @iUniqueItemsKeys = COUNT(Distinct ItemKey)
	FROM @ptblItemConfirmRequest;
	SELECT @iUniqueClientItemIds = COUNT(Distinct ClientItemId)
	FROM @ptblItemConfirmRequest;

	SET @bUniqueItems = CASE WHEN @iUniqueItemsKeys = @iUniqueClientItemIds THEN 1 ELSE 0 END;
	SELECT @iItemCount = COUNT(*)
	FROM @ptblItemConfirmRequest;

	--2023-04-03 Checking to ensure the total number of Items have existence in [common].[ufnOrgClientAcceptedXrefByOrgId]
	SELECT @iFoundClientAcceptedIds = COUNT(cax.ClientAcceptedId) 
	FROM [common].[ufnOrgClientAcceptedXrefByOrgId](@iOrgId) cax
	INNER JOIN @ptblItemConfirmRequest icr 
		ON cax.ClientAcceptedId = icr.ClientAccepted;

	IF @iItemCount <> @iFoundClientAcceptedIds
	BEGIN
		RAISERROR ('ClientAcceptedId not allowed for the Org', 16, 1)
		RETURN
	END

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE i
		SET  @iProcessItemCount=p.ItemCount
			,@iItemStatus = ItemStatusId
			,@bRetail = [common].[ufnRetail](p.ProcessTypeId)--2018-05-04
			,@iProcessTypeId = p.ProcessTypeId --2020-09-13
			,ClientAcceptedId = icr.ClientAccepted --2023-04-03  Already performed the existance check above.  Update to the value passed in via @ptblItemConfirmRequest
			--,ClientAcceptedId = CASE WHEN EXISTS (SELECT 'X' FROM [common].[ufnOrgClientAcceptedXrefByOrgId](p.OrgId) WHERE ClientAcceptedId = icr.ClientAccepted) THEN icr.ClientAccepted ELSE i.ClientAcceptedId END --2023-04-03
			,ItemStatusId = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN @iFinalItemStatusId ELSE i.ItemStatusId END
			,Fee = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN icr.Fee ELSE i.Fee END
			,Amount = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN icr.PayoutAmount ELSE i.Amount END
			,DateActivated = CASE WHEN ItemStatusId = @iProcessedItemStatusid THEN SYSDATETIME() ELSE i.DateActivated END
			,UserName = CASE WHEN i.ItemStatusId = @iProcessedItemStatusid THEN @pnvUserName ELSE i.UserName END
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
		INTO #ProcessConfirmRequestItem
		FROM [ifa].[Item] i
		INNER JOIN [ifa].[Process] p ON i.ProcessId = p.ProcessId
										AND p.ProcessKey = @pnvProcessKey
										AND p.OrgId = @piOrgId
		INNER JOIN @ptblItemConfirmRequest icr ON i.ItemKey = icr.ItemKey
												AND i.ClientItemId = icr.ClientItemId;
		SET @iItemsUpdated = @@ROWCOUNT;

		--2018-08-06 Moved from below
		SELECT @pbiConfirmation = ProcessId
		FROM #ProcessConfirmRequestItem;

		IF @iProcessItemCount = 0 
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'TransactionKey and Item Confirmations Disconnect',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @pnvMsg = 'Your Transaction Key doesn''t match'
			SET @pbiConfirmation = -1;
			RETURN
		END
		ELSE IF @iProcessItemCount <> @iItemsUpdated
			OR @bUniqueItems = 0
			OR @iItemCount <> @iProcessItemCount
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Items Provided Do Not Match Original Transaction',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @pnvMsg = 'Items Provided Do Not Match Original Transaction Request'
			SET @pbiConfirmation = @iItemsUpdated * -1;
			RETURN
		END
		ELSE IF @iItemStatus = @iInitialItemStatusid
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item Confirmations not valid for Initial Status',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @pnvMsg = 'The Item Confirmations cant be applied to Items that have an Initial Status'
			SET @pbiConfirmation = @pbiConfirmation * -1;
			RETURN
		END
		ELSE IF @iItemStatus = @iFinalItemStatusId
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item Confirmations not valid for Final Status',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @pnvMsg = 'The Item Confirmations have already been finalized'
			SET @pbiConfirmation = @pbiConfirmation * -1;
			RETURN
		END
		ELSE IF @iItemStatus = @iReversedlItemStatusid-- > @iFinalItemStatusId 2020-09-1
		BEGIN
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			IF @iLogLevel > 0
				INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
				VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Item Confirmations not valid for Reversed Status',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
			SET @pnvMsg = 'The Item Confirmations have already been reversed'
			SET @pbiConfirmation = @pbiConfirmation * -1;
			RETURN
		END
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;		
		EXEC [error].[uspLogErrorDetailInsertOut2] @psSchemaName = @sSchemaName, @pnvProcessKey=@pnvProcessKey, @piErrorDetailId=@iErrorDetailId OUTPUT;
		IF @iLogLevel > 0
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit-ErrorDetailId ='+CONVERT(NCHAR(10),@iErrorDetailId),DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());
		THROW;
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;

		IF @iLogLevel > 0
		BEGIN
			INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
			VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Update Items',DATEDIFF(microsecond,@dtTimerDate,SYSDATETIME()),SYSDATETIME());		
			SET @dtTimerDate = SYSDATETIME();
		END

		--PROVIDE what ItemActivityUpdate needs
		--2022-04-04 INSERT INTO @tblItem(ItemId,RuleBreak,ItemStatusId,ClientAcceptedId,DateActivated)
		--2022-04-04 SELECT ItemId,RuleBreak,InsertedItemStatusId,InsertedClientAcceptedId,InsertedDateActivated
		INSERT INTO @tblItem(ItemId,Fee,Amount,RuleBreak,ItemStatusId,ClientAcceptedId,DateActivated)
		SELECT ItemId,InsertedFee,InsertedAmount,RuleBreak,InsertedItemStatusId,InsertedClientAcceptedId,InsertedDateActivated
		FROM #ProcessConfirmRequestItem;
		--2022-04-04
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
			,@pnvSrc = @ncObjectName;	--uspProcessConfirmationRequest

		SELECT i.ItemKey, icr.ClientItemId, icr.ClientAccepted as ConfirmAccepted
		FROM #ProcessConfirmRequestItem i 
		INNER JOIN @ptblItemConfirmRequest icr ON i.ItemKey = icr.ItemKey;

	END
	--Last Message uses @dtInitial
	IF @iLogLevel > 0
		INSERT INTO [dbo].[IFATiming](ProcessKey,SchemaName,ObjectName,Msg,Microseconds,DateExecuted)
		VALUES (@ncProcessKey,@ncSchemaName,@ncObjectName,N'Exit' ,DATEDIFF(microsecond,@dtInitial,SYSDATETIME()),SYSDATETIME()); 
END
