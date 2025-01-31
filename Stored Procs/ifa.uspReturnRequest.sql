USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspReturnRequest
	CreatedBy: Larry Dugger
	Date: 2016-12-08
	Description: This procedure will initiate an return request

	Tables: [ifa].[Item]
		,[common].[ReturnCode]

	Functions: [common].[ufnTransactionType]

	History:
		2016-12-08 - LBD - Created
		2016-12-12 - LBD - Modified, added ReturnKey!
		2016-12-14 - HDD - Modified, retrieving the ReturnKey associated with the query.
		2017-08-21 - LBD - Modified, adjusted output message to new V106 exceptions
		2017-09-17 - LBD - Modified, adjusted last output message
		2018-03-14 - LBD - Modified, Doesn't use uncessary function
		2025-01-14 - LXK - Replaced table variables with local temp tables
*****************************************************************************************/
ALTER PROCEDURE [ifa].[uspReturnRequest](
	 @piOrgId INT										--Additional Security
	,@pnvReturnKey NVARCHAR(25)							--This is the TransactionKey tied to a return, that will be established
	,@pnvItemKey NVARCHAR(25)							--This is 'TransactionKey' that was passed to the client (for item) 
	,@pnvReturnCode NVARCHAR(25)						--ReturnCode
	,@pdDateReturned DATE								--date
	,@pnvUserName NVARCHAR(100) = 'N/A'					--This is the loginname
	,@pbiReturnId BIGINT OUTPUT							--Return Id of created record, if original Item is found
)
AS
BEGIN
	SET NOCOUNT ON;
	drop table if exists #ReturnRequestReturns
	create table #ReturnRequestReturns(
		 ReturnId bigint 
		,ReturnKey nvarchar(25)
		,ItemId bigint 
		,ReturnCodeId int 
		,DateReturned date
		,StatusFlag int 
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	drop table if exists #ReturnRequestUol
	create table #ReturnRequestUol(
		 LevelId int
		,ChildId int
		,OrgId int
		,OrgName nvarchar(50)
		,TypeId int
		,[Type] nvarchar(25)
		,StatusFlag int
	);

	DECLARE @iOrgId int = @piOrgId
		,@iErrorDetailId int
		,@sSchemaName nvarchar(128) = N'ifa'
		,@iCurrentTransactionLevel int
		,@biItemId bigint = 0
		,@iReturnCodeId int = 0
		,@iStatusFlag int = 1
		,@iItemTypeId int = [common].[ufnTransactionType]('Item')
		,@iReturnTypeId int = [common].[ufnTransactionType]('Return');

	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @pbiReturnId = 0; --Initialize to not created

	--2018-03-21 uneccessary
	--INSERT INTO #ReturnRequestUol(LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag)
	--SELECT LevelId, ChildId, OrgId, OrgName,TypeId, [Type] ,StatusFlag 
	--FROM [common].[ufnUpOrgListByOrgId](@piOrgId);

	SELECT @biItemId = ItemId 
	FROM [ifa].[TransactionKey] tk
	INNER JOIN [ifa].[Item] i on tk.TransactionId = i.ItemId
	INNER JOIN [ifa].[Process] p on i.ProcessId = p.ProcessId
	--INNER JOIN #ReturnRequestUol uol on p.OrgId = uol.OrgId 2018-03-12 uneccessary
	WHERE tk.TransactionKey = @pnvItemKey
		AND tk.TransactionTypeId = @iItemTypeId
		AND p.OrgId = @iOrgId; --2018-03-12 better

	--Does it already exists
	IF @biItemId > 0
		SELECT @pbiReturnId = ReturnId
			,@pnvReturnKey = ReturnKey --2016-12-14
		FROM [ifa].[Return] 
		WHERE ItemId = @biItemId;

	IF @pbiReturnId > 0
	BEGIN
		--RAISERROR ('%I64d has already been associated with Item %s', 16, 1,@pbiReturnId,@nvTransactionKey);
		RAISERROR ('Item has already been associated with a ReturnKey', 16, 1,@pnvReturnKey);
		RETURN
	END

	SELECT @iReturnCodeId = ReturnCodeId
	FROM [common].[ReturnCode] 
	WHERE Code = @pnvReturnCode

	IF @iReturnCodeId = 0
	BEGIN
		RAISERROR ('Invalid ReturnCode', 16, 1,@pnvReturnCode);
		RETURN
	END

	IF @biItemId > 0
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [ifa].[Return](ReturnKey,ItemId,ReturnCodeId,DateReturned,StatusFlag,DateActivated,UserName)
				OUTPUT inserted.ReturnId
					,inserted.ReturnKey
					,inserted.ItemId
					,inserted.ReturnCodeId
					,inserted.DateReturned
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO #ReturnRequestReturns
			SELECT @pnvReturnKey 
				,@biItemId
				,@iReturnCodeId
				,@pdDateReturned
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
				SELECT ReturnKey,ReturnId,@iReturnTypeId,@iStatusFlag,SYSDATETIME(),@pnvUserName
				FROM #ReturnRequestReturns;
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW;
			END CATCH;
			IF @@TRANCOUNT > @iCurrentTransactionLevel 
				COMMIT TRANSACTION;
			SELECT @pbiReturnId = ReturnId
			FROM #ReturnRequestReturns;
		END	
	END	
	ELSE
		RAISERROR ('Your Transaction Key doesn''t match', 16, 1);

END
