USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCollectionReportRequest
	CreatedBy: Larry Dugger
	Date: 2016-12-08
	Description: This procedure will initiate an return request

	Tables: [ifa].[Item]
		,[common].[ReturnCode]
	Functions: [common].[ufnUpDimensionByOrgIdILTF]
		,[common].[ufnTransactionType]
		,[common].[ufnDimension]

	History:
		2016-12-08 - LBD - Created
		2016-12-12 - LBD - Modified, added ReturnKey and CollectionKey!
		2016-12-14 - HDD - Modified, added missing commit.
		2018-03-21 - LBD - Modified, uses more efficient function
		2025-01-09 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspCollectionReportRequest](
	 @piOrgId INT										--Additional Security
	,@pnvCollectionKey NVARCHAR(25)
	,@pncRoutingNumber NCHAR(9)							 
	,@pnvAccountNumber NVARCHAR(50)						 
	,@pnvCheckNumber NVARCHAR(50)
	,@pmCheckAmount MONEY
	,@pmAmountCollected MONEY							--Amount Collected
	,@pdDateCollected DATE								--Date
	,@pnvUserName NVARCHAR(100) = 'N/A'					--This is the loginname
	,@pbiCollectionId BIGINT OUTPUT						--Collection Id of created record, if original Item is found
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #CollectionReportRequest
	create table #CollectionReportRequest(
		 CollectionId bigint NOT NULL
		,CollectionKey nvarchar(25) not null
		,ItemId bigint NOT NULL
		,AmountCollected money NOT NULL
		,DateCollected date NOT NULL 
		,StatusFlag int NOT NULL
		,DateActivated datetime2(7) NOT NULL
		,UserName nvarchar(100) NOT NULL
	);
	drop table if exists #Uol
	create table #Uol(
		 LevelId int
		,ChildId int
		,OrgId int
		,OrgName nvarchar(50)
		,TypeId int
		,[Type] nvarchar(25)
		,StatusFlag int
	);

	DECLARE @iOrgId int = @piOrgId
		,@iOrgDimensionId int = [common].[ufnDimension]('Organization')
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'ifa'
		,@iCurrentTransactionLevel int
		,@biItemId bigint = 0
		,@iReturnCodeId int = 0
		,@iStatusFlag int = 1
		,@iCollectionTypeId int = [common].[ufnTransactionType]('Collection');

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @pbiCollectionId = 0; --Initialize to not created

	INSERT INTO #Uol(LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag)
	SELECT LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag 
	FROM [common].[ufnUpDimensionByOrgIdILTF](@iOrgId,@iOrgDimensionId);

	SELECT @biItemId = i.ItemId 
	FROM [payer].[Payer] py 
	INNER JOIN [ifa].[Item] i on py.PayerId = i.PayerId
								AND i.CheckNumber = @pnvCheckNumber
								AND i.CheckAmount = @pmCheckAmount
	INNER JOIN [ifa].[Return] r on i.ItemId = r.ItemId
	INNER JOIN [ifa].[Process] p on i.ProcessId = p.ProcessId
	INNER JOIN #Uol uol on p.OrgId = uol.OrgId
	WHERE py.RoutingNumber = @pncRoutingNumber
		AND py.AccountNumber = @pnvAccountNumber;

	IF @biItemId > 0
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [ifa].[Collection](CollectionKey,ItemId,AmountCollected,DateCollected,StatusFlag,DateActivated,UserName)
				OUTPUT inserted.CollectionId
					,inserted.CollectionKey
					,inserted.ItemId
					,inserted.AmountCollected
					,inserted.DateCollected
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO #CollectionReportRequest
			SELECT @pnvCollectionKey 
				,@biItemId
				,@pmAmountCollected
				,@pdDateCollected
				,@iStatusFlag
				,SYSDATETIME()
				,@pnvUserName;
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			THROW;
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel 
		BEGIN
			COMMIT TRANSACTION;
			BEGIN TRANSACTION
			BEGIN TRY
				INSERT INTO [ifa].[TransactionKey](TransactionKey,TransactionId,TransactionTypeId,StatusFlag,DateActivated,UserName)
				SELECT CollectionKey,CollectionId,@iCollectionTypeId,@iStatusFlag,SYSDATETIME(),@pnvUserName
				FROM #CollectionReportRequest;
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW;
			END CATCH;
			IF @@TRANCOUNT > @iCurrentTransactionLevel --2016-12-14
				COMMIT TRANSACTION;
			SELECT @pbiCollectionId = CollectionId
			FROM #CollectionReportRequest;
		END	
	END	
	ELSE
		RAISERROR ('Cannot find Return matching provided info', 16, 1);
END
