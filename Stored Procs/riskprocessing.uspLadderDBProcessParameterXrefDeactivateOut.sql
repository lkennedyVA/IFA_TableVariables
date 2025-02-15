USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderDBProcessParameterXrefDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will DeActivate the LadderDBProcessParameterXref (Clear StatusFlag)
	Tables: [riskprocessing].[LadderDBProcessParameterXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessParameterXrefDeactivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piLadderDBProcessParameterXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @LadderDBProcessParameterXref table (
		 LadderDBProcessParameterXrefId int
		,LadderDBProcessXrefId int
		,DBProcessParameterXrefId int
		,ParameterValueXrefId int
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
			UPDATE [riskprocessing].[LadderDBProcessParameterXref]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.LadderDBProcessParameterXrefId
				,deleted.LadderDBProcessXrefId
				,deleted.DBProcessParameterXrefId
				,deleted.ParameterValueXrefId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @LadderDBProcessParameterXref
			WHERE LadderDBProcessParameterXrefId = @piLadderDBProcessParameterXrefId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[LadderDBProcessParameterXref](LadderDBProcessParameterXrefId
			--,LadderDBProcessXrefId
			--,DBProcessParameterXrefId
			--,ParameterValueXrefId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT LadderDBProcessParameterXrefId
			--,LadderDBProcessXrefId
			--,DBProcessParameterXrefId
			--,ParameterValueXrefId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @LadderDBProcessParameterXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piLadderDBProcessParameterXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piLadderDBProcessParameterXrefId = LadderDBProcessParameterXrefId
			FROM @LadderDBProcessParameterXref;
		END
	END
END
