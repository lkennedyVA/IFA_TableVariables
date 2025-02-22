USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspDBProcessParameterXrefActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will Activate the DBProcessParameterXref (Set StatusFlag)
	Tables: [riskprocessing].[DBProcessParameterXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspDBProcessParameterXrefActivateOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
	,@piDBProcessParameterXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @DBProcessParameterXref table (
		 DBProcessParameterXrefId int
		,DBProcessId int
		,ParameterId int
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
			UPDATE [riskprocessing].[DBProcessParameterXref]
			SET StatusFlag = 1
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
			----Anytime an update occurs we place an original copy in an archive table
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
			SELECT @piDBProcessParameterXrefId = DBProcessParameterXrefId
			FROM @DBProcessParameterXref;
		END
	END
END
