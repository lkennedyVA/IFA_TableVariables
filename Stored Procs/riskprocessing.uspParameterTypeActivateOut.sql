USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterTypeActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will Activate the ParameterType (Set StatusFlag)
	Tables: [riskprocessing].[ParameterType]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterTypeActivateOut](
	 @piParameterTypeId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ParameterType table (
		 ParameterTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime
		,UserName nvarchar(100));
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[ParameterType]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ParameterTypeId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @ParameterType
			WHERE ParameterTypeId = @piParameterTypeId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[ParameterType](ParameterTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT ParameterTypeId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @ParameterType
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piParameterTypeId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piParameterTypeId = ParameterTypeId
			FROM @ParameterType;
		END
	END
END
