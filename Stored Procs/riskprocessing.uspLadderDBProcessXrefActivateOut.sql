USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderDBProcessXrefActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will Activate the LadderDBProcessXref (Set StatusFlag)
	Tables: [riskprocessing].[LadderDBProcessXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessXrefActivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piLadderDBProcessXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderDBProcessXref table (
		 LadderDBProcessXrefId int
		,Title nvarchar(255)
		,LadderId int
		,DBProcessId int
		,DBProcessSuccessValue nvarchar(512)
		,DBProcessSuccessLDBPXId int
		,DBProcessContinueLDBPXId int
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
			UPDATE [riskprocessing].[LadderDBProcessXref]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.LadderDBProcessXrefId
				,deleted.Title
				,deleted.LadderId
				,deleted.DBProcessId
				,deleted.DBProcessSuccessValue
				,deleted.DBProcessSuccessLDBPXId
				,deleted.DBProcessContinueLDBPXId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @LadderDBProcessXref
			WHERE LadderDBProcessXrefId = @piLadderDBProcessXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[LadderDBProcessXref](LadderDBProcessXrefId
			--,Title
			--,LadderId
			--,DBProcessId
			--,DBProcessSuccessValue
			--,DBProcessSuccessLDBPXId
			--,DBProcessContinueLDBPXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT LadderDBProcessXrefId
			--,Title
			--,LadderId
			--,DBProcessId
			--,DBProcessSuccessValue
			--,DBProcessSuccessLDBPXId
			--,DBProcessContinueLDBPXId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @LadderDBProcessXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderDBProcessXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderDBProcessXrefId = LadderDBProcessXrefId
			FROM @LadderDBProcessXref;
		END
	END
END
