USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspProcessMethodologyInsertOut
	CreatedBy: Larry Dugger
	Descr: This procedure will insert a new record
	Tables: [common].[ProcessMethodology]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2020-01-22 - LBD - Created
		2020-09-13 - LBD - Adjusted to work with new structure
*****************************************************************************************/
ALTER   PROCEDURE [common].[uspProcessMethodologyInsertOut](
	@pnvCode NVARCHAR(10)
	,@pnvName NVARCHAR(50)
	,@pnvDescr NVARCHAR(255)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piProcessMethodologyId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @ProcessMethodology table (
		ProcessMethodologyId int
		,Code nvarchar(25)
		,[Name] nvarchar(50)
		,Descr nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = OBJECT_SCHEMA_NAME(@@PROCID);
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [common].[ProcessMethodology]
			OUTPUT inserted.ProcessMethodologyId
			,inserted.Code
			,inserted.[Name]
			,inserted.Descr
			,inserted.StatusFlag
			,inserted.DateActivated
			,inserted.UserName
			INTO @ProcessMethodology
		SELECT @pnvCode
			,@pnvName
			,@pnvDescr
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piProcessMethodologyId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		SELECT @piProcessMethodologyId = ProcessMethodologyId
		FROM @ProcessMethodology
	END
END
