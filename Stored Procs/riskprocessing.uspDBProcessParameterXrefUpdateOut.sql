USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDBProcessParameterXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the DBProcessParameterXref, it will not update StatusFlag
	Tables: [riskprocessing].[DBProcessParameterXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessParameterXrefUpdateOut](
	 @piDBProcessId INT = -1
	,@piParameterId INT = -1
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piDBProcessParameterXrefID INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DBProcessParameterXref table (
		 DBProcessParameterXrefId int
		,DBProcessId int
		,ParameterId int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this DBProcessParameterXref to a DBProcessParameterXref already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[DBProcessParameterXref]
					WHERE DBProcessParameterXrefId <> @piDBProcessParameterXrefId
						AND DBProcessId = @piDBProcessId
						AND ParameterId = @piParameterId
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[DBProcessParameterXref]
			SET DBProcessId = CASE WHEN @piDBProcessId = -1 THEN DBProcessId ELSE @piDBProcessId END
				,ParameterId = CASE WHEN @piParameterId = -1 THEN ParameterId ELSE @piParameterId END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.DBProcessParameterXrefId
				,deleted.DBProcessId
				,deleted.ParameterId
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @DBProcessParameterXref
			WHERE DBProcessParameterXrefId = @piDBProcessParameterXrefId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[DBProcessParameterXref](DBProcessParameterXrefId
			--,DBProcessId
			--,ParameterId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT DBProcessParameterXrefId
			--,DBProcessId
			--,ParameterId
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @DBProcessParameterXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piDBProcessParameterXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piDBProcessParameterXrefID = DBProcessParameterXrefId
			FROM @DBProcessParameterXref;
		END
	END
	ELSE
		SELECT @piDBProcessParameterXrefID = -3
END
