USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspLadderDBProcessXrefInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-07-08
   Descr: This procedure will insert a new record
   Tables: [riskprocessing].[LadderDBProcessXref]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessXrefInsertOut](
    @pnvTitle NVARCHAR(255)
   ,@piLadderId INT
   ,@piDBProcessId INT
   ,@pnvDBProcessSuccessValue NVARCHAR(512)
   ,@piDBProcessSuccessLDBPXId INT
   ,@piDBProcessContinueLDBPXId INT
   ,@piStatusFlag INT
   ,@pnvUserName NVARCHAR(100) = 'N/A'
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
		,DateActivated datetime2(7)
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
			INSERT INTO [riskprocessing].[LadderDBProcessXref]
			OUTPUT inserted.LadderDBProcessXrefId
				,inserted.Title
				,inserted.LadderId
				,inserted.DBProcessId
				,inserted.DBProcessSuccessValue
				,inserted.DBProcessSuccessLDBPXId
				,inserted.DBProcessContinueLDBPXId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @LadderDBProcessXref
			SELECT @pnvTitle 
			,@piLadderId
			,@piDBProcessId
			,@pnvDBProcessSuccessValue
			,@piDBProcessSuccessLDBPXId
			,@piDBProcessContinueLDBPXId
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
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
			FROM @LadderDBProcessXref
		END
	END  
END
