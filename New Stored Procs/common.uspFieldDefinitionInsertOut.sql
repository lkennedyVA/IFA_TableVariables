USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
   Name: uspFieldDefinitionInsertOut
   CreatedBy: Larry Dugger
   Date: 2015-05-26
   Format: This procedure will insert a new record
   Tables: [common].[FieldDefinition]
   
   Functions: [error].[uspLogErrorDetailInsertOut]
   History:
      2015-05-26 - LBD - Created
*******************************************************************************************************************************/
ALTER PROCEDURE [common].[uspFieldDefinitionInsertOut](
    @pnvStructureReference NVARCHAR(255)
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piFieldDefinitionId INT OUTPUT
)
AS
BEGIN
   SET NOCOUNT ON;
   DECLARE @FieldDefinition table (
       FieldDefinitionId int not null
      ,StructureReference nvarchar(255) not null
      ,StatusFlag int not null
      ,DateActivated datetime2(7) not null
		,UserName nvarchar(100)
		);
   DECLARE @iErrorDetailId INT
      ,@iCurrentTransactionLevel INT
      ,@sSchemaName nvarchar(128);
   SET @sSchemaName = N'common';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		INSERT INTO [common].[FieldDefinition](StructureReference)
			OUTPUT inserted.FieldDefinitionId
				,inserted.StructureReference
				,inserted.StatusFlag
				,inserted.DateActivated
				,inserted.UserName
			INTO @FieldDefinition
		SELECT @pnvStructureReference;
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
		SELECT @piFieldDefinitionId = FieldDefinitionId
		FROM @FieldDefinition
	END
END
