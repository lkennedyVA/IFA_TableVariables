USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRPUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-07-08
	Descr: This procedure will update the RP, it will not update RPTypeId or StatusFlag
	Tables: [riskprocessing].[RP]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-07-08 - LBD - Created, from Validbank
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRPUpdateOut](
	 @piRPId INT OUTPUT
	,@pnvCode NVARCHAR(25) = N''
	,@pnvName NVARCHAR(50) = N''
	,@pnvDescr NVARCHAR(255) = N''
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @RP table (
		 RPId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Will Not update this RP to a RP already in use
	IF NOT EXISTS(SELECT 'X' 
					FROM [riskprocessing].[RP]
					WHERE RPId <> @piRPId
						AND ([Name] = @pnvName
						OR Code = @pnvCode)
					)
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [riskprocessing].[RP]
			SET Code = CASE WHEN @pnvCode = N'' THEN Code ELSE @pnvCode END
				,[Name] = CASE WHEN @pnvName = N'' THEN [Name] ELSE @pnvName END
				,Descr = CASE WHEN @pnvDescr = N'' THEN Descr ELSE @pnvDescr END
				,DateActivated = SYSDATETIME()
				,UserName = @pnvUserName
			OUTPUT deleted.RPId
				,deleted.Code
				,deleted.[Name]
				,deleted.Descr
				,deleted.StatusFlag
				,deleted.DateActivated
				,deleted.UserName
			INTO @RP
			WHERE RPId = @piRPId;
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[RP](RPId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,DateArchived
			--) 
			--SELECT RPId
			--,Code
			--,Name
			--,Descr
			--,StatusFlag
			--,DateActivated
			--	,UserName
			--,SYSDATETIME()
			--FROM @RP
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piRPId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piRPId = RPId
			FROM @RP;
		END
	END
	ELSE
		SELECT @piRPId = -3
END
