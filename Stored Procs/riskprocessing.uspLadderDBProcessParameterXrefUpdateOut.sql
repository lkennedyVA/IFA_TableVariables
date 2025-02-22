USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspLadderDBProcessParameterXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the LadderDBProcessParameterXref.ParameterValueXrefId
		,it will not update StatusFlag

	Tables: [riskprocessing].[LadderDBProcessParameterXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]

	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-03-08 - LBD - Modified, adjusted to prevent creating a duplicate record,
			which already exists. We are allowing a parameter value to be changed
			for an existing record.
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspLadderDBProcessParameterXrefUpdateOut](
	 @piLadderDBProcessXrefId INT
	,@piDBProcessParameterXrefId INT
	,@piParameterValueXrefId INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piLadderDBProcessParameterXrefID INT OUTPUT
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
	--Will Not update this LadderDBProcessParameterXref to a LadderDBProcessParameterXref already in use
	IF NOT EXISTS (SELECT 'X' 
					FROM [riskprocessing].[LadderDBProcessParameterXref]
					WHERE LadderDBProcessParameterXrefId <> @piLadderDBProcessParameterXrefId
						AND LadderDBProcessXrefId = @piLadderDBProcessXrefId
						AND DBProcessParameterXrefId = @piDBProcessParameterXrefId
						AND StatusFlag = 1
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[LadderDBProcessParameterXref]
			SET ParameterValueXrefId = CASE WHEN @piParameterValueXrefId = -1 THEN ParameterValueXrefId ELSE @piParameterValueXrefId END
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
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[LadderDBProcessParameterXref](LadderDBProcessParameterXrefId
			--	,LadderDBProcessXrefId
			--	,DBProcessParameterXrefId
			--	,ParameterValueXrefId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT LadderDBProcessParameterXrefId
			--	,LadderDBProcessXrefId
			--	,DBProcessParameterXrefId
			--	,ParameterValueXrefId
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,SYSDATETIME()
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
			SELECT @piLadderDBProcessParameterXrefID = LadderDBProcessParameterXrefId
			FROM @LadderDBProcessParameterXref;
		END
	END
	ELSE
		SELECT @piLadderDBProcessParameterXrefID = -3
END
