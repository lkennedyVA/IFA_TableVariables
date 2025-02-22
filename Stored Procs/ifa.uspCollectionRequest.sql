USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspCollectionRequest
	CreatedBy: Larry Dugger
	Date: 2016-12-08
	Description: This procedure will initiate an collection request

	Tables: [ifa].[Item]
	Functions: [common].[ufnUpDimensionByOrgIdILTF]
		,[common].[ufnTransactionType]
		,[common].[ufnDimension]

	History:
		2016-12-08 - LBD - Created
		2016-12-12 - LBD - Modified, added ReturnKey and CollectionKey!
		2016-12-14 - HDD - Modified, added missing commit.
		2017-08-21 - LBD - Modified, adjusted output message to new V106 exceptions
		2018-03-14 - LBD - Modified, uses more efficient function
		2025-01-09 - LXK - Replaced table variables with local tables
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspCollectionRequest](
	 @piOrgId INT										--Additional Security
	,@pnvCollectionKey NVARCHAR(25)
	,@pnvReturnKey NVARCHAR(25)							--This is the TransactionKey tied to a return, that will be established
	,@pmAmountCollected MONEY							--Amount Collected
	,@pdDateCollected DATE								--Date
	,@pnvUserName NVARCHAR(100) = 'N/A'					--This is the loginname
	,@pbiCollectionId BIGINT OUTPUT						--Collection Id of created record, if original Item is found
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #CollectionRequest
	create table #CollectionRequest(
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
		,@iStatusFlag int = 1
		,@iReturnTypeId int = [common].[ufnTransactionType]('Return')
		,@iCollectionTypeId int = [common].[ufnTransactionType]('Collection');

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @pbiCollectionId = 0; --Initialize to not created

	INSERT INTO #Uol(LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag)
	SELECT LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag 
	FROM [common].[ufnUpDimensionByOrgIdILTF](@iOrgId, @iOrgDimensionId);

	SELECT @biItemId = i.ItemId 
	FROM  [ifa].[TransactionKey] tk
	INNER JOIN [ifa].[Return] r on tk.TransactionId = r.ReturnId
	INNER JOIN [ifa].[Item] i on r.ItemId = i.ItemId
	INNER JOIN [ifa].[Process] p on i.ProcessId = p.ProcessId
	INNER JOIN #Uol uol on p.OrgId = uol.OrgId
	WHERE tk.TransactionKey = @pnvReturnKey
		AND tk.TransactionTypeId = @iReturnTypeId;

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
				INTO #CollectionRequest
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
				FROM #CollectionRequest;
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
			FROM #CollectionRequest;
		END	
	END	
	ELSE
		RAISERROR ('Invalid ReturnKey', 16, 1,@pnvReturnKey);	
END
