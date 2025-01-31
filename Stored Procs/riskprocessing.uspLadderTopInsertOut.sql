USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderTopInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will insert a new record
	Tables: [riskprocessing].[LadderTop]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
			,adjusted to use OrgXrefId instead of OrgId so Dimension is accounted for.
		2017-02-08 - LBD - Modified, removed use of [common].[ExitLevel], 
			[common].[Precedence], and [common].[LadderTrigger] table fields.
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopInsertOut](
	@piRPId INT
	,@piLadderDBProcessXrefId INT
	,@pnvCollectionName nvarchar(100)
	,@piStatusFlag INT
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
		,UserName nvarchar(100));
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this LadderTop to a LadderTop already in use
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
	ELSE
		SELECT @piLadderTopId = -3      
END
