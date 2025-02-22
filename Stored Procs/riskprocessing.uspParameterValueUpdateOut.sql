USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterValueUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the ParameterValue, it will not update StatusFlag
	Tables: [riskprocessing].[ParameterValue]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterValueUpdateOut](
	 @piParameterValueId INT OUTPUT
	,@pnvValue NVARCHAR(512) = N''
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ParameterValue table (
		 ParameterValueId int
		,[Value] nvarchar(512)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100));
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this ParameterValue to a ParameterValue already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[ParameterValue]
					WHERE ParameterValueId <> @piParameterValueId
						AND ([Value] = @pnvValue)
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[ParameterValue]
			SET [Value] = CASE WHEN @pnvValue = N'' THEN [Value] ELSE @pnvValue END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ParameterValueId
				,deleted.[Value]
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @ParameterValue
			WHERE ParameterValueId = @piParameterValueId;
			----Anytime an update occurs we place a copy in an archive table
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
	ELSE
		SELECT @piParameterValueId = -3
END
