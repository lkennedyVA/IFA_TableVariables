USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderTopUpsertOut
	CreatedBy: Larry Dugger
	Date: 2016-03-16
	Descr: This procedure will insert/update a laddertop record
	Tables: [riskprocessing].[LadderTop]
   
	Functions: [error].[uspLogErrorDetailInsertOut]

	History:
		2016-03-16 - LBD - Created
		2017-02-08 - LBD - Modified, removed use of [common].[ExitLevel], 
			[common].[Precedence], and [common].[LadderTrigger] table fields.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopUpsertOut](
	 @piRPId INT
	,@piLadderDBProcessXrefId INT = -1
	,@pnvCollectionName NVARCHAR(100)
	,@piStatusFlag INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piLadderTopId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderTop table (
		 LadderTopId int
		,RPId int
		,LadderDBProcessXrefId int
		,CollectionName nvarchar(100)
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--INSERT If it doesn't exist
	IF NOT EXISTS (SELECT 'X' 
					FROM [riskprocessing].[LadderTop]
					WHERE RPId = @piRPId
							AND CollectionName = @pnvCollectionName
							AND StatusFlag = @piStatusFlag)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [riskprocessing].[LadderTop]
			OUTPUT inserted.LadderTopId
				,inserted.RPId
				,inserted.LadderDBProcessXrefId
				,inserted.CollectionName
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @LadderTop
			SELECT @piRPId
				,@piLadderDBProcessXrefId
				,@pnvCollectionName
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName; 
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderTopId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderTopId = LadderTopId
			FROM @LadderTop
		END
	END
	--UPDATE Otherwise
	ELSE 
		BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[LadderTop]
			SET RPId = CASE WHEN @piRPId = -1 THEN RPId ELSE @piRPId END
				,LadderDBProcessXrefId = CASE WHEN @piLadderDBProcessXrefId = -1 THEN LadderDBProcessXrefId ELSE @piLadderDBProcessXrefId END
				,CollectionName = CASE WHEN @pnvCollectionName = N'' THEN CollectionName ELSE @pnvCollectionName END
				,StatusFlag = CASE WHEN @piStatusFlag = -1 THEN StatusFlag ELSE @piStatusFlag END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.LadderTopId
				,deleted.RPId
				,deleted.LadderDBProcessXrefId
				,deleted.CollectionName
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @LadderTop
			WHERE LadderTopId = @piLadderTopId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[LadderTop](LadderTopId
			--	,RPId
			--	,LadderDBProcessXrefId
			--	,CollectionName
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT LadderTopId
			--	,RPId
			--	,LadderDBProcessXrefId
			--	,CollectionName
			--	,StatusFlag
			--	,DateActivated 
			--	,UserName
			--	,SYSDATETIME()
			--FROM @LadderTop
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderTopId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderTopId = LadderTopId
			FROM @LadderTop;
		END
	END
END
