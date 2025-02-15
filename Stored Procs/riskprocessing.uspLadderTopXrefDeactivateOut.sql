USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderTopXrefDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2015-11-12
	Descr: This procedure will DeActivate the LadderTopXref (Clear StatusFlag)
	Tables: [riskprocessing].[LadderTopXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-11-12 - LBD - Created.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderTopXrefDeactivateOut](
	 @piLadderTopXrefId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderTopXref table (
		 LadderTopXrefId int
		,Title nvarchar(255)
		,LadderTopId int
		,LadderSuccessValue nvarchar(512)
		,LadderSuccessLTXId int
		,LadderContinueLTXId int
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
			UPDATE [riskprocessing].[LadderTopXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.LadderTopXrefId
				,deleted.Title
				,deleted.LadderTopId
				,deleted.LadderSuccessValue
				,deleted.LadderSuccessLTXId
				,deleted.LadderContinueLTXId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @LadderTopXref
			WHERE LadderTopXrefId = @piLadderTopXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[LadderTopXref](LadderTopXrefId
			--,Title
			--,LadderTopId
			--,LadderSuccessValue
			--,LadderSuccessLTXId
			--,LadderContinueLTXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT LadderTopXrefId
			--,Title
			--,LadderTopId
			--,LadderSuccessValue
			--,LadderSuccessLTXId
			--,LadderContinueLTXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @LadderTopXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderTopXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderTopXrefId = LadderTopXrefId
			FROM @LadderTopXref;
		END
	END
END
