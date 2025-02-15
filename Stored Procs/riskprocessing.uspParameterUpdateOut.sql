USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspParameterUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the Parameter, it will not update StatusFlag
	Tables: [riskprocessing].[Parameter]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspParameterUpdateOut](
	 @piParameterID INT OUTPUT
	,@piParameterTypeId INT = -1
	,@pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@pbOtput BIT
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
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this Parameter to a Parameter already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[Parameter]
					WHERE ParameterId <> @piParameterId
						AND ([Name] = @pnvName
						OR Code = @pnvCode)
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[Parameter]
			SET ParameterTypeId = CASE WHEN @piParameterTypeId = -1 THEN ParameterTypeId ELSE @piParameterTypeId END
				,Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,Otput = @pbOtput
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
			----Anytime an update occurs we place a copy in an archive table
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
			SELECT @piParameterID = ParameterId
			FROM @Parameter;
		END
	END
	ELSE
		SELECT @piParameterID = -3
END
