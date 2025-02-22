USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterValueActivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will Activate the ParameterValue (Set StatusFlag)
	Tables: [riskprocessing].[ParameterValue]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterValueActivateOut](
	 @piParameterValueId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ParameterValue table (
		 ParameterValueId int
		,[Value] nvarchar(512)
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
			UPDATE [riskprocessing].[ParameterValue]
			SET StatusFlag = 1
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ParameterValueId
				,deleted.[Value]
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @ParameterValue
			WHERE ParameterValueId = @piParameterValueId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[ParameterValue](ParameterValueId
			--,Value
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT ParameterValueId
			--,Value
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @ParameterValue
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piParameterValueId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piParameterValueId = ParameterValueId
			FROM @ParameterValue;
		END
	END
END
