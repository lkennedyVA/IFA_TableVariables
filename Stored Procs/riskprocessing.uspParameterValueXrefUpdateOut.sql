USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterValueXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the ParameterValueXref, it will not update StatusFlag
	Tables: [riskprocessing].[ParameterValueXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterValueXrefUpdateOut](
	 @piParameterValueXrefID INT OUTPUT
	,@piParameterId INT = -1
	,@piParameterValueId INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ParameterValueXref table (
		 ParameterValueXrefId int
		,ParameterId int
		,ParameterValueId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this ParameterValueXref to a ParameterValueXref already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[ParameterValueXref]
					WHERE ParameterValueXrefId <> @piParameterValueXrefId
						AND ParameterId = @piParameterId
						AND ParameterValueId = @piParameterValueId
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[ParameterValueXref]
			SET ParameterId = CASE WHEN @piParameterId = -1 THEN ParameterId ELSE @piParameterId END
				,ParameterValueId = CASE WHEN @piParameterValueId = -1 THEN ParameterValueId ELSE @piParameterValueId END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ParameterValueXrefId
				,deleted.ParameterId
				,deleted.ParameterValueId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @ParameterValueXref
			WHERE ParameterValueXrefId = @piParameterValueXrefId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[ParameterValueXref](ParameterValueXrefId
			--,ParameterId
			--,ParameterValueId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT ParameterValueXrefId
			--,ParameterId
			--,ParameterValueId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @ParameterValueXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piParameterValueXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piParameterValueXrefID = ParameterValueXrefId
			FROM @ParameterValueXref;
		END
	END
	ELSE
		SELECT @piParameterValueXrefID = -3
END
