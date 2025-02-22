USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderTopNeverActiveOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will set the StatusFlag to 3 'NeverActive'
	Tables: [riskprocessing].[LadderTop]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
			,adjusted to use OrgXrefId instead of OrgId so Dimension is accounted for.
		2017-02-08 - LBD - Modified, removed use of [common].[ExitLevel], 
			[common].[Precedence], and [common].[LadderTrigger] table fields.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopNeverActiveOut](
	 @piLadderTopId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[LadderTop]
			SET StatusFlag = 3
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
			----Anytime an update occurs we place an original copy in an archive table
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
