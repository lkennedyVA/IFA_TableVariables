USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderDBProcessParameterXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will insert a new record
	Tables: [riskprocessing].[LadderDBProcessParameterXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-03-08 - LBD - Modified, assde StatusFlag to 'check'
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut](
	 @piLadderDBProcessXrefId INT
	,@piDBProcessParameterXrefId INT
	,@piParameterValueXrefId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
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
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @piLadderDBProcessParameterXrefId = 0;
	--Will Not insert this LadderDBProcessParameterXref to a combination already in use
	SELECT @piLadderDBProcessParameterXrefId = LadderDBProcessParameterXrefId
	FROM [riskprocessing].[LadderDBProcessParameterXref]
	WHERE LadderDBProcessXrefId = @piLadderDBProcessXrefId
		AND DBProcessParameterXrefId = @piDBProcessParameterXrefId
		AND StatusFlag = 1
	IF @piLadderDBProcessParameterXrefId = 0
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [riskprocessing].[LadderDBProcessParameterXref]
			OUTPUT inserted.LadderDBProcessParameterXrefId
				,inserted.LadderDBProcessXrefId
				,inserted.DBProcessParameterXrefId
				,inserted.ParameterValueXrefId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @LadderDBProcessParameterXref
			SELECT @piLadderDBProcessXrefId
			,@piDBProcessParameterXrefId
			,@piParameterValueXrefId
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
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
			FROM @LadderDBProcessParameterXref
		END
	END
END
