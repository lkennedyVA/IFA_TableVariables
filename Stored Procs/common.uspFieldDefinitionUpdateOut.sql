USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFieldDefinitionUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Format: This procedure will update the FieldDefinition, it will not update the StatusFlag
	Tables: [common].[FieldDefinition]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFieldDefinitionUpdateOut](
	 @piFieldDefinitionId INT
	,@pnvStructureReference NVARCHAR(255)
	,@piStatusFlag INT 
	,@pnvUserName NVARCHAR(100) = 'N/A'
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @FieldDefinition table (
		 FieldDefinitionId int
		,StructureReference nvarchar(255)
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128);
	SET @sSchemaName = N'common';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [common].[FieldDefinition]
		SET StructureReference = @pnvStructureReference
			,StatusFlag = @piStatusFlag
			,DateActivated = SYSDATETIME()
			,UserName = @pnvUserName
		OUTPUT deleted.FieldDefinitionId
			,deleted.StructureReference
			,deleted.StatusFlag
			,deleted.DateActivated
			,deleted.UserName
		INTO @FieldDefinition
		WHERE FieldDefinitionId = @piFieldDefinitionId;
		----Anytime an update occurs we place a copy in an archive table
		--INSERT INTO [archive].[FieldDefinition](
		--	FieldDefinitionId
		--	,StructureReference
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,DateArchived
		--) 
		--SELECT FieldDefinitionId
		--	,StructureReference
		--	,StatusFlag
		--	,DateActivated
		--	,UserName
		--	,SYSDATETIME()
		--FROM @FieldDefinition
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piFieldDefinitionId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW	
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		RETURN 1;
	END
END
