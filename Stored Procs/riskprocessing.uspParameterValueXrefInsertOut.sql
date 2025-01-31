USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterValueXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will insert a new record
	Tables: [riskprocessing].[ParameterValueXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-01-19 - LBD - Modified, more intelligent, returns Id, if not necessary to add
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterValueXrefInsertOut](
	 @piParameterId INT
	,@piParameterValueId INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A' 
	,@piParameterValueXrefId INT OUTPUT
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
		,UserName nvarchar(100));
	DECLARE @iParameterValueXrefId int = 0
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this ParameterValueXref to a ParameterValueXref already in use
	SELECT @iParameterValueXrefId = ParameterValueXrefId
	FROM [riskprocessing].[ParameterValueXref]
	WHERE ParameterId = @piParameterId
		AND ParameterValueId = @piParameterValueId
	IF @iParameterValueXrefId = 0
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			INSERT INTO [riskprocessing].[ParameterValueXref]
			OUTPUT inserted.ParameterValueXrefId
				,inserted.ParameterId
				,inserted.ParameterValueId
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @ParameterValueXref
			SELECT @piParameterId
			,@piParameterValueId
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
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
			SELECT @piParameterValueXrefId = ParameterValueXrefId
			FROM @ParameterValueXref
		END
	END
	ELSE
		SELECT @piParameterValueXrefId = @iParameterValueXrefId;  
END
