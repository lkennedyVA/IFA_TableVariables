USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterDeactivateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will DeActivate the Parameter (Clear StatusFlag)
	Tables: [riskprocessing].[Parameter]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterDeactivateOut](
	 @piParameterId INT OUTPUT
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @Parameter table (
		 ParameterId int
		,ParameterTypeId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,Otput bit
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
			UPDATE [riskprocessing].[Parameter]
			SET StatusFlag = 0
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.ParameterId
				,deleted.ParameterTypeId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.Otput
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @Parameter
			WHERE ParameterId = @piParameterId;
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[Parameter](ParameterId
			--,ParameterTypeId
			--,Code
			--,Name
			--,Descr
			--,Otput
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,DateArchived
			--) 
			--SELECT ParameterId
			--,ParameterTypeId
			--,Code
			--,Name
			--,Descr
			--,Otput
			--,StatusFlag
			--,DateActivated
			--,UserName
			--,SYSDATETIME()
			--FROM @Parameter
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piParameterId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piParameterId = ParameterId
			FROM @Parameter;
		END
	END
END
